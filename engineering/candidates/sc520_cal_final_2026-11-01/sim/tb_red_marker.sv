`timescale 1ns/1ps
module tb_red_marker;
 reg cc=0,lc=0,rst=0,v=0,u=0,l=0;always #4.83 cc=~cc;always #10 lc=~lc;
 reg [95:0] rgb=0;wire good;wire [7:0] mu;wire [6:0] my;wire [4:0] gx;wire [3:0] gy;
 wall_red_marker dut(cc,lc,rst,v,u,l,rgb,good,mu,my,gx,gy);
 integer f=0;
 task send(input integer cx,cy,extra,corrupt,early);
  integer x,y,a,b;reg [23:0] color;
  begin
   if(early)begin @(negedge cc);u=1;v=0;l=0;@(negedge cc);u=0;repeat(65)@(negedge cc);end
   for(y=0;y<720;y=y+1)for(x=0;x<320;x=x+1)begin
    @(negedge cc);v=1;u=!early&&x==0&&y==0;l=(x==319)&&!(corrupt&&y==500);
    a=x-80;b=(y-200)/4;color=24'h304050;
    // saturated red outside ROI must never pull the pen toward the border.
    if(x<40 || (cx>=0 && a>=cx-4 && a<=cx+4 && y>=200 && b>=cy-4 && b<=cy+4))color=24'hd03028;
    if(extra==1 && a>=130 && a<=140 && y>=200 && b>=55 && b<=65)color=24'hd03028;
    if(extra==2 && a>=40 && a<=60 && y>=200 && b>=25 && b<=45)color=24'hd8b894;
    rgb={4{color}};
    if(x%73==20)begin @(negedge cc);v=0;u=0;l=0;end
   end
   @(negedge cc);v=0;u=0;l=0;repeat(90)@(negedge cc);repeat(10)@(negedge lc);f=f+1;
  end
 endtask
 task check(input integer x,y,cx,cy);
  if(!good || mu!=x || my!=y || gx!=cx || gy!=cy)
   $fatal(1,"marker f%0d valid%0d uv(%0d,%0d) cell(%0d,%0d) expected (%0d,%0d)/(%0d,%0d)",f,good,mu,my,gx,gy,x,y,cx,cy);
 endtask
 initial begin
  #73;rst=1;
  send(-1,0,2,0,1);if(good)$fatal(1,"skin without marker acquired as red pen");
  send(22,22,2,0,1);check(22,22,4,4);
  send(24,24,1,0,0);check(24,24,4,4); // distant second red rejected by lock
  send(25,25,0,0,1);check(25,25,4,4); // cell-boundary hysteresis
  send(26,26,0,0,0);check(26,26,5,5);
  send(50,40,0,0,1);check(50,40,10,8); // quick motion, no IIR lag
  send(-1,0,0,0,0);if(good)$fatal(1,"lost marker stayed valid");
  send(144,70,0,0,1);check(144,70,28,14); // reacquire outside former lock
  send(143,70,0,1,0);if(good)$fatal(1,"malformed frame published marker");
  send(140,70,0,0,1);check(140,70,28,14);
  repeat(5000020)@(negedge lc);if(good)$fatal(1,"camera stop left stale pen");
  $display("PASS red marker: %0d full RGB96 frames, early/coincident SOF, bubbles, ROI, independent centroid, lock, hysteresis, loss/reacquire, malformed-frame rejection, camera-stop timeout",f);$finish;
 end
 initial begin #200000000;$fatal(1,"marker watchdog");end
endmodule
