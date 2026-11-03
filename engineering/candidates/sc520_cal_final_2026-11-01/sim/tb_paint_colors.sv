`timescale 1ns/1ps
module tb_paint_colors;
 reg clk=0,rst=0,tv=0,start=0,eff=0,mv=0,toggle=0,clear=0,color_req=0;
 always #10 clk=~clk;
 reg [8:0] addr=0,rd=0;reg [4:0] mx=0;reg [3:0] my=4;
 wire [23:0] out;wire busy,done,down;wire [2:0] brush,status;wire [9:0] fg;
 wall_light_painter #(.WARMUP_FRAMES(0),.CAL_FRAMES(1)) dut(
  .clk(clk),.rst_n(rst),.tile_valid(tv),.tile_addr(addr),.tile_rgb(24'h304050),
  .frame_start(start),.home_request(1'b0),.capture_request(1'b0),.effect_request(eff),
  .marker_valid(mv),.marker_x(mx),.marker_y(my),.pen_toggle(toggle),.paint_clear(clear),
  .color_request(color_req),.brush_color(brush),.pen_down(down),
  .canvas_write(),.canvas_addr(),.canvas_rgb(),.read_addr(rd),.read_rgb(out),
  .busy(busy),.frame_done(done),.status(status),.foreground_count(fg));
 reg [23:0] expected[0:511];integer i,j,c,checks=0;
 function [23:0] palette(input integer n);
  case(n)
   0:palette=24'h042018;1:palette=24'h040820;2:palette=24'h180420;
   3:palette=24'h200404;4:palette=24'h201004;5:palette=24'h042004;
  endcase
 endfunction
 task frame;
  begin
   wait(!busy);
   for(i=0;i<512;i=i+1)begin @(negedge clk);tv=1;addr=i;end
   @(negedge clk);tv=0;start=1;@(negedge clk);start=0;wait(done);@(negedge clk);
   for(i=0;i<512;i=i+1)begin
    rd=i;@(posedge clk);#1;
    if(out!==expected[i])$fatal(1,"color pixel%0d got%h wanted%h brush%0d",i,out,expected[i],brush);
    if(out[23:16]>32||out[15:8]>32||out[7:0]>32)$fatal(1,"brightness ceiling");
    checks=checks+1;@(negedge clk);
   end
  end
 endtask
 task pen;begin @(negedge clk);toggle=1;@(negedge clk);toggle=0;@(negedge clk);end endtask
 task color_next;begin @(negedge clk);color_req=1;@(negedge clk);color_req=0;@(negedge clk);end endtask
 task mode_next;begin @(negedge clk);eff=1;@(negedge clk);eff=0;@(negedge clk);end endtask
 initial begin
  for(j=0;j<512;j=j+1)expected[j]=0;
  #73;rst=1;wait(!busy);frame();color_next();if(brush!=0)$fatal(1,"LIVE changed brush");
  mode_next();mv=1;frame();
  for(c=0;c<6;c=c+1)begin
   if(c!=0)begin
    color_next();if(brush!=c||down)$fatal(1,"color change did not lift pen");
    frame(); // old colored pixels must remain byte-for-byte unchanged
   end
   mx=2+c*4;pen();expected[4*32+mx]=palette(c);frame();
   expected[4*32+mx+1]=palette(c);expected[4*32+mx+2]=palette(c);mx=mx+2;frame();
  end
  color_next();if(brush!=0||down)$fatal(1,"six-color wrap");
  mx=6;pen();expected[4*32+6]=palette(0);frame(); // recolor only the touched blue pixel
  mode_next();frame();if(status!=4)$fatal(1,"multicolor HOLD missing");
  color_next();if(brush!=0)$fatal(1,"HOLD color key changed brush");
  for(j=0;j<512;j=j+1)expected[j]=0;
  mode_next();frame();mode_next();frame();mode_next();frame();
  if(brush!=0||down)$fatal(1,"new PAINT must start cyan and UP");
  color_next();color_next();if(brush!=2)$fatal(1,"brush select");
  @(negedge clk);clear=1;@(negedge clk);clear=0;frame();
  if(brush!=2||down)$fatal(1,"clear must preserve brush and lift pen");
  $display("PASS paint colors: %0d exact pixels; six persistent colors, old-stroke preservation, thin interpolated lines, auto pen-up, wrap, local overwrite, HOLD, clear, unchanged 32/255 peak",checks);$finish;
 end
 initial begin #25000000;$fatal(1,"color painter watchdog");end
endmodule
