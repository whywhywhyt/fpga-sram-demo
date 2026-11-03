// Natural-color enhancement at the causal Prewitt center (x-1,y-1).
// RGB888/MSB-first, four pixels/beat, exactly three registered stages.
// Three strengths share a gentler S-curve; no separate chroma arithmetic.
// Fine-contrast noise is not treated as useful sharpening detail.
// Per-channel contrast increases color separation together with luminance.
// Same storage and three-stage interface as the accepted mild version.
// One synchronous read-before-write RGB row, no multipliers/frame buffer.
// edge_mask is the SAME beat's three-stage Prewitt output, not a request.
module natural_enhance_96 #(
    parameter integer IMG_WIDTH=1280, IMG_HEIGHT=720
)(
    input wire clk,rst_n,user,valid,
    input wire [95:0] data,
    input wire [1:0] level, // 1 LOW (identity tone), 2 MEDIUM, 3 HIGH
    input wire [3:0] edge_mask,
    output wire [95:0] color,
    output wire [95:0] cartoon_color
);
    localparam integer GROUPS=IMG_WIDTH/4;
    localparam integer XW=(GROUPS<2)?1:$clog2(GROUPS);
    localparam integer YW=(IMG_HEIGHT<2)?1:$clog2(IMG_HEIGHT);
    (* ram_style="block" *) reg [95:0] row [0:GROUPS-1];
    reg [XW-1:0] x,wx;
    reg [YW-1:0] y,wy;
    wire [XW-1:0] cx=user?{XW{1'b0}}:x;
    wire [YW-1:0] cy=user?{YW{1'b0}}:y;
    reg [95:0] previous_row;
    // The older neighbor is used only as luma; retaining its full RGB wastes
    // 16 flip-flops. Preserve the center RGB and the exact 8-bit neighbor luma.
    reg [23:0] previous_center;
    reg [7:0] previous_left_luma;
    reg wvalid;
    reg [95:0] tone2,sat3;
    reg [95:0] cartoon2,cartoon3;
    reg [23:0] cartoon_left;
    // Horizontal [1,2,1] smoothing uses the SAME full-color row as enhancement.
    // An eight-level palette keeps skin and pale objects more legible than
    // the old four-level prototype. No new line RAM, DSP or stream latency.
    function [7:0] cartoon_channel;
        input [7:0] left,center,right;
        reg [9:0] sum;
        reg [8:0] rounded;
        reg [2:0] q;
        begin
            sum={2'b0,left}+{1'b0,center,1'b0}+{2'b0,right}+10'd2;
            rounded={1'b0,sum[9:2]}+9'd16;
            q=rounded>=256?3'd7:rounded[7:5];
            cartoon_channel={q,q,q[2:1]};
        end
    endfunction
    function [23:0] cartoon_pixel;
        input [23:0] left,center,right;
        begin cartoon_pixel={cartoon_channel(left[23:16],center[23:16],right[23:16]),
                             cartoon_channel(left[15:8],center[15:8],right[15:8]),
                             cartoon_channel(left[7:0],center[7:0],right[7:0])};end
    endfunction

    reg [15:0] detail2,detail3; // Bounded to +/-7; no extra line storage.
    reg [1:0] level1;
    function [7:0] clip;
        input signed [9:0] v;
        begin clip=v<0?8'd0:v>255?8'd255:v[7:0];end
    endfunction
    function [7:0] luma;
        input [23:0] p;
        reg [9:0] s;
        begin
            s={2'b0,p[23:16]}+{1'b0,p[15:8],1'b0}+{2'b0,p[7:0]};
            luma=s[9:2];
        end
    endfunction
    function [7:0] strong_curve;
        input [7:0] v;
        reg [8:0] middle;
        reg [8:0] outer;
        begin
            // Slopes .75 / 1.25 / .75 versus prior .5 / 1.5 / .5.
            // Less crushing of shadows and less amplification of midtone noise.
            middle={1'b0,v}+{3'b0,v[7:2]}-9'd32;
            outer={2'b0,v[7:1]}+{3'b0,v[7:2]}+(v[7]?9'd64:9'd0);
            strong_curve=(v[7]^v[6])?middle[7:0]:outer[7:0];
        end
    endfunction
    function [7:0] curve;
        input [7:0] v;
        input [1:0] strength;
        reg [8:0] blend;
        begin
            blend={1'b0,v}+{1'b0,strong_curve(v)};
            curve=strength==1?v:strength==2?blend[8:1]:strong_curve(v);
        end
    endfunction
    function [23:0] contrast;
        input [23:0] p;
        input [1:0] strength;
        begin contrast={curve(p[23:16],strength),curve(p[15:8],strength),curve(p[7:0],strength)};end
    endfunction
    function [3:0] detail;
        input [7:0] left_luma;
        input [23:0] center,right;
        input [1:0] strength;
        reg signed [10:0] d;
        reg signed [3:0] bounded;
        begin
            d=($signed({2'b0,luma(center),1'b0})-$signed({3'b0,left_luma})-$signed({3'b0,luma(right)}))>>>1;
            if(d>= -5 && d<=5)bounded=0;
            else if(d>7)bounded=4'sd7;
            else if(d< -7)bounded=-4'sd7;
            else bounded=d[3:0];
            detail=strength==1?(bounded>>>2):strength==2?(bounded>>>1):bounded;
        end
    endfunction
    function [23:0] sharpen;
        input [23:0] p;
        input signed [3:0] d;
        input enabled;
        reg signed [9:0] correction;
        begin
            correction=enabled?{{6{d[3]}},d}:10'sd0;
            sharpen={clip($signed({2'b0,p[23:16]})+correction),
                     clip($signed({2'b0,p[15:8]})+correction),
                     clip($signed({2'b0,p[7:0]})+correction)};
        end
    endfunction
    wire row_ok=wy>=2;
    wire left_ok=row_ok && wx!=0;
    wire [23:0] p0=previous_center;
    wire [23:0] p1=previous_row[95:72];
    wire [23:0] p2=previous_row[71:48];
    wire [23:0] p3=previous_row[47:24];
    // Synchronous RAM output. No reset on memory or read register.
    always @(posedge clk) if(rst_n && valid) begin
        previous_row<=row[cx];
        row[cx]<=data;
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            x<=0;y<=0;wx<=0;wy<=0;wvalid<=0;
            previous_center<=0;previous_left_luma<=0;tone2<=0;sat3<=0;cartoon2<=0;cartoon3<=0;cartoon_left<=0;detail2<=0;detail3<=0;level1<=2;
        end else begin
            wvalid<=valid;
            if(user)begin x<=0;y<=0;end
            if(valid)begin
                wx<=cx;wy<=cy;
                level1<=level;
                x<=(cx==GROUPS-1)?0:cx+1'b1;
                y<=(cx==GROUPS-1)?((cy==IMG_HEIGHT-1)?0:cy+1'b1):cy;
            end
            if(wvalid)begin
                cartoon2<={left_ok?cartoon_pixel(cartoon_left,p0,p1):24'd0,
                           left_ok?cartoon_pixel(p0,p1,p2):24'd0,
                           row_ok?cartoon_pixel(p1,p2,p3):24'd0,
                           row_ok?cartoon_pixel(p2,p3,previous_row[23:0]):24'd0};
                cartoon_left<=(wx==GROUPS-1)?24'd0:previous_row[47:24];
                tone2<={left_ok?contrast(p0,level1):24'd0,left_ok?contrast(p1,level1):24'd0,
                        row_ok?contrast(p2,level1):24'd0,row_ok?contrast(p3,level1):24'd0};
                detail2<={left_ok?detail(previous_left_luma,p0,p1,level1):4'd0,
                          left_ok?detail(luma(p0),p1,p2,level1):4'd0,
                          row_ok?detail(luma(p1),p2,p3,level1):4'd0,
                          row_ok?detail(luma(p2),p3,previous_row[23:0],level1):4'd0};
                previous_center<=(wx==GROUPS-1)?24'd0:previous_row[23:0];
                previous_left_luma<=(wx==GROUPS-1)?8'd0:luma(previous_row[47:24]);
            end else begin tone2<=0;detail2<=0;cartoon2<=0;end
            cartoon3<=cartoon2;
            sat3<=tone2; // Keep latency, spend saved chroma logic on visible levels.
            detail3<=detail2;
        end
    end
    assign cartoon_color={edge_mask[3]?24'd0:cartoon3[95:72],edge_mask[2]?24'd0:cartoon3[71:48],
                          edge_mask[1]?24'd0:cartoon3[47:24],edge_mask[0]?24'd0:cartoon3[23:0]};
    assign color={sharpen(sat3[95:72],detail3[15:12],edge_mask[3]),
                  sharpen(sat3[71:48],detail3[11:8],edge_mask[2]),
                  sharpen(sat3[47:24],detail3[7:4],edge_mask[1]),
                  sharpen(sat3[23:0],detail3[3:0],edge_mask[0])};
endmodule
