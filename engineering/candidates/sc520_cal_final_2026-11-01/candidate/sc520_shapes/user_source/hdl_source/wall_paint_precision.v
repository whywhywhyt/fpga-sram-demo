`timescale 1ns/1ps
// A dedicated marker tap. One pixel per four-pixel beat and every fourth
// line: 160x80 samples in the central 640x320 ROI, without a frame buffer.
// Input SOF may precede valid by many cycles (production AWB protocol).
module wall_red_marker(
    input wire cam_clk,led_clk,rst_n,
    input wire valid,user,last,input wire [95:0] rgb,
    output reg marker_valid,output reg [7:0] marker_u,
    output reg [6:0] marker_v,output reg [4:0] marker_x,
    output reg [3:0] marker_y
);
    reg [8:0] beat;reg [9:0] row;
    reg frame_ok,started;
    wire [8:0] bx=user?0:beat;
    wire [9:0] ry=user?0:row;
    reg sample_valid;reg [7:0] sample_u;reg [6:0] sample_v;
    reg [7:0] sample_r,sample_g,sample_b;
    wire red=sample_r>=64 && {1'b0,sample_r}>={1'b0,sample_g}+9'd28 &&
             {1'b0,sample_r}>={1'b0,sample_b}+9'd28 &&
             {sample_g,1'b0}<=({1'b0,sample_r}+{3'b0,sample_r[7:2]}) &&
             {sample_b,1'b0}<=({1'b0,sample_r}+{3'b0,sample_r[7:2]});
    reg [13:0] count;
    reg [20:0] sum_u,sum_v;
    reg [7:0] min_u,max_u,lock_u;reg [6:0] min_v,max_v,lock_v;
    reg locked;
    wire in_lock=!locked ||
        (({1'b0,sample_u}+9'd40>={1'b0,lock_u}) &&
         ({1'b0,sample_u}<={1'b0,lock_u}+9'd40) &&
         ({1'b0,sample_v}+8'd32>={1'b0,lock_v}) &&
         ({1'b0,sample_v}<={1'b0,lock_v}+8'd32));
    reg eof;
    reg [1:0] div_state;
    reg [4:0] div_bit;
    reg [20:0] dividend,quotient;
    reg [14:0] remainder;
    reg [13:0] divisor;
    reg [7:0] result_u;reg [6:0] result_v;
    wire [14:0] trial={remainder[13:0],dividend[20]};
    wire fits=trial>={1'b0,divisor};
    wire [20:0] next_q={quotient[19:0],fits};
    // Bundled-data mailbox: payload remains stable until LED ack returns.
    reg request;reg [15:0] payload;
    reg acknowledge;
    (* ASYNC_REG="TRUE" *) reg ack_s1,ack_s2,req_s1,req_s2;
    reg [22:0] stale;
    wire mailbox_free=request==ack_s2;
    wire plausible=count>=12 && count<=1536 && max_u-min_u<=64 &&
                   max_v-min_v<=48 && max_u>min_u && max_v>min_v;
    always @(posedge cam_clk or negedge rst_n)begin
        if(!rst_n)begin
            beat<=0;row<=0;frame_ok<=0;started<=0;sample_valid<=0;
            sample_u<=0;sample_v<=0;sample_r<=0;sample_g<=0;sample_b<=0;
            count<=0;sum_u<=0;sum_v<=0;min_u<=159;max_u<=0;min_v<=79;max_v<=0;
            locked<=0;lock_u<=0;lock_v<=0;eof<=0;
            div_state<=0;div_bit<=0;dividend<=0;quotient<=0;remainder<=0;divisor<=1;
            result_u<=0;result_v<=0;request<=0;payload<=0;ack_s1<=0;ack_s2<=0;
        end else begin
            ack_s1<=acknowledge;ack_s2<=ack_s1;sample_valid<=0;eof<=0;
            if(user)begin
                beat<=0;row<=0;frame_ok<=1;started<=1;
                count<=0;sum_u<=0;sum_v<=0;min_u<=159;max_u<=0;min_v<=79;max_v<=0;
                // An interrupted frame cannot leave a stale pen locked on.
                if(started)begin
                    locked<=0;
                    if(mailbox_free)begin payload<=0;request<=~request;end
                end
            end
            if(valid && (started || user))begin
                if(last!=(bx==319) || ry>=720)begin
                    frame_ok<=0;locked<=0;
                    if(frame_ok && mailbox_free)begin payload<=0;request<=~request;end
                end
                beat<=last?0:bx+1'b1;row<=last?ry+1'b1:ry;
                if((frame_ok || user) && last==(bx==319) &&
                   bx>=80 && bx<240 && ry>=200 && ry<520 && ry[1:0]==0)begin
                    sample_valid<=1;sample_u<=bx-80;sample_v<=(ry-200)>>2;
                    sample_r<=rgb[95:88];sample_g<=rgb[87:80];sample_b<=rgb[79:72];
                end
                if(last && bx==319 && ry==719)begin eof<=1;started<=0;end
            end
            if(sample_valid && red && in_lock && !user)begin
                count<=count+1'b1;sum_u<=sum_u+sample_u;sum_v<=sum_v+sample_v;
                if(sample_u<min_u)min_u<=sample_u;if(sample_u>max_u)max_u<=sample_u;
                if(sample_v<min_v)min_v<=sample_v;if(sample_v>max_v)max_v<=sample_v;
            end
            case(div_state)
                0:if(eof)begin
                    if(frame_ok && plausible)begin
                        dividend<=sum_u;divisor<=count;quotient<=0;remainder<=0;
                        div_bit<=20;div_state<=1;
                    end else begin
                        locked<=0;
                        if(mailbox_free)begin payload<=0;request<=~request;end
                    end
                end
                1,2:begin
                    dividend<={dividend[19:0],1'b0};quotient<=next_q;
                    remainder<=fits?trial-{1'b0,divisor}:trial;
                    if(div_bit==0)begin
                        if(div_state==1)begin
                            result_u<=next_q[7:0];dividend<=sum_v;
                            quotient<=0;remainder<=0;div_bit<=20;div_state<=2;
                        end else begin result_v<=next_q[6:0];div_state<=3;end
                    end else div_bit<=div_bit-1'b1;
                end
                3:begin
                    locked<=1;lock_u<=result_u;lock_v<=result_v;
                    if(mailbox_free)begin payload<={1'b1,result_u,result_v};request<=~request;end
                    div_state<=0;
                end
            endcase
        end
    end
    wire [4:0] cell_x=payload[14:7]/8'd5;
    wire [3:0] cell_y=payload[6:0]/7'd5;
    wire [7:0] old_left=marker_x*8'd5;
    wire [6:0] old_top=marker_y*7'd5;
    always @(posedge led_clk or negedge rst_n)begin
        if(!rst_n)begin
            req_s1<=0;req_s2<=0;acknowledge<=0;marker_valid<=0;
            marker_u<=0;marker_v<=0;marker_x<=0;marker_y<=0;stale<=0;
        end else begin
            req_s1<=request;req_s2<=req_s1;
            if(req_s2!=acknowledge)begin
                acknowledge<=req_s2;stale<=0;marker_valid<=payload[15];
                marker_u<=payload[14:7];marker_v<=payload[6:0];
                // 4-pixel hysteresis around a 20-pixel cell boundary.
                if(!marker_valid || payload[14:7]+9'd1<old_left ||
                    {1'b0,payload[14:7]}>={1'b0,old_left}+9'd6)marker_x<=cell_x;
                if(!marker_valid || payload[6:0]+8'd1<old_top ||
                    {1'b0,payload[6:0]}>={1'b0,old_top}+8'd6)marker_y<=cell_y;
            end else if(stale==23'd4999999)marker_valid<=0;
            else stale<=stale+1'b1;
        end
    end
endmodule

// Double-buffered palette-index artwork preview and frame-latched marker metadata.
// LED writer owns one bank until publication; HDMI switches only at SOF,
// then acknowledges, so the displayed bank is never being modified.
module wall_paint_overlay(
    input wire led_clk,hdmi_clk,rst_n,
    input wire write_valid,input wire [8:0] write_addr,input wire [23:0] write_rgb,
    input wire frame_done,input wire [2:0] wall_status,
    input wire marker_valid,pen_down,input wire [7:0] marker_u,input wire [6:0] marker_v,
    input wire de,user,last,input wire [23:0] pixel,
    output wire [23:0] out_pixel,input wire [2:0] brush_color
);
    reg [2:0] canvas[0:1023];
    reg request,acknowledge,write_bank,read_bank,recording,published_bank;
    reg [23:0] payload;
    (* ASYNC_REG="TRUE" *) reg ack_s1,ack_s2,req_s1,req_s2;
    wire free=request==ack_s2;
    always @(posedge led_clk or negedge rst_n)begin
        if(!rst_n)begin
            request<=0;write_bank<=1;published_bank<=0;recording<=0;ack_s1<=0;ack_s2<=0;payload<=0;
        end else begin
            ack_s1<=acknowledge;ack_s2<=ack_s1;
            if(write_valid && write_addr==0)recording<=free;
            if(frame_done && free)begin
                payload<={brush_color,recording?write_bank:published_bank,wall_status,marker_valid,pen_down,marker_u,marker_v};
                request<=~request;recording<=0;
                if(recording)begin published_bank<=write_bank;write_bank<=~write_bank;end
            end
        end
    end
    always @(posedge led_clk)begin
        if(write_valid && ((write_addr==0 && free) || (write_addr!=0 && recording)))
            canvas[{write_bank,write_addr}]<=encode_color(write_rgb);
    end
    function [2:0] encode_color;
        input [23:0] rgb;
        begin case(rgb)
            24'h042018:encode_color=1;
            24'h040820:encode_color=2;
            24'h180420:encode_color=3;
            24'h200404:encode_color=4;
            24'h201004:encode_color=5;
            24'h042004:encode_color=6;
            default:encode_color=0;
        endcase end
    endfunction
    function [23:0] preview_palette;
        input [2:0] code;
        begin case(code)
            1:preview_palette=24'h20d8e0;
            2:preview_palette=24'h4060ff;
            3:preview_palette=24'hb030ff;
            4:preview_palette=24'hff3030;
            5:preview_palette=24'hff9020;
            6:preview_palette=24'h30e050;
            default:preview_palette=24'h030608;
        endcase end
    endfunction
    reg [10:0] x;reg [9:0] y;
    wire [10:0] px=user?0:x;wire [9:0] py=user?0:y;
    reg [2:0] shown_brush,shown_status;reg shown_valid,shown_down,have_frame;
    reg [7:0] shown_u;reg [6:0] shown_v;
    wire enabled=have_frame && (shown_status==3 || shown_status==4);
    // Preview = 256x128 at (992,512), each LED represented by 8x8 pixels.
    // Read the next HDMI pixel so the synchronous RAM output aligns with px.
    wire [10:0] next_x=user?(de?11'd1:11'd0):(de?(last?11'd0:x+1'b1):x);
    wire [9:0] next_y=user?10'd0:(de&&last?y+1'b1:y);
    wire [10:0] preview_x=next_x-11'd992;
    wire [8:0] preview_addr={next_y[6:3],preview_x[7:3]};
    reg [2:0] preview_code;
    always @(posedge hdmi_clk)preview_code<=canvas[{read_bank,preview_addr}];
    always @(posedge hdmi_clk or negedge rst_n)begin
        if(!rst_n)begin
            req_s1<=0;req_s2<=0;acknowledge<=0;read_bank<=0;x<=0;y<=0;
            shown_brush<=0;shown_status<=0;shown_valid<=0;shown_down<=0;shown_u<=0;shown_v<=0;have_frame<=0;
        end else begin
            req_s1<=request;req_s2<=req_s1;
            if(user)begin
                x<=de?1:0;y<=0;
                if(req_s2!=acknowledge)begin
                    shown_brush<=payload[23:21];read_bank<=payload[20];shown_status<=payload[19:17];
                    shown_valid<=payload[16];shown_down<=payload[15];
                    shown_u<=payload[14:7];shown_v<=payload[6:0];
                    acknowledge<=req_s2;have_frame<=1;
                end
            end else if(de)begin if(last)begin x<=0;y<=y+1'b1;end else x<=x+1'b1;end
        end
    end
    wire roi_edge=((px>=320 && px<960) && (py==200 || py==519)) ||
                  ((py>=200 && py<520) && (px==320 || px==959));
    wire [10:0] cursor_x=11'd320+{1'b0,shown_u,2'b00};
    wire [9:0] cursor_y=10'd200+{1'b0,shown_v,2'b00};
    wire [10:0] dx=px>cursor_x?px-cursor_x:cursor_x-px;
    wire [9:0] dy=py>cursor_y?py-cursor_y:cursor_y-py;
    wire cursor=shown_valid && ((dx<=10 && dy<=1)||(dx<=1 && dy<=10));
    wire preview=px>=992 && px<1248 && py>=512 && py<640;
    wire border=px>=991 && px<=1248 && py>=511 && py<=640 &&
                (px==991 || px==1248 || py==511 || py==640);
    wire [23:0] cursor_color=shown_down?24'h20ffff:24'hff8040;
    // At (992,488) a 16x16 square is cyan for DOWN, orange for UP,
    // red when the marker is lost. No extra font ROM or language dependency.
    wire indicator=px>=992 && px<1008 && py>=488 && py<504;
    wire swatches=px>=1024 && px<1216 && py>=488 && py<504;
    wire [7:0] swatch_dx=px-1024;
    wire [2:0] swatch_slot=swatch_dx[7:5];
    wire [4:0] swatch_x=swatch_dx[4:0];
    wire swatch_fill=swatch_x>=2 && swatch_x<26 && py>=490 && py<502;
    wire swatch_selected=swatch_slot==shown_brush && swatch_x<28 &&
        (swatch_x==0 || swatch_x==27 || py==488 || py==503);
    wire [23:0] swatch_rgb=swatch_selected?24'hffffff:
        (swatch_fill?preview_palette(swatch_slot+3'd1):24'h081020);
    assign out_pixel=(!enabled || !de)?pixel:
        cursor?cursor_color:roi_edge?24'h608090:border?24'h80a0b0:
        indicator?(shown_valid?cursor_color:24'hff2020):
        swatches?swatch_rgb:preview?preview_palette(preview_code):pixel;
endmodule
