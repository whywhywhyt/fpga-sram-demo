`timescale 1ns/1ps
module tb_integrated #(parameter THROUGH_AWB=0);
 reg cc=0,lc=0,rst=0,v=0,u=0,l=0;always #4.83 cc=~cc;always #10 lc=~lc;
 reg [95:0] rgb=0;reg [3:0] buttons=15;reg [2:0] mode=0;
 wire data;wire [2:0] status;
 wire av,au,al;wire [95:0] ar;
 // Keep gain at unity only in this bench, so the independent pixel oracle
 // remains exact while exercising the production AWB's real RAM/framing.
 awb #(.IMG_WIDTH(1280),.IMG_HEIGHT(720),.MIN_SAMPLES(4194303)) real_awb(
  .I_clk(cc),.I_rst_n(rst),.I_tvalid(v),.I_tuser(u),.I_tlast(l),.I_tdata(rgb),
  .I_tready(),.O_tready(1'b1),.O_tvalid(av),.O_tuser(au),.O_tlast(al),.O_tdata(ar));
 interactive_lightwall dut(.cam_clk(cc),.led_clk(lc),.rst_n(rst),
  .video_valid(THROUGH_AWB?av:v),.video_user(THROUGH_AWB?au:u),.video_last(THROUGH_AWB?al:l),
  .video_rgb(THROUGH_AWB?ar:rgb),.capture_request(1'b0),.effect_request(1'b0),
  .pen_toggle(1'b0),.paint_clear(1'b0),.color_request(1'b0),.home_request(1'b0),
  .wall_enable(1'b1),.ws_data(data),.wall_status(status),
  .marker_valid(),.marker_u(),.marker_v(),.pen_down(),.canvas_write(),.canvas_addr(),
  .canvas_rgb(),.canvas_done(),.brush_color());
 defparam dut.painter.WARMUP_FRAMES=2;
 defparam dut.painter.CAL_FRAMES=1;
 integer energy[0:511],hue[0:511],checks=0,wordn=0,frame_no=0;
 reg mask[0:511];reg [23:0] expected[0:511];
 reg [1:0] prior_ack=0;
 integer oldx=-1;
 function [23:0] color(input integer e,fast);
  integer r,g,b;
  begin
   if(e==0)begin r=0;g=0;b=0;end
   else if(e>=48)begin r=fast?e:e/8;g=fast?e/8:e;b=e-e/4;end
   else if(e>=24)begin r=e/4;g=e/4;b=e;end
   else begin r=e;g=0;b=e;end
   r=(r+1)/2;g=(g+1)/2;b=(b+1)/2;
   color=(r<<16)|(g<<8)|b;
  end
 endfunction
 function [23:0] contour_color(input integer e);
  integer r,g,b;
  begin r=(e/2+1)/2;g=(e+1)/2;b=(e+1)/2;contour_color=(r<<16)|(g<<8)|b;end
 endfunction
 task reference(input integer x0);
  integer i,x,y,nearby,target,fast,alln;
  begin
   fast=oldx>=0&&x0>=0&&((x0-oldx>=2)||(oldx-x0>=2));
   for(i=0;i<512;i=i+1)begin
    x=i%32;y=i/32;mask[i]=(x0>=0&&x>=x0&&x<x0+3&&y>=5&&y<8);
   end
   for(i=0;i<512;i=i+1)begin
    x=i%32;y=i/32;nearby=0;
    if(x>0)nearby=nearby|mask[i-1];if(x<31)nearby=nearby|mask[i+1];
    if(y>0)nearby=nearby|mask[i-32];if(y<15)nearby=nearby|mask[i+32];
    target=mask[i]?63:(nearby?14:0);
    if(energy[i]>0)energy[i]=energy[i]-1;
    if(target>0&&target>=energy[i])hue[i]=fast;
    if(target>energy[i])energy[i]=target;
    alln=1;
    if(x==0 || !mask[i-1])alln=0;if(x==31 || !mask[i+1])alln=0;
    if(y==0 || !mask[i-32])alln=0;if(y==15 || !mask[i+32])alln=0;
    expected[i]=(mask[i] && !alln)?contour_color(energy[i]):color(energy[i],hue[i]);
   end
   oldx=x0;
  end
 endtask
 // Verify accepted serial words independently of the wrapper address
 // expression. Full pulse coding is verified by tb_transport.
 always @(posedge lc)if(rst)begin
  if(dut.word_ready&&dut.word_valid)begin : compare
   integer panel,row,col,index;reg [23:0] want;
   panel=wordn/256;row=(wordn%256)/16;col=wordn%16;
   if(row%2)col=15-col;
   index=row*32+panel*16+col;
   want={expected[index][15:8],expected[index][23:16],expected[index][7:0]};
   if(dut.transmitter.word_data!==want)$fatal(1,"integrated frame%0d serial%0d grid%0d got%h wanted%h",frame_no,wordn,index,dut.transmitter.word_data,want);
   wordn=wordn+1;checks=checks+1;
  end
  if(dut.acknowledge!=prior_ack)begin
   if(dut.tx_busy)$fatal(1,"camera bank released during transmission");
   prior_ack=dut.acknowledge;
  end
 end
 task send(input integer x0);
  integer x,y,cellx,celly;
  begin
   reference(x0);wordn=0;
   if(!THROUGH_AWB&&frame_no%2==1)begin
    @(negedge cc);v=0;u=1;l=0;@(negedge cc);u=0;repeat(65)@(negedge cc);
   end
   for(y=0;y<720;y=y+1)for(x=0;x<320;x=x+1)begin
    @(negedge cc);v=1;u=(THROUGH_AWB||frame_no%2==0)&&x==0&&y==0;l=x==319;cellx=x/10;celly=y/45;
    rgb={4{(x0>=0&&cellx>=x0&&cellx<x0+3&&celly>=5&&celly<8)?24'hd8b894:24'h304050}};
    if(x%37==8)begin @(negedge cc);v=0;u=0;l=0;end
   end
   @(negedge cc);v=0;u=0;l=0;
   wait(dut.led_state==3);wait(dut.led_state==0);repeat(8)@(negedge lc);
   if(wordn!=512||status!=(frame_no<2?0:2))$fatal(1,"integrated completion words%0d status%0d",wordn,status);
   $display("CHECK integrated frame%0d object_x%0d HDMI_mode%0d",frame_no,x0,mode);frame_no=frame_no+1;
  end
 endtask
 integer i;
 initial begin
  for(i=0;i<512;i=i+1)begin energy[i]=0;hue[i]=0;expected[i]=0;end
  #73;rst=1;
  send(-1);send(-1);send(-1);send(3);send(4);mode=3;send(8);send(8);mode=4;send(-1);mode=0;send(-1);
  if(checks!=4608)$fatal(1,"integrated count");
  $display("PASS integrated: %0d RGB96-to-serial words; real_AWB=%0d, WAIT exits after warmup, coincident/early SOF, exact spatial averaging, foreground/halo/trails, speed hue, stationary retention, mode independence, both-panel serpentine GRB ordering, immutable output and bank lifetime",checks,THROUGH_AWB);$finish;
 end
 initial begin #250000000;$fatal(1,"integrated watchdog");end
endmodule
