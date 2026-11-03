`timescale 1ns/1ps
module tb_transport;
 reg clk=0,rst=0,start=0,wv=0;always #10 clk=~clk;
 reg [23:0] wd=0;wire ready,data,busy,done;
 wall_ws2812_tx dut(clk,rst,start,wd,wv,ready,data,busy,done);
 integer p,bitn,tick,ones=0,zeros=0;
 reg [23:0] w;
 function [23:0] pattern(input integer i);pattern=(24'h123457*i)^24'h59a56d;endfunction
 initial begin
  #73;rst=1;
  wait(!busy);@(negedge clk);start=1;@(negedge clk);start=0;
  for(p=0;p<512;p=p+1)begin
   wait(ready);@(negedge clk);w=pattern(p);wd=w;wv=1;
   @(posedge clk);#1;
   @(negedge clk);wv=0;
   // The first high half-cycle was already emitted immediately after the
   // acceptance edge. Check the complete 63-clock slot at each posedge+1.
   for(bitn=23;bitn>=0;bitn=bitn-1)begin
    for(tick=0;tick<63;tick=tick+1)begin
     if(data!==(tick<(w[bitn]?40:20)))$fatal(1,"pulse p%0d b%0d tick%0d data%0d",p,bitn,tick,data);
     if(tick!=62||bitn!=0)begin @(posedge clk);#1;end
    end
    if(w[bitn])ones=ones+1;else zeros=zeros+1;
   end
   @(posedge clk);#1;if(data)$fatal(1,"fetch/latch high");
  end
  for(tick=0;tick<15000;tick=tick+1)begin
   if(data)$fatal(1,"reset high");
   if(done)$fatal(1,"short reset");@(posedge clk);#1;
  end
  if(!done||busy)$fatal(1,"latch completion");
  $display("PASS transport: 512 GRB words, %0d one / %0d zero pulses, exact 20/40 high of 63 ticks, 15000-tick latch; physical keys are covered by unified-key suites",ones,zeros);$finish;
 end
 initial begin #30000000;$fatal(1,"transport watchdog");end
endmodule
