`timescale 1ns/1ps
module tb_paint_overlay;
 reg lc=0,hc=0,rst=0,w=0,fd=0,de=0,user=0,last=0;
 always #10 lc=~lc;always #6.667 hc=~hc;
 reg [8:0] addr=0;reg [23:0] wrgb=0;
 reg [2:0] status=3;reg mv=1,down=1;reg [7:0] mu=40;reg [6:0] my=70;
 wire [23:0] out;
 wall_paint_overlay dut(lc,hc,rst,w,addr,wrgb,fd,status,mv,down,mu,my,
                         de,user,last,24'h123456,out,3'd2);
 integer i,x,y,pass=0,checks=0;
 function ink(input integer n,which);
  ink=which?((n%32)==(n/32)):((n%32)==7 || (n/32)==12);
 endfunction
 function [23:0] led_color(input integer n);
  case(n%6)
   0:led_color=24'h042018;1:led_color=24'h040820;2:led_color=24'h180420;
   3:led_color=24'h200404;4:led_color=24'h201004;5:led_color=24'h042004;
  endcase
 endfunction
 function [23:0] hdmi_color(input integer n);
  case(n%6)
   0:hdmi_color=24'h20d8e0;1:hdmi_color=24'h4060ff;2:hdmi_color=24'hb030ff;
   3:hdmi_color=24'hff3030;4:hdmi_color=24'hff9020;5:hdmi_color=24'h30e050;
  endcase
 endfunction
 task write_frame(input integer which);
  begin
   for(i=0;i<512;i=i+1)begin @(negedge lc);w=1;addr=i;wrgb=ink(i,which)?led_color(i):0;end
   @(negedge lc);w=0;fd=1;@(negedge lc);fd=0;repeat(10)@(negedge lc);
  end
 endtask
 task raster(input integer which);
  reg [23:0] want;integer index,dx,dy,slot,sx;
  begin
   // Early SOF: matches the framing used by the HDMI mixer.
   @(negedge hc);user=1;de=0;last=0;@(negedge hc);user=0;
   repeat(4)@(negedge hc);
   for(y=0;y<720;y=y+1)begin
    for(x=0;x<1280;x=x+1)begin
     de=1;last=x==1279;#1;want=24'h123456;
     dx=x-480;if(dx<0)dx=-dx;dy=y-480;if(dy<0)dy=-dy;
     if((dx<=10&&dy<=1)||(dx<=1&&dy<=10))want=24'h20ffff;
     else if((x>=320&&x<960&&(y==200||y==519)) || (y>=200&&y<520&&(x==320||x==959)))want=24'h608090;
     else if(x>=991&&x<=1248&&y>=511&&y<=640&&(x==991||x==1248||y==511||y==640))want=24'h80a0b0;
     else if(x>=992&&x<1008&&y>=488&&y<504)want=24'h20ffff;
     else if(x>=1024&&x<1216&&y>=488&&y<504)begin
      slot=(x-1024)/32;sx=(x-1024)%32;want=24'h081020;
      if(slot==2&&sx<28&&(sx==0||sx==27||y==488||y==503))want=24'hffffff;
      else if(sx>=2&&sx<26&&y>=490&&y<502)want=hdmi_color(slot);
     end
     else if(x>=992&&x<1248&&y>=512&&y<640)begin
      index=((y-512)/8)*32+(x-992)/8;want=ink(index,which)?hdmi_color(index):24'h030608;
     end
     if(out!==want)$fatal(1,"preview raster%0d xy%0d,%0d got%h want%h",which,x,y,out,want);
     checks=checks+1;@(negedge hc);
    end
    de=0;last=0;repeat(3)@(negedge hc);
   end
   de=0;pass=pass+1;
  end
 endtask
 initial begin
  #73;rst=1;write_frame(0);
  if(dut.have_frame)$fatal(1,"metadata changed outside SOF");
  raster(0);repeat(10)@(negedge lc);write_frame(1);
  if(dut.read_bank!==1)$fatal(1,"display bank changed before SOF");
  raster(1);
  $display("PASS paint overlay: %0d full rasters / %0d pixel checks, ROI/cursor alignment, 32x16 preview address and 8x8 replication, atomic metadata, bank swap only at SOF",pass,checks);$finish;
 end
 initial begin #100000000;$fatal(1,"preview watchdog");end
endmodule
