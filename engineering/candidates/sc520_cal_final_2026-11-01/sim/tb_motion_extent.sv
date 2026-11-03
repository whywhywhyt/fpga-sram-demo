`timescale 1ns/1ps
module tb_motion_extent;
 localparam W=160,H=80,T=8,GW=20,GH=10,N=200,AW=8;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,u=0,v=0,l=0,sof=0;reg [95:0]rgb=0;
 wire valid,visible,global_change,map_bit;wire[9:0] count;wire[5:0]x0,x1;wire[4:0]y0,y1;
 motion_region_detect_96 #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.TILE_WIDTH(T),.TILE_HEIGHT(T)) dut(
  .clk(clk),.rst_n(rst),.I_tuser(u),.I_tvalid(v),.I_tlast(l),.I_tdata(rgb),.display_sof(sof),
  .map_addr(8'd0),.map_bit(map_bit),.result_valid(valid),.moving_tiles(count),.box_visible(visible),
  .global_change(global_change),.box_x0(x0),.box_x1(x1),.box_y0(y0),.box_y1(y1));
 integer f,x,y,gx,gy,lo,hi,top,bottom,value,cycles,previous_width,previous_height,width_now,height_now;
 integer checks=0,completed=0;reg was_visible=0;
 task idle(input integer n);begin @(negedge clk);u=0;v=0;l=0;repeat(n-1)@(negedge clk);end endtask
 initial begin
  repeat(5)@(negedge clk);rst=1;idle(4);
  for(f=0;f<36;f++)begin
   lo=f<3?4:f<12?1:8;hi=f<3?7:f<12?13:9;
   top=f<3?3:f<12?1:4;bottom=f<3?5:f<12?8:5;
   for(y=0;y<H;y++)for(x=0;x<W;x+=4)begin
    @(negedge clk);u=x==0&&y==0;v=1;l=x==W-4;gx=x/T;gy=y/T;
    value=f==0||f>=27?40:(gx>=lo&&gx<=hi&&gy>=top&&gy<=bottom)?(f%2==0?120:200):40;
    rgb={4{8'(value),8'(value),8'(value)}};
    if(x==20)idle(2);
   end
   idle(5);cycles=0;
   while(!dut.pending_result&&cycles<40000)begin idle(1);cycles++;end
   if(!dut.pending_result)$fatal(1,"motion extent analysis timeout");
   @(negedge clk);sof=1;@(negedge clk);sof=0;
   if(visible)begin
    if(x0>x1||x1>=GW||y0>y1||y1>=GH)$fatal(1,"invalid/clipped motion box");
    width_now=x1-x0;height_now=y1-y0;
    if(was_visible)begin
     if(width_now-previous_width>1||previous_width-width_now>1)$fatal(1,"width jumps more than one cell frame%0d",f);
     if(height_now-previous_height>1||previous_height-height_now>1)$fatal(1,"height jumps more than one cell frame%0d",f);
     checks++;
    end
    if(f==3&&(x1-x0!=4||y1-y0!=3))$fatal(1,"large foreground instantly inflated the motion box");
    previous_width=x1-x0;previous_height=y1-y0;
   end
   if(f==2&&(!visible||x0!=4||x1!=7||y0!=3||y1!=5))$fatal(1,"initial acquisition changed");
   if(f==26&&(!visible||x1-x0!=1||y1-y0!=1))$fatal(1,"box did not settle to reduced object");
   if(f==35&&visible)$fatal(1,"size smoothing retained a stale stationary box");
   was_visible=visible;checks++;
  end
  if(checks<40)$fatal(1,"insufficient extent cases");
  completed=1;$display("PASS motion extent: real streamed samples, joined foreground growth, shrink convergence, bounded extent and image edges, initial acquisition and delayed publication; %0d checks",checks);$finish;
 end
 initial begin #30000000;$fatal(1,"motion extent watchdog");end
endmodule
