// Authored target visualization BEFORE frame-status/DDR, so the frame, box,
// coordinates and mode stay together through DDR repetitions/drops.
// Detector sees original RGB before any Logo/text; no asynchronous bus CDC.
// Display the preceding completed capture frame's box, fixed at SOF.
// Six clocks align pixels with detector+tracker, then two render overlay.
module target_overlay_96 #(
    parameter integer IMG_WIDTH=1280, IMG_HEIGHT=720
)(
    input wire clk,rst_n,
    input wire I_tuser,I_tvalid,I_tlast,
    input wire [95:0] I_tdata,
    input wire [2:0] I_mode,
    input wire [7:0] I_threshold,
    input wire [1:0] I_color,
    output reg O_tuser,O_tvalid,O_tlast,
    output reg [95:0] O_tdata,
    output reg [2:0] O_mode,
    output reg [7:0] O_threshold
);
    wire found,frame_done;
    wire [10:0] xmin,xmax,ymin,ymax;
    red_bbox_96 #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT)) detect(
        .clk(clk),.rst_n(rst_n),.user(I_tuser),.valid(I_tvalid),.enable(I_mode==5 || I_mode==6),
        .data(I_tdata),.margin(I_threshold),.target_color(I_color),.found(found),.frame_done(frame_done),
        .xmin(xmin),.xmax(xmax),.ymin(ymin),.ymax(ymax),.pair_count());
    reg [95:0] rgb1,rgb2,rgb3,rgb4,rgb5,rgb6;
    reg [5:0] users,valids,lasts;
    reg [2:0] mode1,mode2,mode3,mode4,mode5,mode6;
    reg [7:0] th1,th2,th3,th4,th5,th6;
    reg [1:0] color1,color2,color3,color4,color5,color6,display_color;
    // mode5 matches the completed detector frame at its sample edge.
    wire [1:0] tracker_state;
    wire tracker_visible;
    wire [10:0] track_x0,track_x1,track_y0,track_y1;
    wire [351:0] trail_points;
    wire [4:0] trail_count;
    box_tracker tracker(.clk(clk),.rst_n(rst_n),.clear(mode5!=6 || color5!=color6),
        .sample(frame_done),.detected(found),.xmin(xmin),.xmax(xmax),.ymin(ymin),.ymax(ymax),
        .state(tracker_state),.visible(tracker_visible),
        .txmin(track_x0),.txmax(track_x1),.tymin(track_y0),.tymax(track_y1),
        .trail_points(trail_points),.trail_count(trail_count));
    // Suppress previous-color results for the first frame of a new color.
    wire color_matches=color6==display_color;
    wire selected_found=color_matches && (mode6==6?tracker_visible:found);
    wire [1:0] selected_state=!color_matches?2'd0:mode6==6?tracker_state:(found?2'd2:2'd0);
    wire [10:0] selected_x0=mode6==6?track_x0:xmin,selected_x1=mode6==6?track_x1:xmax;
    wire [10:0] selected_y0=mode6==6?track_y0:ymin,selected_y1=mode6==6?track_y1:ymax;
    reg [1:0] display_state;
    reg display_found;
    reg [10:0] dx0,dx1,dy0,dy1;
    // History and box use the same capture-frame snapshot before DDR.
    reg [351:0] display_trail;
    reg [4:0] display_trail_count;
    wire [351:0] render_trail=users[5]?trail_points:display_trail;
    wire [4:0] render_trail_count=users[5]?trail_count:display_trail_count;
    wire visible=users[5]?selected_found:display_found;
    wire [10:0] bx0=users[5]?selected_x0:dx0,bx1=users[5]?selected_x1:dx1;
    wire [10:0] by0=users[5]?selected_y0:dy0,by1=users[5]?selected_y1:dy1;
    wire [11:0] sumx={1'b0,bx0}+{1'b0,bx1},sumy={1'b0,by0}+{1'b0,by1};
    wire [10:0] center_x=sumx[11:1],center_y=sumy[11:1];
    reg [10:0] x,y;
    wire [10:0] px=users[5]?11'd0:x,py=users[5]?11'd0:y;
    wire enabled=mode6==5 || mode6==6;
    wire [1:0] render_state=users[5]?selected_state:display_state;
    wire panel=enabled && px>=184 && px<632 && py>=88 && py<(mode6==6?168:144);
    wire row0=py>=96 && py<110,row1=py>=120 && py<134;
    wire row2=mode6==6 && py>=144 && py<158;
    wire [10:0] tx=px-11'd192;
    wire [4:0] pos=tx[8:4];
    wire [2:0] row=row0?((py-11'd96)>>1):row1?((py-11'd120)>>1):((py-11'd144)>>1);
    wire [7:0] code;
    wire [4:0] bits;
    target_char label(.clk(clk),.rst_n(rst_n),.update(users[5]),
        .pos(pos),.line1(row1),.line2(row2),.color(color6),.found(visible),.tracking(mode6==6),.state(render_state),.cx(center_x),.cy(center_y),.code(code));
    osd_font5x7 font(.code(code),.row(row),.bits(bits));
    reg [3:0] text_d,box_d,cross_d,trail_d;
    reg panel_d,v_d,u_d,l_d,hold_d;
    reg [95:0] base_d;
    reg [2:0] mode_d;
    reg [7:0] th_d;
    integer k,j;
    reg [11:0] xx;
    reg trail_hit;
    reg [10:0] history_x,history_y;
    reg inside_box;
    reg [23:0] pixel;
    wire [11:0] border_width=mode6==6?12'd4:12'd2;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            rgb1<=0;rgb2<=0;rgb3<=0;rgb4<=0;rgb5<=0;rgb6<=0;users<=0;valids<=0;lasts<=0;
            mode1<=0;mode2<=0;mode3<=0;mode4<=0;mode5<=0;mode6<=0;th1<=0;th2<=0;th3<=0;th4<=0;th5<=0;th6<=0;
            color1<=0;color2<=0;color3<=0;color4<=0;color5<=0;color6<=0;display_color<=0;
            display_state<=0;display_found<=0;dx0<=0;dx1<=0;dy0<=0;dy1<=0;x<=0;y<=0;
            display_trail<=0;display_trail_count<=0;
            text_d<=0;box_d<=0;cross_d<=0;trail_d<=0;panel_d<=0;hold_d<=0;v_d<=0;u_d<=0;l_d<=0;base_d<=0;
            mode_d<=0;th_d<=0;O_tuser<=0;O_tvalid<=0;O_tlast<=0;O_tdata<=0;O_mode<=0;O_threshold<=0;
        end else begin
            rgb1<=I_tdata;rgb2<=rgb1;rgb3<=rgb2;rgb4<=rgb3;rgb5<=rgb4;rgb6<=rgb5;
            users<={users[4:0],I_tuser};valids<={valids[4:0],I_tvalid};lasts<={lasts[4:0],I_tlast};
            mode1<=I_mode;mode2<=mode1;mode3<=mode2;mode4<=mode3;mode5<=mode4;mode6<=mode5;
            th1<=I_threshold;th2<=th1;th3<=th2;th4<=th3;th5<=th4;th6<=th5;
            color1<=I_color;color2<=color1;color3<=color2;color4<=color3;color5<=color4;color6<=color5;
            if(users[5])begin
                x<=0;y<=0;display_state<=selected_state;display_found<=selected_found;dx0<=selected_x0;dx1<=selected_x1;dy0<=selected_y0;dy1<=selected_y1;
                display_trail<=trail_points;display_trail_count<=trail_count;
                display_color<=color6;
            end
            if(valids[5])begin
                x<=px==IMG_WIDTH-4?11'd0:px+11'd4;
                y<=px==IMG_WIDTH-4?(py==IMG_HEIGHT-1?11'd0:py+1'b1):py;
            end
            base_d<=rgb6;panel_d<=panel;hold_d<=mode6==6 && render_state==3;v_d<=valids[5];u_d<=users[5];l_d<=lasts[5];
            mode_d<=mode6;th_d<=th6;
            for(k=0;k<4;k=k+1)begin
                xx={1'b0,px}+k;
                text_d[3-k]<=enabled && px>=192 && px<624 && (row0||row1||row2)
                    && (tx[3:0]+k)<10 && bits[4-((tx[3:0]+k)>>1)];
                box_d[3-k]<=enabled && visible && xx>=bx0 && xx<=bx1 && py>=by0 && py<=by1
                    && (xx<bx0+border_width || xx+border_width>bx1 || {1'b0,py}<by0+border_width || {1'b0,py}+border_width>by1);
                cross_d[3-k]<=enabled && visible && ((py==center_y && xx+12'd8>=center_x && xx<=center_x+12'd8)
                    || (xx==center_x && {1'b0,py}+12'd8>=center_y && {1'b0,py}<=center_y+12'd8));
                trail_hit=0;
                for(j=0;j<16;j=j+1)begin
                    history_x=render_trail[j*22+11 +:11];history_y=render_trail[j*22 +:11];
                    if(j<render_trail_count && xx+12'd4>=history_x && xx<={1'b0,history_x}+12'd4
                        && {1'b0,py}+12'd4>=history_y && {1'b0,py}<={1'b0,history_y}+12'd4)trail_hit=1;
                end
                trail_d[3-k]<=mode6==6 && visible && trail_hit;
                inside_box=visible && xx>=bx0 && xx<=bx1 && py>=by0 && py<=by1;
                pixel=rgb6[95-k*24 -:24];
                // Dim TRACK's background, preserving the current box contents.
                if(mode6==6 && !inside_box)base_d[95-k*24 -:24]<={1'b0,pixel[23:17],1'b0,pixel[15:9],1'b0,pixel[7:1]};
            end
            O_tuser<=u_d;O_tvalid<=v_d;O_tlast<=l_d;O_mode<=mode_d;O_threshold<=th_d;
            for(k=0;k<4;k=k+1)
                O_tdata[95-k*24 -:24]<=!v_d?24'd0:text_d[3-k]?24'hffffff:panel_d?24'h101820:
                    cross_d[3-k]?(hold_d?24'hffb000:24'hffff00):box_d[3-k]?(hold_d?24'hffb000:mode_d==6?24'h00e6ff:24'h00ff40):
                    trail_d[3-k]?24'h00e6ff:base_d[95-k*24 -:24];
        end
    end
endmodule

module target_char(
    input wire clk,rst_n,update,
    input wire [4:0] pos,
    input wire line1,line2,found,tracking,
    input wire [1:0] state,
    input wire [1:0] color,
    input wire [10:0] cx,cy,
    output reg [7:0] code
);
    // Serial double-dabble: 11 clocks during the top rows, well before text
    // starts at y=96. Avoid an 11-step combinational conversion at pixel rate.
    reg [10:0] shift_x,shift_y;
    reg [3:0] remaining;
    reg [15:0] xd,yd,adjust_x,adjust_y;
    integer j;
    always @(*)begin
        adjust_x=xd;adjust_y=yd;
        for(j=0;j<4;j=j+1)begin
            if(xd[j*4 +:4]>=5)adjust_x[j*4 +:4]=xd[j*4 +:4]+4'd3;
            if(yd[j*4 +:4]>=5)adjust_y[j*4 +:4]=yd[j*4 +:4]+4'd3;
        end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin shift_x<=0;shift_y<=0;remaining<=0;xd<=0;yd<=0;end
        else if(update)begin shift_x<=cx;shift_y<=cy;remaining<=11;xd<=0;yd<=0;end
        else if(remaining!=0)begin
            xd<={adjust_x[14:0],shift_x[10]};yd<={adjust_y[14:0],shift_y[10]};
            shift_x<={shift_x[9:0],1'b0};shift_y<={shift_y[9:0],1'b0};remaining<=remaining-1'b1;
        end
    end
    reg [215:0] text;
    always @(*)begin
        if(!line1) text=found?"RED FOUND                  ":"RED LOST                   ";
        else begin
            text="X ---- Y ----              ";
            if(found)begin
                text[199:192]=8'd48+xd[15:12];text[191:184]=8'd48+xd[11:8];
                text[183:176]=8'd48+xd[7:4];text[175:168]=8'd48+xd[3:0];
                text[143:136]=8'd48+yd[15:12];text[135:128]=8'd48+yd[11:8];
                text[127:120]=8'd48+yd[7:4];text[119:112]=8'd48+yd[3:0];
            end
        end
        if(!line1 && tracking)begin
            case(state)
                1:text="RED WAIT                   ";
                2:text="RED TRACK                  ";
                3:text="RED HOLD                   ";
                default:text="RED LOST                   ";
            endcase
        end
        if(line2)text="TRAIL 16 HOLD 30 FRAMES    ";
        else if(!line1)case(color)
            1:text={"GREEN",text[191:16]};
            2:text={"BLUE",text[191:8]};
            default:begin end
        endcase
        code=pos<27?text[215-pos*8 -:8]:8'd32;
    end
endmodule
