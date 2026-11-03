`timescale 1ns/1ps
module tb_wall_switch_live;
 reg completed=0;
 reg cc=0,lc=0,rst=0,v=0,u=0,l=0,en=0;
 always #4.83 cc=~cc;always #10 lc=~lc;
 reg[95:0]rgb=0;wire data;wire[2:0]status;
 interactive_lightwall #(.POWER_SWITCH(1)) dut(.cam_clk(cc),.led_clk(lc),.rst_n(rst),
  .video_valid(v),.video_user(u),.video_last(l),.video_rgb(rgb),
  .capture_request(1'b0),.effect_request(1'b0),.pen_toggle(1'b0),.paint_clear(1'b0),.color_request(1'b0),.home_request(1'b0),.wall_enable(en),.ws_data(data),.wall_status(status),
  .marker_valid(),.marker_u(),.marker_v(),.pen_down(),.canvas_write(),.canvas_addr(),
  .canvas_rgb(),.canvas_done(),.brush_color());
 defparam dut.painter.WARMUP_FRAMES=0;
 defparam dut.painter.CAL_FRAMES=1;
 integer acknowledgements=0,engine_words=0,nonzero=0,black_words=0;
 reg[1:0]old_ack=0;
 always @(posedge lc)if(rst)begin
  if(dut.acknowledge!=old_ack)begin
   acknowledgements++;old_ack=dut.acknowledge;
  end
  if(dut.word_ready && dut.word_valid)engine_words++;
  if(dut.transmitter.core_ready && dut.transmitter.core.word_valid)begin
   if(dut.transmitter.core.word_data!=0)nonzero++;
   else black_words++;
  end
 end
 task frame(input bit object_present);
  integer x,y;reg[23:0]pixel;
  begin
   for(y=0;y<720;y++)for(x=0;x<320;x++)begin
    @(negedge cc);v=1;u=x==0&&y==0;l=x==319;
    pixel=object_present && x>=100&&x<130&&y>=225&&y<360?24'hd8b894:24'h304050;
    rgb={4{pixel}};
   end
   @(negedge cc);v=0;u=0;l=0;
   // Allow the capture's trailing area-average pipeline to publish before SOF.
   repeat(32)@(negedge cc);
  end
 endtask
 integer before_words,before_nonzero;
 initial begin
  #73;rst=1;
  frame(0);frame(0);frame(0);
  if(status!=7||nonzero||dut.capture.published!=2||dut.capture.dropped!=1)
   $fatal(1,"OFF startup/capture independence status%0d pub%0d drop%0d nonzero%0d",status,dut.capture.published,dut.capture.dropped,nonzero);
  // Bank ownership must recover after frames filled while OFF.
  en=1;wait(acknowledgements==2);repeat(5)@(negedge lc);
  if(status!=2||engine_words!=1024)$fatal(1,"ON did not drain queued camera banks");
  frame(1);wait(dut.led_state==3);en=0;
  wait(acknowledgements==3);repeat(820000)@(negedge lc);
  if(status!=7)$fatal(1,"OFF status missing");
  before_nonzero=nonzero;before_words=black_words;
  repeat(820000)@(negedge lc);
  if(nonzero!=before_nonzero||black_words<=before_words)$fatal(1,"OFF did not actively flush black without camera");
  en=1;repeat(820000)@(negedge lc);frame(1);wait(acknowledgements==4);repeat(5)@(negedge lc);
  if(status!=2||engine_words!=2048||nonzero==0)$fatal(1,"resume lost live output/bank handshake");
  completed=1;
  $display("PASS wall switch live: five 720p camera frames, default OFF, full banks and recovery, four complete 512-word engine transmissions, active camera-free blackout, resume and LIVE status");$finish;
 end
 initial begin #250000000;$fatal(1,"live switch watchdog");end
endmodule
