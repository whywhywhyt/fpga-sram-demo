`timescale 1ns/1ps
module tb_paint_precision;
 reg clk=0,rst=0,tv=0,start=0,cap=0,eff=0,mv=0,toggle=0,clear=0;
 always #10 clk=~clk;
 reg [23:0] scene=24'h304050;reg [8:0] addr=0,rd=0;reg [4:0] mx=0;reg [3:0] my=0;
 wire [23:0] out;wire busy,done,down,cw;wire [8:0] ca;wire [23:0] cr;
 wire [2:0] status;wire [9:0] fg;
 wall_light_painter #(.WARMUP_FRAMES(0),.CAL_FRAMES(1)) dut(
  .clk(clk),.rst_n(rst),.tile_valid(tv),.tile_addr(addr),.tile_rgb(scene),
  .frame_start(start),.home_request(1'b0),.capture_request(cap),.effect_request(eff),
  .marker_valid(mv),.marker_x(mx),.marker_y(my),.color_request(1'b0),.brush_color(),.pen_toggle(toggle),.paint_clear(clear),
  .pen_down(down),.canvas_write(cw),.canvas_addr(ca),.canvas_rgb(cr),
  .read_addr(rd),.read_rgb(out),.busy(busy),.frame_done(done),.status(status),.foreground_count(fg));
 reg expected[0:511];integer i,j,checks=0;
 task frame;
  begin
   wait(!busy);
   for(i=0;i<512;i=i+1)begin @(negedge clk);tv=1;addr=i;end
   @(negedge clk);tv=0;start=1;@(negedge clk);start=0;wait(done);@(negedge clk);
   for(i=0;i<512;i=i+1)begin
    rd=i;@(posedge clk);#1;
    if(out!==(expected[i]?24'h042018:24'h0))$fatal(1,"paint pixel %0d got %h expected ink=%0d",i,out,expected[i]);
    checks=checks+1;@(negedge clk);
   end
  end
 endtask
 task pen;begin @(negedge clk);toggle=1;@(negedge clk);toggle=0;end endtask
 task mode_next;begin @(negedge clk);eff=1;@(negedge clk);eff=0;end endtask
 initial begin
  for(j=0;j<512;j=j+1)expected[j]=0;
  #73;rst=1;wait(!busy);frame();mode_next();mv=1;mx=2;my=3;
  frame();if(down)$fatal(1,"PAINT did not start pen-up");
  pen();expected[3*32+2]=1;frame();
  mx=3;expected[3*32+3]=1;frame(); // old one-cell/frame failure
  mx=12;for(j=3;j<=12;j=j+1)expected[3*32+j]=1;frame();
  mx=18;my=9;for(j=0;j<=6;j=j+1)expected[(3+j)*32+12+j]=1;frame();
  pen();mx=25;my=12;frame(); // move while UP: zero new pixels
  pen();expected[12*32+25]=1;frame();
  mv=0;frame();mv=1;mx=1;my=1;expected[33]=1;frame(); // loss breaks stroke
  // Large discontinuity must not draw a diagonal across the whole canvas.
  mx=30;my=14;expected[14*32+30]=1;frame();
  mx=24;my=8;for(j=0;j<=6;j=j+1)expected[(14-j)*32+30-j]=1;frame();
  mx=18;my=14;for(j=0;j<=6;j=j+1)expected[(8+j)*32+24-j]=1;frame();
  mx=12;my=8;for(j=0;j<=6;j=j+1)expected[(14-j)*32+18-j]=1;frame();
  mx=18;my=2;for(j=0;j<=6;j=j+1)expected[(8-j)*32+12+j]=1;frame();
  my=8;for(j=2;j<=8;j=j+1)expected[j*32+18]=1;frame();
  mx=12;for(j=12;j<=18;j=j+1)expected[8*32+j]=1;frame();
  // PAINT controls must remain usable even when a person changes most of
  // the background. It is marker-driven, not gated by background occupancy.
  scene=24'hffffff;mx=13;expected[8*32+13]=1;frame();
  if(status!=3)$fatal(1,"global foreground disabled PAINT controls");
  scene=24'h304050;
  @(negedge clk);clear=1;@(negedge clk);clear=0;
  for(j=0;j<512;j=j+1)expected[j]=0;
  frame();if(down)$fatal(1,"clear failed to lift pen");
  mx=4;my=4;frame();pen();expected[4*32+4]=1;frame();
  mode_next();mv=0;frame();if(status!=4)$fatal(1,"HOLD missing");
  $display("PASS paint precision: %0d exact pixels; one-cell slow steps, continuous fast/diagonal lines, pen-up reposition, loss/jump breaks, clear, hold, 32/255 peak",checks);
  $finish;
 end
 initial begin #20000000;$fatal(1,"precision watchdog");end
endmodule
