// All physical-key decisions use the continuous board oscillator.
module mode_button_control #(
 parameter integer DEBOUNCE_CYCLES=500000,LONG_PRESS_CYCLES=50000000
)(
 input wire clk,rst_n,input wire[3:0]buttons,
 output reg[2:0]mode,output reg[7:0]binary_threshold,edge_threshold,red_threshold,
 output reg[1:0]target_color,output reg cal_capture,cal_toggle,cal_clear,wall_enabled,
 input wire[2:0]wall_status,
 output reg capture_request,effect_request,pen_toggle,paint_clear,color_request,home_request
);
 localparam CW=DEBOUNCE_CYCLES<2?1:$clog2(DEBOUNCE_CYCLES+1);
 localparam HC=$clog2(3*LONG_PRESS_CYCLES+1),POWER_CYCLES=(3*LONG_PRESS_CYCLES)/2;
 (* ASYNC_REG="TRUE" *)reg[3:0]sync1,sync2;
 reg[3:0]qualified,seen;reg[CW-1:0]debounce[0:3];
 reg[HC-1:0]hold3,hold4,count12,count34;
 reg chord12,chord34,chord34_paint,chord34_sent,long3_sent,long4_sent;
 reg block3,block4,press_on3,press_on4,press_paint3,press_paint4;
 reg[2:0]press_mode3,press_mode4;
 wire pair12=!qualified[0]&&!qualified[1],pair34=!qualified[2]&&!qualified[3];
 wire wall_context=wall_enabled&&mode==0;
 integer i;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   sync1<=15;sync2<=15;qualified<=15;
   for(i=0;i<4;i=i+1)debounce[i]<=0;
  end else begin
   sync1<=buttons;sync2<=sync1;
   for(i=0;i<4;i=i+1)begin
    if(sync2[i]==qualified[i])debounce[i]<=0;
    else if(debounce[i]==DEBOUNCE_CYCLES-1)begin qualified[i]<=sync2[i];debounce[i]<=0;end
    else debounce[i]<=debounce[i]+1'b1;
   end
  end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   mode<=3;binary_threshold<=96;edge_threshold<=96;red_threshold<=32;target_color<=2;
   wall_enabled<=0;seen<=0;hold3<=0;hold4<=0;count12<=0;count34<=0;
   chord12<=0;chord34<=0;chord34_paint<=0;chord34_sent<=0;long3_sent<=0;long4_sent<=0;
   block3<=0;block4<=0;press_mode3<=0;press_mode4<=0;
   press_on3<=0;press_on4<=0;press_paint3<=0;press_paint4<=0;
   cal_capture<=0;cal_toggle<=0;cal_clear<=0;
   capture_request<=0;effect_request<=0;pen_toggle<=0;paint_clear<=0;color_request<=0;home_request<=0;
  end else begin
   cal_capture<=0;cal_toggle<=0;cal_clear<=0;
   capture_request<=0;effect_request<=0;pen_toggle<=0;paint_clear<=0;color_request<=0;home_request<=0;
   // Chords consume both keys through staggered releases. K1 has no long action.
   if(!qualified[0])seen[0]<=1;
   else if(seen[0])begin if(!chord12)mode<=mode==7?0:mode+1'b1;seen[0]<=0;end
   if(!qualified[1])begin
    seen[1]<=1;
   end else if(seen[1])begin
    if(!chord12)mode<=0; // K2 always returns RGB; calibration cannot be bypassed.
    seen[1]<=0;
   end
   if(pair12)begin
    mode<=0;
    if(!chord12)begin chord12<=1;count12<=1;end
    else if(count12<LONG_PRESS_CYCLES)count12<=count12+1'b1;
   end else if(chord12&&qualified[0]&&qualified[1])begin
    if(count12>=LONG_PRESS_CYCLES)cal_capture<=1; // Longer holds still capture; never erase valid gains.
    chord12<=0;count12<=0;
   end
   if(!qualified[2])begin
    if(!seen[2])begin
     seen[2]<=1;hold3<=1;long3_sent<=0;block3<=chord34||pair34||chord12||pair12;
     press_mode3<=mode;press_on3<=wall_enabled;press_paint3<=wall_status==3;
    end else begin
     if(hold3<POWER_CYCLES)hold3<=hold3+1'b1;
     if(chord34||pair34||chord12||pair12)block3<=1;
     if(!long3_sent&&!block3&&!chord34&&!pair34&&!chord12&&!pair12&&hold3>=POWER_CYCLES-1)begin
      wall_enabled<=~wall_enabled;long3_sent<=1;if(!wall_enabled)home_request<=1;
     end
    end
   end else if(seen[2])begin
    if(!long3_sent&&!block3&&!chord34&&!chord12&&mode==press_mode3)begin
     case(mode)
      2:if(binary_threshold<248)binary_threshold<=binary_threshold+8;
      3,7:if(edge_threshold<248)edge_threshold<=edge_threshold+8;
      4:if(target_color<3)target_color<=target_color+1'b1;
      5:if(red_threshold<120)red_threshold<=red_threshold+8;
      0:if(wall_enabled&&press_on3)begin
       if(press_paint3&&wall_status==3)pen_toggle<=1;
       else if(!press_paint3&&wall_status!=3)capture_request<=1;
      end
      default:;
     endcase
    end
    seen[2]<=0;hold3<=0;long3_sent<=0;block3<=0;
   end
   if(!qualified[3])begin
    if(!seen[3])begin
     seen[3]<=1;hold4<=1;long4_sent<=0;block4<=chord34||pair34||chord12||pair12;
     press_mode4<=mode;press_on4<=wall_enabled;press_paint4<=wall_status==3;
    end else begin
     if(hold4<LONG_PRESS_CYCLES)hold4<=hold4+1'b1;
     if(chord34||pair34||chord12||pair12)block4<=1;
     if(!long4_sent&&!block4&&!chord34&&!pair34&&!chord12&&!pair12&&hold4>=LONG_PRESS_CYCLES-1)begin
      long4_sent<=1;
      if(wall_context&&press_on4&&press_mode4==0&&press_paint4&&wall_status==3)color_request<=1;
     end
    end
   end else if(seen[3])begin
    if(!long4_sent&&!block4&&!chord34&&!chord12&&mode==press_mode4)begin
     case(mode)
      2:if(binary_threshold>8)binary_threshold<=binary_threshold-8;
      3,7:if(edge_threshold>8)edge_threshold<=edge_threshold-8;
      4:if(target_color>1)target_color<=target_color-1'b1;
      5:if(red_threshold>8)red_threshold<=red_threshold-8;
      0:if(wall_enabled&&press_on4)effect_request<=1;
      default:;
     endcase
    end
    seen[3]<=0;hold4<=0;long4_sent<=0;block4<=0;
   end
   // Short K3/K4 overlap cancels both singles. Only a >=1s DRAW chord clears.
   if(pair34&&!chord12&&!pair12)begin
    if(!chord34)begin
     chord34<=1;count34<=1;chord34_sent<=0;
     chord34_paint<=wall_context&&wall_status==3&&!long3_sent&&!long4_sent;
    end else if(count34<LONG_PRESS_CYCLES)count34<=count34+1'b1;
    if(chord34&&!chord34_sent&&count34>=LONG_PRESS_CYCLES-1)begin
     chord34_sent<=1;if(chord34_paint&&wall_context&&wall_status==3)paint_clear<=1;
    end
   end else if(chord34&&qualified[2]&&qualified[3])begin
    chord34<=0;count34<=0;chord34_sent<=0;chord34_paint<=0;
   end
  end
 end
endmodule

// Held-payload CDC: latest coherent configuration and ordered CAL commands.
// All lamp commands remain in the 50MHz domain, independent of camera clocks.
module realtime_mode_control #(
 parameter integer CLOCK_HZ=50000000,DEBOUNCE_CYCLES=CLOCK_HZ/100
)(
 input wire sys_clk,cam_clk,rst_n,input wire[3:0]buttons,input wire[2:0]wall_status,
 output reg[2:0]mode,output reg[7:0]binary_threshold,edge_threshold,red_threshold,
 output reg[1:0]target_color,output reg cal_capture,cal_toggle,cal_clear,
 output wire wall_enabled,capture_request,effect_request,pen_toggle,paint_clear,color_request,home_request
);
 wire[2:0]src_mode;wire[7:0]src_binary,src_edge,src_red;wire[1:0]src_color;
 wire src_capture,src_toggle,src_clear;
 mode_button_control #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),.LONG_PRESS_CYCLES(CLOCK_HZ))keys(
  .clk(sys_clk),.rst_n(rst_n),.buttons(buttons),.wall_status(wall_status),
  .mode(src_mode),.binary_threshold(src_binary),.edge_threshold(src_edge),.red_threshold(src_red),.target_color(src_color),
  .cal_capture(src_capture),.cal_toggle(src_toggle),.cal_clear(src_clear),.wall_enabled(wall_enabled),
  .capture_request(capture_request),.effect_request(effect_request),.pen_toggle(pen_toggle),
  .paint_clear(paint_clear),.color_request(color_request),.home_request(home_request));
 wire[28:0]config_bus={src_mode,src_color,src_binary,src_edge,src_red};
 wire[1:0]new_command=src_clear?2'd3:(src_toggle?2'd2:(src_capture?2'd1:2'd0));
 reg[1:0]queue[0:7];reg[2:0]rd,wr;reg[3:0]queued;
 reg[30:0]mailbox;reg[28:0]sent_config;reg request,acknowledge;
 (* ASYNC_REG="TRUE" *)reg ack_s1,ack_s2,req_s1,req_s2;
 wire send_mail=request==ack_s2&&(config_bus!=sent_config||queued!=0);
 wire pop=send_mail&&queued!=0;
 wire push=new_command!=0&&(queued<8||pop);
 // Eight queued commands plus one in flight. Camera-off input beyond that
 // finite capacity drops newest; running-camera service takes microseconds.
 always @(posedge sys_clk or negedge rst_n)begin
  if(!rst_n)begin
   mailbox<={2'd0,3'd3,2'd2,8'd96,8'd96,8'd32};sent_config<={3'd3,2'd2,8'd96,8'd96,8'd32};
   request<=0;ack_s1<=0;ack_s2<=0;rd<=0;wr<=0;queued<=0;
  end else begin
   ack_s1<=acknowledge;ack_s2<=ack_s1;
   if(push)begin queue[wr]<=new_command;wr<=wr+1'b1;end
   if(pop)rd<=rd+1'b1;
   case({push,pop})2'b10:queued<=queued+1'b1;2'b01:queued<=queued-1'b1;default:;endcase
   if(send_mail)begin
    mailbox<={queued!=0?queue[rd]:2'd0,config_bus};sent_config<=config_bus;request<=!request;
   end
  end
 end
 reg copy_pending;
 always @(posedge cam_clk or negedge rst_n)begin
  if(!rst_n)begin
   req_s1<=0;req_s2<=0;acknowledge<=0;copy_pending<=0;
   mode<=3;target_color<=2;binary_threshold<=96;edge_threshold<=96;red_threshold<=32;
   cal_capture<=0;cal_toggle<=0;cal_clear<=0;
  end else begin
   req_s1<=request;req_s2<=req_s1;cal_capture<=0;cal_toggle<=0;cal_clear<=0;
   if(copy_pending)begin
    {mode,target_color,binary_threshold,edge_threshold,red_threshold}<=mailbox[28:0];
    cal_capture<=mailbox[30:29]==1;cal_toggle<=mailbox[30:29]==2;cal_clear<=mailbox[30:29]==3;
    acknowledge<=req_s2;copy_pending<=0;
   end else if(req_s2!=acknowledge)copy_pending<=1;
  end
 end
endmodule
