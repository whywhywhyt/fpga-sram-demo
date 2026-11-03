// Original four-pixel RGB888 Prewitt implementation for lab_ex_1.
// MSB-first pixels; 1280 pixels/line = 320 input beats.
// Causal window: output (x,y) represents center (x-1,y-1).
// Top two rows and left two columns are black. Every pixel is evaluated.
// Frame-start is an independent pulse preceding valid in the official ISP.
// No elastic output buffer: I_tready is tied high in this project.
module prewitt_detect_96 #(
    parameter integer IMG_WIDTH = 1280,
    parameter integer IMG_HEIGHT = 720,
    parameter [10:0] EDGE_TH = 11'd96
)(
    input wire I_clk, I_rst_n,
    input wire I_tlast, I_tuser,
    input wire [95:0] I_tdata,
    input wire I_tvalid, I_tready,
    input wire [10:0] threshold,
    output reg O_tlast, O_tuser,
    output reg [95:0] O_tdata,
    output reg O_tvalid,
    output wire O_tready
);
    localparam integer GROUPS = IMG_WIDTH / 4;
    localparam integer X_W = (GROUPS <= 1) ? 1 : $clog2(GROUPS);
    localparam integer Y_W = (IMG_HEIGHT <= 1) ? 1 : $clog2(IMG_HEIGHT);
    assign O_tready = I_tready;
    wire accept = I_tvalid && I_tready;
    function [7:0] luminance;
        input [23:0] p;
        reg [8:0] sum;
        begin
            sum = {3'b0,p[23:18]} + {2'b0,p[15:9]} + {3'b0,p[7:2]};
            luminance = sum[7:0];
        end
    endfunction
    wire [31:0] gray = {luminance(I_tdata[95:72]),
                        luminance(I_tdata[71:48]),
                        luminance(I_tdata[47:24]),
                        luminance(I_tdata[23:0])};
    // Synchronous read-before-write buffers; no memory reset, permitting ERAM.
    // First two rows mask samples left over from earlier frames.
    (* ram_style = "block" *) reg [31:0] line1 [0:GROUPS-1];
    (* ram_style = "block" *) reg [31:0] line2 [0:GROUPS-1];
    reg [X_W-1:0] x_group;
    reg [Y_W-1:0] y_line;
    wire [X_W-1:0] x_cur = I_tuser ? {X_W{1'b0}} : x_group;
    wire [Y_W-1:0] y_cur = I_tuser ? {Y_W{1'b0}} : y_line;
    reg [31:0] top, middle, bottom;
    reg [X_W-1:0] window_x;
    reg [Y_W-1:0] window_y;
    reg window_valid, window_last, window_user;
    reg [10:0] window_threshold;
    always @(posedge I_clk) begin
        if (I_rst_n && accept) begin
            top <= line2[x_cur];
            middle <= line1[x_cur];
            bottom <= gray;
            line1[x_cur] <= gray;
        end
        // Delay the second-row write by one cycle, using the synchronous
        // line1 output rather than an asynchronous memory-to-memory path.
        if (I_rst_n && window_valid) line2[window_x] <= middle;
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            x_group <= 0; y_line <= 0;
            window_x <= 0; window_y <= 0;
            window_valid <= 0; window_last <= 0; window_user <= 0; window_threshold <= EDGE_TH;
        end else begin
            window_valid <= accept;
            window_threshold <= threshold;
            window_last <= accept && (x_cur == GROUPS-1);
            window_user <= I_tuser;
            if (I_tuser) begin x_group <= 0; y_line <= 0; end
            if (accept) begin
                window_x <= x_cur; window_y <= y_cur;
                // Fixed line length tolerates bubbles and AWB falling-valid
                // tlast; I_tlast cannot accidentally delimit a short line.
                if (x_cur == GROUPS-1) begin
                    x_group <= 0;
                    y_line <= (y_cur == IMG_HEIGHT-1) ? 0 : y_cur + 1'b1;
                end else begin
                    x_group <= x_cur + 1'b1;
                    y_line <= y_cur;
                end
            end
        end
    end
    function [21:0] edge_gradient;
        input [23:0] a, b, c;
        reg signed [10:0] gx, gy;
        begin
            gx = $signed({3'b0,a[7:0]}) + $signed({3'b0,b[7:0]}) + $signed({3'b0,c[7:0]})
               - $signed({3'b0,a[23:16]}) - $signed({3'b0,b[23:16]}) - $signed({3'b0,c[23:16]});
            gy = $signed({3'b0,a[23:16]}) + $signed({3'b0,a[15:8]}) + $signed({3'b0,a[7:0]})
               - $signed({3'b0,c[23:16]}) - $signed({3'b0,c[15:8]}) - $signed({3'b0,c[7:0]});
            edge_gradient = {gy,gx};
        end
    endfunction
    reg [15:0] previous_top, previous_middle, previous_bottom;
    wire row_ok = window_y >= 2;
    wire left_ok = row_ok && window_x != 0;
    wire [21:0] g0 = edge_gradient({previous_top,top[31:24]},
                             {previous_middle,middle[31:24]},
                             {previous_bottom,bottom[31:24]});
    wire [21:0] g1 = edge_gradient({previous_top[7:0],top[31:16]},
                             {previous_middle[7:0],middle[31:16]},
                             {previous_bottom[7:0],bottom[31:16]});
    wire [21:0] g2 = edge_gradient(top[31:8],middle[31:8],bottom[31:8]);
    wire [21:0] g3 = edge_gradient(top[23:0],middle[23:0],bottom[23:0]);
    reg [21:0] gradient0,gradient1,gradient2,gradient3;
    reg [3:0] gradient_enabled;
    reg gradient_valid,gradient_last,gradient_user;
    reg [10:0] gradient_threshold;
    function [23:0] edge_rgb;
        input [21:0] g;
        input enable;
        input [10:0] limit;
        reg signed [10:0] gx,gy;
        reg [10:0] ax,ay,magnitude;
        begin
            gx=g[10:0];gy=g[21:11];
            ax=gx[10]?-gx:gx;ay=gy[10]?-gy:gy;
            magnitude=(ax>=ay)?ax+(ay>>1):ay+(ax>>1);
            edge_rgb=(enable && magnitude>=limit)?24'hffffff:24'h000000;
        end
    endfunction
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            gradient0<=0;gradient1<=0;gradient2<=0;gradient3<=0;
            gradient_enabled<=0;gradient_valid<=0;gradient_last<=0;gradient_user<=0;
            gradient_threshold<=EDGE_TH;
            previous_top<=0;previous_middle<=0;previous_bottom<=0;
        end else begin
            gradient0<=g0;gradient1<=g1;gradient2<=g2;gradient3<=g3;
            gradient_enabled<={left_ok,left_ok,row_ok,row_ok};
            gradient_valid<=window_valid;gradient_last<=window_last;gradient_user<=window_user;
            gradient_threshold<=window_threshold;
            if(window_user) begin previous_top<=0;previous_middle<=0;previous_bottom<=0;end
            if(window_valid) begin
                previous_top<=window_last?16'd0:top[15:0];
                previous_middle<=window_last?16'd0:middle[15:0];
                previous_bottom<=window_last?16'd0:bottom[15:0];
            end
        end
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin O_tdata<=0;O_tvalid<=0;O_tlast<=0;O_tuser<=0;end
        else begin
            O_tvalid<=gradient_valid;O_tlast<=gradient_last;O_tuser<=gradient_user;
            O_tdata<=gradient_valid ? {
                edge_rgb(gradient0,gradient_enabled[3],gradient_threshold),
                edge_rgb(gradient1,gradient_enabled[2],gradient_threshold),
                edge_rgb(gradient2,gradient_enabled[1],gradient_threshold),
                edge_rgb(gradient3,gradient_enabled[0],gradient_threshold)} : 96'd0;
        end
    end
endmodule
