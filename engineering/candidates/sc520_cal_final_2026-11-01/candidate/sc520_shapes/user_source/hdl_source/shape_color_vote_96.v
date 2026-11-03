// Four MSB-first RGB888 pixels/beat. 16-pixel majority per 4x4 tile.
// Every tile, including background, is written. RAM has no reset path;
// row zero of each tile overwrites its previous partial sum.
module shape_color_vote_96 #(
    parameter integer IMG_WIDTH=1280, IMG_HEIGHT=720
)(
    input wire clk,rst_n,user,valid,enable,
    input wire [95:0] data,
    input wire [7:0] margin,
    output reg tile_valid,frame_complete,
    output reg [15:0] tile_addr,tile_frame,
    output reg [2:0] tile_color,
    output reg [7:0] tile_margin,
    output reg [15:0] capture_frame
);
    localparam integer TW=IMG_WIDTH/4;
    function [2:0] color_of;
        input [23:0] p;
        input [7:0] m;
        reg [7:0] r,g,b,main,other,delta;
        reg [1:0] winner;
        reg yellow;
        begin
            r=p[23:16];g=p[15:8];b=p[7:0];
            yellow=(r>=64 && g>=64 && {1'b0,b}<(({1'b0,r}+{1'b0,g})>>2) &&
                    ((r>g)?(r-g):(g-r))<=(m+8'd24));
            if(yellow) color_of=3'd4;
            else begin
                if(r>=g && r>=b)begin main=r;other=g>b?g:b;winner=1;end
                else if(g>=b)begin main=g;other=r>b?r:b;winner=2;end
                else begin main=b;other=r>g?r:g;winner=3;end
                if(winner==3)begin
                    // Reject weak blue casts on neutral backgrounds. Keep the lower
                    // absolute margin for darker blue, but require 25% dominance.
                    delta=(m>>1)>(main>>2)?(m>>1):(main>>2);
                end else delta=m>(main>>2)?m:(main>>2);
                color_of=(main>=64 && {1'b0,main}>={1'b0,other}+{1'b0,delta})?{1'b0,winner}:3'd0;
            end
        end
    endfunction
    reg [10:0] x,y;
    reg active,frame_enable;
    reg [7:0] frame_margin;
    reg [15:0] next_addr;
    wire [10:0] px=user?11'd0:x,py=user?11'd0:y;
    wire en=user?enable:frame_enable;
    wire [7:0] th=user?margin:frame_margin;
    wire [2:0] c0=color_of(data[95:72],th),c1=color_of(data[71:48],th);
    wire [2:0] c2=color_of(data[47:24],th),c3=color_of(data[23:0],th);
    wire [2:0] vr={2'd0,c0==1}+{2'd0,c1==1}+{2'd0,c2==1}+{2'd0,c3==1};
    wire [2:0] vg={2'd0,c0==2}+{2'd0,c1==2}+{2'd0,c2==2}+{2'd0,c3==2};
    wire [2:0] vb={2'd0,c0==3}+{2'd0,c1==3}+{2'd0,c2==3}+{2'd0,c3==3};
    wire [2:0] vy={2'd0,c0==4}+{2'd0,c1==4}+{2'd0,c2==4}+{2'd0,c3==4};
    reg [19:0] row_sum [0:TW-1];
    reg [19:0] sum_q;
    reg p_valid,p_final;
    reg [1:0] p_row;
    reg [8:0] p_col;
    reg [11:0] p_votes;
    reg [15:0] p_addr,p_frame;
    reg [7:0] p_margin;
    wire [4:0] sr=(p_row==0?5'd0:sum_q[19:15])+{2'd0,p_votes[11:9]};
    wire [4:0] sg=(p_row==0?5'd0:sum_q[14:10])+{2'd0,p_votes[8:6]};
    wire [4:0] sb=(p_row==0?5'd0:sum_q[9:5])+{2'd0,p_votes[5:3]};
    wire [4:0] sy=(p_row==0?5'd0:sum_q[4:0])+{2'd0,p_votes[2:0]};
    // Dedicated synchronous RAM process: never reset the memory array.
    always @(posedge clk)begin
        sum_q<=row_sum[px[10:2]];
        if(p_valid)row_sum[p_col]<={sr,sg,sb,sy};
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            x<=0;y<=0;active<=0;frame_enable<=0;frame_margin<=32;next_addr<=0;
            p_valid<=0;p_final<=0;p_row<=0;p_col<=0;p_votes<=0;p_addr<=0;p_frame<=0;p_margin<=0;
            tile_valid<=0;frame_complete<=0;tile_addr<=0;tile_frame<=0;tile_color<=0;tile_margin<=0;capture_frame<=0;
        end else begin
            tile_valid<=p_valid && p_row==3;frame_complete<=p_valid && p_row==3 && p_final;
            tile_addr<=p_addr;tile_margin<=p_margin;tile_frame<=p_frame;
            tile_color<=sr>=9 && sr>sg && sr>sb && sr>sy?3'd1:
                sg>=9 && sg>sr && sg>sb && sg>sy?3'd2:
                sb>=9 && sb>sr && sb>sg && sb>sy?3'd3:
                sy>=9 && sy>sr && sy>sg && sy>sb?3'd4:3'd0;
            p_valid<=valid && (active || user) && en;
            p_row<=py[1:0];p_col<=px[10:2];p_votes<={vr,vg,vb,vy};
            p_addr<=user?16'd0:next_addr;p_margin<=th;p_frame<=user?capture_frame+16'd1:capture_frame;
            p_final<=px==IMG_WIDTH-4 && py==IMG_HEIGHT-1;
            if(user)begin
                x<=0;y<=0;active<=1;frame_enable<=enable;frame_margin<=margin;next_addr<=0;
                capture_frame<=capture_frame+1'b1;
            end
            if(valid && (active || user))begin
                x<=px==IMG_WIDTH-4?11'd0:px+11'd4;
                y<=px==IMG_WIDTH-4?py+11'd1:py;
                if(py[1:0]==3)next_addr<=next_addr+1'b1;
                if(px==IMG_WIDTH-4 && py==IMG_HEIGHT-1)active<=0;
            end
        end
    end
endmodule
