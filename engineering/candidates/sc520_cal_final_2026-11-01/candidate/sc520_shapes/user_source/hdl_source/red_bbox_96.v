// Bounded streaming run-region detector, four MSB-first RGB888 pixels/beat.
// Short horizontal runs are discarded before region association. Up to eight
// live regions use adjacent-row interval envelopes; intersecting regions merge.
// This is a bounded approximation, not an unlimited pixel-label CCL engine.
// Published bounds retain full pixel precision; no tile quantization is used.
module red_bbox_96 #(
    parameter integer IMG_WIDTH=1280, IMG_HEIGHT=720,
    parameter integer MIN_PAIRS=128, MIN_WIDTH=8, MIN_HEIGHT=8,
    parameter integer MIN_RUN=8, REGIONS=8
)(
    input wire clk,rst_n,user,valid,enable,
    input wire [95:0] data,
    input wire [7:0] margin,
    input wire [1:0] target_color,
    output reg found,frame_done,
    output reg [10:0] xmin,xmax,ymin,ymax,
    // Retained interface name: now the selected region's accepted PIXEL count.
    output reg [19:0] pair_count
);
    function is_color;
        input [23:0] p;
        input [7:0] m;
        input [1:0] color;
        reg [7:0] main_channel,other1,other2;
        begin
            case(color)
                1:begin main_channel=p[15:8];other1=p[23:16];other2=p[7:0];end
                2:begin main_channel=p[7:0];other1=p[23:16];other2=p[15:8];end
                default:begin main_channel=p[23:16];other1=p[15:8];other2=p[7:0];end
            endcase
            is_color=main_channel>=80 && {1'b0,main_channel}>={1'b0,other1}+{1'b0,m}
                && {1'b0,main_channel}>={1'b0,other2}+{1'b0,m};
        end
    endfunction
    reg [10:0] x,y;
    wire [10:0] cx=user?11'd0:x,cy=user?11'd0:y;
    reg v1,u1,en1,eof1;
    reg [10:0] x1,y1;
    reg [3:0] mask1;
    reg [1:0] color1,previous_color;
    reg [10:0] run_start,run_length;
    reg [10:0] next_start,next_length,event_lo,event_hi,event_length;
    reg event_valid;
    integer lane;
    // MIN_RUN>=4 guarantees at most one qualifying run finishes per beat.
    always @(*) begin
        next_start=u1?11'd0:run_start;
        next_length=(u1 || x1==0)?11'd0:run_length;
        event_valid=0;event_lo=0;event_hi=0;event_length=0;
        for(lane=0;lane<4;lane=lane+1)begin
            if(v1 && en1 && mask1[3-lane])begin
                if(next_length==0)next_start=x1+lane;
                next_length=next_length+1'b1;
            end
            if(v1 && ((!en1 || !mask1[3-lane]) || x1+lane==IMG_WIDTH-1))begin
                if(next_length>=MIN_RUN)begin
                    event_valid=1;event_lo=next_start;
                    event_hi=next_start+next_length-1'b1;event_length=next_length;
                end
                next_length=0;
            end
        end
    end
    reg u2,en2,eof2,hit2;
    reg [10:0] lo2,hi2,y2,len2;
    reg [REGIONS-1:0] used,prev_valid;
    reg [19:0] area[0:REGIONS-1];
    reg [10:0] lx[0:REGIONS-1],hx[0:REGIONS-1],ly[0:REGIONS-1],hy[0:REGIONS-1];
    reg [10:0] row_lo[0:REGIONS-1],row_hi[0:REGIONS-1];
    reg [10:0] prev_lo[0:REGIONS-1],prev_hi[0:REGIONS-1];
    reg [REGIONS-1:0] region_match;
    reg [19:0] weights[0:7];
    reg [19:0] sum01,sum23,sum45,sum67;
    reg [10:0] len_m;
    wire [19:0] merged_area=(sum01+sum23)+(sum45+sum67)+len_m;
    function [10:0] min2;
        input [10:0] a,b;
        begin min2=a<b?a:b;end
    endfunction
    function [10:0] max2;
        input [10:0] a,b;
        begin max2=a>b?a:b;end
    endfunction
    function [10:0] min8;
        input [87:0] a;
        begin min8=min2(min2(min2(a[10:0],a[21:11]),min2(a[32:22],a[43:33])),
            min2(min2(a[54:44],a[65:55]),min2(a[76:66],a[87:77])));end
    endfunction
    function [10:0] max8;
        input [87:0] a;
        begin max8=max2(max2(max2(a[10:0],a[21:11]),max2(a[32:22],a[43:33])),
            max2(max2(a[54:44],a[65:55]),max2(a[76:66],a[87:77])));end
    endfunction
    reg [87:0] leaf_x0,leaf_x1,leaf_y0,leaf_rl,leaf_rh,leaf_pl,leaf_ph;
    wire [10:0] mx0=min8(saved_x0),mx1=max8(saved_x1),my0=min8(saved_y0);
    wire [10:0] rl=min8(saved_rl),rh=max8(saved_rh),pl=min8(saved_pl),ph=max8(saved_ph);
    reg [87:0] saved_x0,saved_x1,saved_y0,saved_rl,saved_rh,saved_pl,saved_ph;
    reg [REGIONS-1:0] saved_match;
    reg saved_pv,u_m,en_m,eof_m,hit_m;
    reg [10:0] y_m;
    reg [3:0] saved_slot;
    reg slot_valid;
    reg pv;
    integer i,slot,free_slot;
    // Keep preceding-row intervals separately from the full-frame box.
    always @(*)begin
        region_match=0;slot=-1;free_slot=-1;
        pv=0;
        for(i=0;i<8;i=i+1)weights[i]=0;
        for(i=0;i<REGIONS;i=i+1)begin
            leaf_x0[i*11 +:11]=lo2;leaf_x1[i*11 +:11]=hi2;leaf_y0[i*11 +:11]=y2;
            leaf_rl[i*11 +:11]=lo2;leaf_rh[i*11 +:11]=hi2;
            leaf_pl[i*11 +:11]=IMG_WIDTH-1;leaf_ph[i*11 +:11]=0;
            if(!used[i] || {1'b0,hy[i]}+12'd1<{1'b0,y2})begin
                if(free_slot==-1)free_slot=i;
            end
            if(!u2 && used[i] && (
                (hy[i]+12'd1==y2 && {1'b0,lo2}<={1'b0,row_hi[i]}+12'd1 && {1'b0,hi2}+12'd1>=row_lo[i]) ||
                (hy[i]==y2 && prev_valid[i] && {1'b0,lo2}<={1'b0,prev_hi[i]}+12'd1 && {1'b0,hi2}+12'd1>=prev_lo[i])
            ))begin
                region_match[i]=1;weights[i]=area[i];
                if(slot==-1)slot=i;
                leaf_x0[i*11 +:11]=min2(lx[i],lo2);leaf_x1[i*11 +:11]=max2(hx[i],hi2);
                leaf_y0[i*11 +:11]=min2(ly[i],y2);
                if(hy[i]==y2)begin
                    leaf_rl[i*11 +:11]=min2(row_lo[i],lo2);leaf_rh[i*11 +:11]=max2(row_hi[i],hi2);
                    if(prev_valid[i])begin
                        pv=1;leaf_pl[i*11 +:11]=prev_lo[i];leaf_ph[i*11 +:11]=prev_hi[i];
                    end
                end else begin
                    pv=1;leaf_pl[i*11 +:11]=row_lo[i];leaf_ph[i*11 +:11]=row_hi[i];
                end
            end
        end
        if(slot==-1)slot=u2?0:free_slot;
    end
    reg [19:0] best_area;
    reg [10:0] best_x0,best_x1,best_y0,best_y1;
    wire qualifies=hit_m && slot_valid && merged_area>=MIN_PAIRS
        && mx1-mx0>=MIN_WIDTH-1 && y_m-my0>=MIN_HEIGHT-1;
    reg u3,en3,eof3,qualified3;
    reg [19:0] area3;
    reg [10:0] x03,x13,y03,y13;
    wire improve=qualified3 && (u3 || area3>best_area);
    wire [19:0] final_area=improve?area3:(u3?20'd0:best_area);
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            x<=0;y<=0;v1<=0;u1<=0;en1<=0;eof1<=0;x1<=0;y1<=0;mask1<=0;color1<=0;previous_color<=0;
            run_start<=0;run_length<=0;u2<=0;en2<=0;eof2<=0;hit2<=0;lo2<=0;hi2<=0;y2<=0;len2<=0;
            used<=0;prev_valid<=0;best_area<=0;best_x0<=0;best_x1<=0;best_y0<=0;best_y1<=0;
            sum01<=0;sum23<=0;sum45<=0;sum67<=0;len_m<=0;
            saved_x0<=0;saved_x1<=0;saved_y0<=0;saved_rl<=0;saved_rh<=0;saved_pl<=0;saved_ph<=0;
            saved_match<=0;saved_pv<=0;u_m<=0;en_m<=0;eof_m<=0;hit_m<=0;y_m<=0;saved_slot<=0;slot_valid<=0;
            u3<=0;en3<=0;eof3<=0;qualified3<=0;area3<=0;x03<=0;x13<=0;y03<=0;y13<=0;
            found<=0;frame_done<=0;xmin<=0;xmax<=0;ymin<=0;ymax<=0;pair_count<=0;
            for(i=0;i<REGIONS;i=i+1)begin
                area[i]<=0;lx[i]<=0;hx[i]<=0;ly[i]<=0;hy[i]<=0;
                row_lo[i]<=0;row_hi[i]<=0;prev_lo[i]<=0;prev_hi[i]<=0;
            end
        end else begin
            if(user)begin x<=0;y<=0;end
            if(valid)begin
                x<=cx==IMG_WIDTH-4?11'd0:cx+11'd4;
                y<=cx==IMG_WIDTH-4?(cy==IMG_HEIGHT-1?11'd0:cy+1'b1):cy;
            end
            v1<=valid;u1<=user;en1<=enable;color1<=target_color;
            eof1<=valid && cx==IMG_WIDTH-4 && cy==IMG_HEIGHT-1;x1<=cx;y1<=cy;
            mask1<={is_color(data[95:72],margin,target_color),is_color(data[71:48],margin,target_color),
                is_color(data[47:24],margin,target_color),is_color(data[23:0],margin,target_color)};
            if(u1 || v1)begin run_start<=next_start;run_length<=next_length;end
            u2<=u1;en2<=en1;eof2<=eof1;hit2<=event_valid;
            lo2<=event_lo;hi2<=event_hi;y2<=y1;len2<=event_length;
            sum01<=weights[0]+weights[1];sum23<=weights[2]+weights[3];
            sum45<=weights[4]+weights[5];sum67<=weights[6]+weights[7];len_m<=len2;
            saved_x0<=leaf_x0;saved_x1<=leaf_x1;saved_y0<=leaf_y0;
            saved_rl<=leaf_rl;saved_rh<=leaf_rh;saved_pl<=leaf_pl;saved_ph<=leaf_ph;
            saved_match<=region_match;saved_pv<=pv;u_m<=u2;en_m<=en2;eof_m<=eof2;
            hit_m<=hit2;y_m<=y2;saved_slot<=slot;slot_valid<=slot>=0;
            if(u_m)begin used<=0;prev_valid<=0;end
            if(hit_m && slot_valid)begin
                for(i=0;i<REGIONS;i=i+1)begin
                    if(saved_match[i])begin used[i]<=0;prev_valid[i]<=0;end
                    if(saved_slot==i)begin
                        used[i]<=1;area[i]<=merged_area;lx[i]<=mx0;hx[i]<=mx1;ly[i]<=my0;hy[i]<=y_m;
                        row_lo[i]<=rl;row_hi[i]<=rh;prev_valid[i]<=saved_pv;prev_lo[i]<=pl;prev_hi[i]<=ph;
                    end
                end
            end
            u3<=u_m;en3<=en_m;eof3<=eof_m;qualified3<=qualifies;
            area3<=merged_area;x03<=mx0;x13<=mx1;y03<=my0;y13<=y_m;
            if(u3)best_area<=0;
            if(improve)begin
                best_area<=area3;best_x0<=x03;best_x1<=x13;best_y0<=y03;best_y1<=y13;
            end
            frame_done<=eof3;
            if(u1)begin
                previous_color<=color1;
                if(!en1 || color1!=previous_color)begin found<=0;pair_count<=0;end
            end
            if(eof3)begin
                found<=en3 && final_area!=0;pair_count<=en3?final_area:20'd0;
                xmin<=final_area==0?11'd0:(improve?x03:best_x0);
                xmax<=final_area==0?11'd0:(improve?x13:best_x1);
                ymin<=final_area==0?11'd0:(improve?y03:best_y0);
                ymax<=final_area==0?11'd0:(improve?y13:best_y1);
            end
        end
    end
endmodule
