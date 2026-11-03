`timescale 1ns/1ps
// Production four-pixel status raster followed by actual single-pixel HDMI
// overlays. This catches the CAL/latency occlusion missed by isolated tests.
module tb_spatial_composite;
 reg clk=0,rst=0;always #5 clk=~clk;
 reg sv=0,su=0;reg[159:0]diag=0;wire ov,ou,ol;wire[95:0]rgb;
 frame_status_96 fs(.clk(clk),.rst_n(rst),.I_tlast(1'b0),.I_tuser(su),.I_tvalid(sv),
 .I_tdata({4{24'h234567}}),.I_mode(3'd0),.I_threshold(8'd96),.I_awb_diag(173'd0),
 .I_spatial_diag(diag),.O_tlast(ol),.O_tuser(ou),.O_tvalid(ov),.O_tdata(rgb));
 reg[23:0]memory[0:921599];integer written=0,j;
 always @(posedge clk)begin #1;if(ov)begin
  for(j=0;j<4;j++)memory[written+j]=rgb[95-j*24-:24];
  written=written+4;
 end end
 reg de=0,user=0,last=0;reg[23:0]pixel=0;wire[23:0]lat,wall,paint,final_rgb;
 wire final_de;reg publish=0;reg[2:0]wall_mode=2;
 latency_panel lp(.clk(clk),.rst_n(rst),.de(de),.user(user),.last(last),.pixel(pixel),
 .sample_done(1'b0),.sample_valid(1'b0),.latency_ticks(24'd500),.displayed_id(16'h1234),
 .repeat_count(16'd0),.repeated(1'b0),.out_pixel(lat));
 wall_status_panel ws(.clk(clk),.rst_n(rst),.de(de),.user(user),.last(last),
 .status_async(wall_mode),.pixel(lat),.out_pixel(wall));
 wall_paint_overlay wp(.led_clk(clk),.hdmi_clk(clk),.rst_n(rst),.write_valid(1'b0),
 .write_addr(9'd0),.write_rgb(24'd0),.frame_done(publish),.wall_status(wall_mode),
 .marker_valid(1'b1),.pen_down(1'b0),.marker_u(8'd64),.marker_v(7'd32),
 .de(de),.user(user),.last(last),.pixel(wall),.out_pixel(paint),.brush_color(3'd0));
 video_osd logo(.clk(clk),.rst_n(rst),.vsync(1'b0),.hsync(1'b0),.de(de),.user(user),
 .last(last),.pixel(paint),.out_vsync(),.out_hsync(),.out_de(final_de),.out_pixel(final_rgb));
 integer n=0,x,y,f,index=0,xx,yy,checked=0,ink=0,latency_checks=0,paint_checks=0;
 reg scoring=0;reg completed=0;
 always @(posedge clk)begin #2;if(scoring && final_de)begin
  xx=index%1280;yy=index/1280;
  if(xx>=16 && xx<528 && yy>=600 && yy<664)begin
   if(final_rgb!==memory[index])$fatal(1,"CAL hidden/corrupted by HDMI overlays frame%0d x%0d y%0d %h/%h",f,xx,yy,final_rgb,memory[index]);
   checked++;
   if(final_rgb==24'h00e6ff)ink++;
  end
  if(xx==944 && yy==16)begin
   if(final_rgb!==24'h101820)$fatal(1,"latency panel was damaged");
   latency_checks++;
  end
  if(f%2==1 && xx==320 && yy==200)begin
   if(final_rgb!==24'h608090)$fatal(1,"painting ROI not enabled/visible");
   paint_checks++;
  end
  index++;
 end end
 initial begin
  repeat(4)@(negedge clk);rst=1;
  for(f=0;f<5;f++)begin
   written=0;diag={8'h01,16'h10e0,16'h10e0,16'h10e0,16'h1200,16'h1100,16'h1400,16'h1300,16'h1000,16'h0f00,5'd0,3'(f+1)};
   for(n=0;n<230400;n++)begin
    @(negedge clk);sv=1;su=n==0;
   end
   @(negedge clk);sv=0;su=0;repeat(4)@(negedge clk);
   if(written!=921600)$fatal(1,"incomplete status framebuffer %0d",written);
   wall_mode=f%2==1?3:2;publish=1;@(negedge clk);publish=0;
   repeat(10)@(negedge clk);
   scoring=1;index=0;ink=0;
   for(n=0;n<921600;n++)begin
    de=1;user=n==0;last=n%1280==1279;pixel=memory[n];@(negedge clk);
   end
   de=0;user=0;last=0;repeat(4)@(negedge clk);
   if(index!=921600 || ink<100)$fatal(1,"CAL final output missing %0d pixels, ink=%0d",index,ink);
   scoring=0;
  end
  if(checked!=163840 || latency_checks!=5 || paint_checks!=2)$fatal(1,"coverage incomplete");
  completed=1;
  $display("PASS spatial composite: five CAL states, 163840 exact final pixels after latency/wall/paint/Logo overlays; latency and drawing ROI retained");
  $finish;
 end
 initial begin #80000000;$fatal(1,"composite watchdog");end
endmodule
