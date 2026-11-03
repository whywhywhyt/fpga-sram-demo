`timescale 1ns/1ps
// All image-effect work is serialized at 50 MHz on the 32x16 tile grid.
// Only fully validated frames reach this module. Background and trail state
// therefore cannot be poisoned by an unvalidated/partial camera frame.
module wall_light_painter #(
    parameter integer GRID_W=32, GRID_H=16,
    parameter integer WARMUP_FRAMES=120, CAL_FRAMES=16,
    parameter integer FG_ON=12, FG_OFF=8, DECAY_STEP=1,
    parameter integer PIXELS=GRID_W*GRID_H, AW=$clog2(PIXELS)
)(
    input wire clk,rst_n,
    input wire tile_valid,
    input wire [AW-1:0] tile_addr,
    input wire [23:0] tile_rgb,
    input wire frame_start,capture_request,effect_request,
    input wire home_request,
    input wire marker_valid,input wire [4:0] marker_x,input wire [3:0] marker_y,
    input wire pen_toggle,paint_clear,color_request,
    output reg [2:0] brush_color,
    output reg pen_down,
    output wire canvas_write,output wire [8:0] canvas_addr,output wire [23:0] canvas_rgb,
    input wire [AW-1:0] read_addr,
    output reg [23:0] read_rgb,
    output wire busy,
    output reg frame_done,
    output reg [2:0] status,
    output reg [9:0] foreground_count
);
    // Status: WAIT=0, CAL=1, LIVE=2, PAINT=3, HOLD=4, LIGHT/RECAP=5.
    reg [17:0] current[0:PIXELS-1],background[0:PIXELS-1];
    reg raw_mask[0:PIXELS-1],clean_mask[0:PIXELS-1];
    // {previous supported foreground, retained hue, intensity[5:0]}.
    reg [7:0] trail[0:PIXELS-1];
    reg [2:0] paint_colors[0:PIXELS-1];
    reg [2:0] paint_color_q,frame_brush;
    reg [23:0] display[0:PIXELS-1];
    reg [4:0] state;
    localparam INIT=0,IDLE=1,AREAD=2,ADIFF=3,AWRT=4,
               FSET=5,FREAD=6,FUSE=7,FWRITE=8,
               CSET=9,CREAD=10,CUSE=11,CWRITE=12,FINISH=13,
               PSET=14,PCLEAR=15,PLINE=16;
    reg [AW-1:0] idx,neighbor_addr;
    reg [2:0] neighbor;
    reg sample_bit,self_bit,adjacent_bit,all_bit;
    reg [17:0] cur_q,bg_q;
    reg [7:0] trail_q,difference;
    reg [7:0] warmup_count;
    reg [5:0] calibration_count;
    reg bg_valid,calibrating,pending_capture,clear_trails,pending_home;
    reg [1:0] effect,frame_effect;
    wire [1:0] next_effect=(pending_home || home_request)?2'd0:effect;
    reg [5:0] min_x,max_x,old_center_x,center_x;
    reg [4:0] min_y,max_y,old_center_y,center_y;
    reg [5:0] ripple_phase;
    // Keep the last valid color origin during fade-out. Triggering, wave
    // geometry and energy decay remain the restored baseline implementation.
    reg [5:0] rainbow_x;
    reg [4:0] rainbow_y;
    reg old_center_valid,fast_hue,lighting_block;
    wire [5:0] xpos=idx%GRID_W;
    wire [4:0] ypos=idx/GRID_W;
    wire [5:0] new_center_x=({1'b0,min_x}+{1'b0,max_x})>>1;
    wire [4:0] new_center_y=({1'b0,min_y}+{1'b0,max_y})>>1;
    wire [5:0] speed_x=(new_center_x>=old_center_x)?new_center_x-old_center_x:old_center_x-new_center_x;
    wire [4:0] speed_y=(new_center_y>=old_center_y)?new_center_y-old_center_y:old_center_y-new_center_y;
    wire [6:0] speed={1'b0,speed_x}+{2'b0,speed_y};
    wire supported=self_bit && adjacent_bit;
    wire active_core=self_bit && !calibrating && !lighting_block;
    wire active_halo=adjacent_bit && !calibrating && !lighting_block;
    wire contour_bit=self_bit && !all_bit;
    wire active_contour=frame_effect==0 && contour_bit && !calibrating && !lighting_block;
    // PAINT uses the independently tracked marker, never the foreground box.
    reg previous_pen_valid,frame_marker_valid,frame_pen_down,pending_clear;
    reg [4:0] previous_pen_x,frame_pen_x,line_x,end_x;
    reg [3:0] previous_pen_y,frame_pen_y,line_y,end_y;
    reg [5:0] line_dx,line_dy;
    reg signed [7:0] line_error;
    wire signed [8:0] twice_error=$signed(line_error)*2;
    wire step_x=twice_error>=-$signed({1'b0,line_dy});
    wire step_y=twice_error<=$signed({1'b0,line_dx});
    wire [5:0] pen_dx=frame_pen_x>=previous_pen_x?frame_pen_x-previous_pen_x:previous_pen_x-frame_pen_x;
    wire [4:0] pen_dy=frame_pen_y>=previous_pen_y?frame_pen_y-previous_pen_y:previous_pen_y-frame_pen_y;
    wire connect_pen=previous_pen_valid && ({1'b0,pen_dx}+{2'b0,pen_dy}<=16);
    wire [4:0] begin_x=connect_pen?previous_pen_x:frame_pen_x;
    wire [3:0] begin_y=connect_pen?previous_pen_y:frame_pen_y;
    wire [5:0] segment_dx=frame_pen_x>=begin_x?frame_pen_x-begin_x:begin_x-frame_pen_x;
    wire [5:0] segment_dy=frame_pen_y>=begin_y?frame_pen_y-begin_y:begin_y-frame_pen_y;
    wire [5:0] ripple_dx=abs6(xpos,center_x);
    wire [4:0] ripple_dy=(ypos>=center_y)?(ypos-center_y):(center_y-ypos);
    wire [5:0] ripple_hi=(ripple_dx>={1'b0,ripple_dy})?ripple_dx:{1'b0,ripple_dy};
    wire [4:0] ripple_lo=(ripple_dx>={1'b0,ripple_dy})?ripple_dy:ripple_dx[4:0];
    wire [5:0] ripple_dist=ripple_hi+{1'b0,ripple_lo[4:1]};
    wire [5:0] ripple_error=(ripple_dist>=ripple_phase)?ripple_dist-ripple_phase:ripple_phase-ripple_dist;
    wire ripple_valid=frame_effect==3 && foreground_count>=4 && !lighting_block;
    wire ripple_core=ripple_valid && ripple_error==0;
    wire ripple_halo=ripple_valid && ripple_error==1;
    wire [5:0] color_dx=abs6(xpos,rainbow_x);
    wire [4:0] color_dy=(ypos>=rainbow_y)?ypos-rainbow_y:rainbow_y-ypos;
    wire [5:0] color_hi=(color_dx>={1'b0,color_dy})?color_dx:{1'b0,color_dy};
    wire [4:0] color_lo=(color_dx>={1'b0,color_dy})?color_dy:color_dx[4:0];
    wire [5:0] color_radius=color_hi+{1'b0,color_lo[4:1]};
    wire [5:0] target=frame_effect==1?6'd0:
                      frame_effect==3?(ripple_core?6'd63:(ripple_halo?6'd28:6'd0)):
                      (active_core?6'd63:(active_halo?6'd14:6'd0));
    wire [5:0] decayed=(calibrating || clear_trails)?6'd0:
        (frame_effect==1?trail_q[5:0]:
        (trail_q[5:0]>DECAY_STEP?trail_q[5:0]-DECAY_STEP:6'd0));
    wire [5:0] energy=(target>decayed)?target:decayed;
    wire hue=(target!=0 && target>=decayed)?
             (frame_effect==3?(ripple_phase[2]^fast_hue):fast_hue):trail_q[6];
    assign busy=(state!=IDLE);
    assign canvas_write=state==CWRITE;
    assign canvas_addr=idx;
    assign canvas_rgb=frame_effect==1?(energy!=0?paint_palette(paint_color_q):24'h000000):
        (frame_effect==3?rainbow_palette(energy,color_radius[3:1]):
        (active_contour?contour_palette(energy):palette(energy,hue)));
    // The per-channel ceiling stays at 32/255. Each pixel stores its own
    // palette index, so changing brushes never recolors existing artwork.
    function [23:0] paint_palette;
        input [2:0] color;
        begin case(color)
            0:paint_palette=24'h042018; // cyan (accepted brightness)
            1:paint_palette=24'h040820; // blue
            2:paint_palette=24'h180420; // purple
            3:paint_palette=24'h200404; // red
            4:paint_palette=24'h201004; // orange
            default:paint_palette=24'h042004; // green
        endcase end
    endfunction
    function [5:0] abs6;
        input [5:0] a,b;
        begin abs6=(a>b)?a-b:b-a;end
    endfunction
    function [5:0] bg_mix;
        input [5:0] a,b;
        reg [7:0] sum;
        begin sum={2'b0,a}+{1'b0,a,1'b0}+{2'b0,b}+8'd2;bg_mix=sum[7:2];end
    endfunction
    function [5:0] dim6;
        input [5:0] v;
        reg [6:0] q;
        begin q=({1'b0,v}+1'b1)>>1;dim6=(q==0 && v!=0)?6'd1:q[5:0];end
    endfunction
    // RGB components are kept at <=63: no implicit second brightness divider.
    function [23:0] palette;
        input [5:0] e;
        input fast;
        reg [5:0] r,g,b;
        begin
            if(e==0)begin r=0;g=0;b=0;end
            else if(e>=48)begin r=fast?e:(e>>3);g=fast?(e>>3):e;b=e-(e>>2);end
            else if(e>=24)begin r=e>>2;g=e>>2;b=e;end
            else begin r=e;g=0;b=e;end
            palette={2'b0,dim6(r),2'b0,dim6(g),2'b0,dim6(b)};
        end
    endfunction
    function [23:0] contour_palette;
        input [5:0] e;
        reg [5:0] r,g,b;
        begin r=e>>1;g=e;b=e;contour_palette={2'b0,dim6(r),2'b0,dim6(g),2'b0,dim6(b)};end
    endfunction
    function [23:0] rainbow_palette;
        input [5:0] e;
        input [2:0] band;
        reg [5:0] r,g,b,q;
        begin
            r=0;g=0;b=0;q=e-(e>>2);
            case(band)
                0:r=e;                             // red origin
                1:begin r=e;g=e>>1;end              // orange
                2:begin r=q;g=q;end                 // yellow, balanced peak
                3:g=e;                             // green
                4:begin g=q;b=q;end                 // cyan
                5:b=e;                             // blue
                default:begin r=e>>1;b=e;end        // violet, then repeat
            endcase
            rainbow_palette={2'b0,dim6(r),2'b0,dim6(g),2'b0,dim6(b)};
        end
    endfunction
    // Synchronous RAM ports, no array reset. INIT clears only the displayed
    // image and trail; background is not read until first calibration writes.
    always @(posedge clk)begin
        if(tile_valid && state==IDLE)current[tile_addr]<={tile_rgb[23:18],tile_rgb[15:10],tile_rgb[7:2]};
        read_rgb<=display[read_addr];
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=INIT;idx<=0;neighbor_addr<=0;neighbor<=0;
            frame_done<=0;status<=0;foreground_count<=0;
            warmup_count<=WARMUP_FRAMES;calibration_count<=0;bg_valid<=0;
            calibrating<=0;pending_capture<=0;clear_trails<=0;pending_home<=0;
            effect<=0;frame_effect<=0;min_x<=0;max_x<=0;min_y<=0;max_y<=0;ripple_phase<=0;
            rainbow_x<=0;rainbow_y<=0;
            old_center_x<=0;old_center_y<=0;center_x<=0;center_y<=0;
            old_center_valid<=0;fast_hue<=0;lighting_block<=0;
            cur_q<=0;bg_q<=0;trail_q<=0;difference<=0;
            sample_bit<=0;self_bit<=0;adjacent_bit<=0;all_bit<=1;
            brush_color<=0;frame_brush<=0;paint_color_q<=0;
            pen_down<=0;previous_pen_valid<=0;frame_marker_valid<=0;frame_pen_down<=0;pending_clear<=0;
            previous_pen_x<=0;previous_pen_y<=0;frame_pen_x<=0;frame_pen_y<=0;
            line_x<=0;line_y<=0;end_x<=0;end_y<=0;line_dx<=0;line_dy<=0;line_error<=0;
        end else begin
            frame_done<=0;
            if(home_request)pending_home<=1;
            // Apply only between frames; preserve background and color math.
            if(state==IDLE && (pending_home || home_request))begin
                effect<=0;pending_home<=0;clear_trails<=1;
                pen_down<=0;previous_pen_valid<=0;
                status<=bg_valid?3'd2:3'd0;
            end
            if(color_request && effect==1)begin
                brush_color<=brush_color==5?0:brush_color+1'b1;
                pen_down<=0;previous_pen_valid<=0;
            end
            if(pen_toggle && effect==1 && !color_request)begin pen_down<=~pen_down;previous_pen_valid<=0;end
            if(paint_clear && effect==1)begin pending_clear<=1;pen_down<=0;previous_pen_valid<=0;end
            if(!marker_valid)previous_pen_valid<=0;
            if(capture_request)begin pending_capture<=1;effect<=0;brush_color<=0;pen_down<=0;previous_pen_valid<=0;end
            else if(effect_request)begin
                effect<=(effect==3)?0:effect+1'b1;
                if(effect==0)brush_color<=0;
                pen_down<=0;previous_pen_valid<=0;
                if(effect==0 || effect==2 || effect==3)clear_trails<=1;
                if(effect==2)ripple_phase<=0;
            end
            case(state)
                INIT:begin
                    display[idx]<=0;trail[idx]<=0;paint_colors[idx]<=0;
                    if(idx==PIXELS-1)begin idx<=0;state<=IDLE;end else idx<=idx+1'b1;
                end
                IDLE:if(frame_start)begin
                    if(pending_capture || capture_request)begin
                        pending_capture<=0;bg_valid<=0;calibration_count<=0;warmup_count<=0;
                        effect<=0;frame_effect<=0;calibrating<=1;status<=1;
                        foreground_count<=0;old_center_valid<=0;idx<=0;state<=AREAD;
                    end else if(warmup_count!=0)begin
                        warmup_count<=warmup_count-1'b1;frame_done<=1;status<=0;
                    end else if(next_effect==2 && bg_valid)begin
                        // A held artwork stays unchanged even while input banks drain.
                        status<=4;frame_done<=1;
                    end else begin
                        frame_effect<=next_effect;calibrating<=!bg_valid;idx<=0;state<=AREAD;
                        frame_marker_valid<=marker_valid;frame_pen_x<=marker_x;frame_pen_y<=marker_y;
                        frame_pen_down<=pen_down;frame_brush<=brush_color;
                        if(pending_clear || paint_clear)begin clear_trails<=1;pending_clear<=0;end
                        foreground_count<=0;lighting_block<=0;
                        min_x<=GRID_W-1;max_x<=0;min_y<=GRID_H-1;max_y<=0;
                        status<=!bg_valid?1:(next_effect==1?3:(next_effect==3?6:2));
                    end
                end
                AREAD:begin
                    cur_q<=current[idx];bg_q<=background[idx];trail_q<=trail[idx];state<=ADIFF;
                end
                ADIFF:begin
                    difference<={2'b0,abs6(cur_q[17:12],bg_q[17:12])}+
                                {2'b0,abs6(cur_q[11:6],bg_q[11:6])}+
                                {2'b0,abs6(cur_q[5:0],bg_q[5:0])};state<=AWRT;
                end
                AWRT:begin
                    if(calibrating)begin
                        if(calibration_count==0)background[idx]<=cur_q;
                        else background[idx]<={bg_mix(bg_q[17:12],cur_q[17:12]),
                            bg_mix(bg_q[11:6],cur_q[11:6]),bg_mix(bg_q[5:0],cur_q[5:0])};
                        raw_mask[idx]<=0;
                    end else raw_mask[idx]<=(difference>=(trail_q[7]?FG_OFF:FG_ON));
                    if(idx==PIXELS-1)begin idx<=0;state<=FSET;end
                    else begin idx<=idx+1'b1;state<=AREAD;end
                end
                FSET:begin neighbor<=0;neighbor_addr<=idx;self_bit<=0;adjacent_bit<=0;all_bit<=1;state<=FREAD;end
                FREAD:begin sample_bit<=raw_mask[neighbor_addr];state<=FUSE;end
                FUSE:begin
                    if(neighbor==0)self_bit<=sample_bit;
                    else if((neighbor==1 && xpos!=0) || (neighbor==2 && xpos!=GRID_W-1) ||
                            (neighbor==3 && ypos!=0) || (neighbor==4 && ypos!=GRID_H-1)) begin
                        adjacent_bit<=adjacent_bit|sample_bit; all_bit<=all_bit&sample_bit;
                    end else all_bit<=0;
                    case(neighbor)
                        0:neighbor_addr<=idx-1'b1;
                        1:neighbor_addr<=idx+1'b1;
                        2:neighbor_addr<=idx-GRID_W;
                        3:neighbor_addr<=idx+GRID_W;
                        default:;
                    endcase
                    if(neighbor==4)state<=FWRITE;
                    else begin neighbor<=neighbor+1'b1;state<=FREAD;end
                end
                FWRITE:begin
                    clean_mask[idx]<=supported;
                    if(supported)begin
                        foreground_count<=foreground_count+1'b1;
                        if(xpos<min_x)min_x<=xpos;if(xpos>max_x)max_x<=xpos;
                        if(ypos<min_y)min_y<=ypos;if(ypos>max_y)max_y<=ypos;
                    end
                    if(idx==PIXELS-1)begin idx<=0;state<=frame_effect==1?PSET:CSET;neighbor<=7;end
                    else begin idx<=idx+1'b1;state<=FSET;end
                end
                PSET:begin
                    if(clear_trails)begin idx<=0;state<=PCLEAR;previous_pen_valid<=0;end
                    else if(frame_marker_valid && frame_pen_down && !calibrating)begin
                        line_x<=begin_x;line_y<=begin_y;end_x<=frame_pen_x;end_y<=frame_pen_y;
                        line_dx<=segment_dx;line_dy<=segment_dy;
                        line_error<=$signed({1'b0,segment_dx})-$signed({1'b0,segment_dy});state<=PLINE;
                    end else begin previous_pen_valid<=0;idx<=0;state<=CSET;end
                end
                PCLEAR:begin
                    trail[idx]<=0;
                    if(idx==PIXELS-1)begin idx<=0;clear_trails<=0;state<=PSET;end else idx<=idx+1'b1;
                end
                PLINE:begin
                    // Bresenham includes both endpoints. One RAM write per
                    // clock, no divide/multiply or thick halo in the stroke.
                    trail[{line_y,line_x}]<=8'h3f;
                    paint_colors[{line_y,line_x}]<=frame_brush;
                    if(line_x==end_x && line_y==end_y)begin
                        previous_pen_x<=end_x;previous_pen_y<=end_y;
                        previous_pen_valid<=marker_valid && pen_down;
                        idx<=0;state<=CSET;
                    end else begin
                        line_error<=line_error-(step_x?$signed({1'b0,line_dy}):8'sd0)+
                                                (step_y?$signed({1'b0,line_dx}):8'sd0);
                        if(step_x)line_x<=line_x<end_x?line_x+1'b1:line_x-1'b1;
                        if(step_y)line_y<=line_y<end_y?line_y+1'b1:line_y-1'b1;
                    end
                end
                CSET:begin
                    if(neighbor==7)begin
                        // The prior cycle finished the entire connected-mask pass.
                        lighting_block<=foreground_count>(PIXELS*3/4);
                        fast_hue<=old_center_valid && foreground_count!=0 && speed>=2;
                        center_x<=new_center_x;center_y<=new_center_y;
                        if(frame_effect==3 && foreground_count>=4 && foreground_count<=(PIXELS*3/4) && !calibrating)begin
                            rainbow_x<=new_center_x;rainbow_y<=new_center_y;
                            // A fresh foreground starts at the red origin,
                            // without the rejected two-slot/cooldown scheme.
                            if(!old_center_valid)ripple_phase<=0;
                        end
                    end
                    neighbor<=0;neighbor_addr<=idx;self_bit<=0;adjacent_bit<=0;all_bit<=1;
                    trail_q<=trail[idx];paint_color_q<=paint_colors[idx];state<=CREAD;
                end
                CREAD:begin sample_bit<=clean_mask[neighbor_addr];state<=CUSE;end
                CUSE:begin
                    if(neighbor==0)self_bit<=sample_bit;
                    else if((neighbor==1 && xpos!=0) || (neighbor==2 && xpos!=GRID_W-1) ||
                            (neighbor==3 && ypos!=0) || (neighbor==4 && ypos!=GRID_H-1)) begin
                        adjacent_bit<=adjacent_bit|sample_bit; all_bit<=all_bit&sample_bit;
                    end else all_bit<=0;
                    case(neighbor)
                        0:neighbor_addr<=idx-1'b1;
                        1:neighbor_addr<=idx+1'b1;
                        2:neighbor_addr<=idx-GRID_W;
                        3:neighbor_addr<=idx+GRID_W;
                        default:;
                    endcase
                    if(neighbor==4)state<=CWRITE;
                    else begin neighbor<=neighbor+1'b1;state<=CREAD;end
                end
                CWRITE:begin
                    trail[idx]<={active_core,hue,energy};
                    display[idx]<=canvas_rgb;
                    if(idx==PIXELS-1)state<=FINISH;
                    else begin idx<=idx+1'b1;state<=CSET;end
                end
                FINISH:begin
                    frame_done<=1;state<=IDLE;clear_trails<=0;
                    if(calibrating)begin
                        if(calibration_count==CAL_FRAMES-1)begin bg_valid<=1;status<=2;end
                        else calibration_count<=calibration_count+1'b1;
                    end else begin
                        old_center_x<=center_x;old_center_y<=center_y;
                        old_center_valid<=foreground_count!=0 && !lighting_block;
                        if(frame_effect==3 && foreground_count>=4 && !lighting_block)
                            ripple_phase <= (ripple_phase >= 6'd38) ? 6'd0 : (ripple_phase + 1'b1);
                        status<=frame_effect==1?3:(lighting_block?5:(frame_effect==3?6:2));
                    end
                end
                default:state<=INIT;
            endcase
        end
    end
endmodule

// Informational status crosses clocks independently of video. It does not
// control acquisition. This panel is downstream of the light-wall sample tap.
module wall_status_panel(
 input wire clk,rst_n,de,user,last,input wire [2:0] status_async,
 input wire [23:0] pixel,output wire [23:0] out_pixel);
 (* ASYNC_REG="TRUE" *) reg [2:0] status_s1,status_s2;
 reg [2:0] status_frame;reg [10:0] x;reg [9:0] y;
 wire [10:0] px=user?0:x;wire [9:0] py=user?0:y;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin status_s1<=0;status_s2<=0;status_frame<=0;x<=0;y<=0;end
  else begin
   status_s1<=status_async;status_s2<=status_s1;
   if(user)begin status_frame<=status_s2;x<=de?1:0;y<=0;end
   else if(de)begin if(last)begin x<=0;y<=y+1'b1;end else x<=x+1'b1;end
  end
 end
 // Right edge is fixed. Width follows the longest actual string for each
 // frame-latched state: 5, 6 or 7 cells, with eight pixels on either side.
 wire [10:0] text_left=status_frame==5?11'd1144:(status_frame==0 || status_frame==1)?11'd1160:11'd1176;
 wire region=de && px>=text_left-11'd8 && px<1264 && py>=672 && py<704;
 wire [8:0] dx=px-text_left;wire [4:0] dy=py-680;wire [3:0] pos=dx>>4;
 reg [7:0] code;
 always @*begin
  code=32;
  case(pos)
   0:code=8'd174;1:code=8'd175;2:code=":";
   3:case(status_frame)0:code=8'd173;1:code=8'd156;2:code=8'd176;3:code=8'd178;4:code=8'd180;6:code=8'd182;7:code=8'd162;default:code=8'd186;endcase
   4:case(status_frame)0:code=8'd160;1:code=8'd157;2:code=8'd177;3:code=8'd179;4:code=8'd181;6:code=8'd183;7:code=8'd163;default:code=8'd187;endcase
   5:case(status_frame)0:code=8'd161;1:code=8'd150;5:code=8'd156;default:code=32;endcase
   6:if(status_frame==5)code=8'd157;
   default:code=32;
  endcase
 end
 wire [15:0] glyph;presentation_font16 font(.code(code),.row(dy[3:0]),.bits(glyph));
 wire ink=px>=text_left && py>=680 && py<696 && glyph[15-dx[3:0]];
 assign out_pixel=region?(ink?24'h409fff:24'h101820):pixel;
endmodule

