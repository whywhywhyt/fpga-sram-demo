`timescale 1ns/1ps
module tb_noise_tone;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,u=0,l=0,v=0;reg [95:0] data=0;wire ou,ol,ov;wire [95:0] out;
 axis_tone_rgb96 dut(clk,rst,l,u,v,data,ol,ou,ov,out);
 reg [203:0] vectors[0:27206-1];reg [95:0] q[0:3],expected;
 reg [3:0] vq=0,uq=0,lq=0;integer i,n,checked=0,completed=0;
 always @(posedge clk)begin
  if(!rst)begin vq=0;uq=0;lq=0;for(n=0;n<4;n++)q[n]=0;end
  else begin
   for(n=3;n>0;n--)q[n]=q[n-1];q[0]=expected;
   vq={vq[2:0],v};uq={uq[2:0],u};lq={lq[2:0],l};
  end
  #1;if(rst)begin
   if({ov,ou,ol}!=={vq[3],uq[3],lq[3]})$fatal(1,"noise stream latency");
   if(out!==q[3])$fatal(1,"noise integer output at %0d got%h expected%h",checked,out,q[3]);
   checked++;
  end
 end
 initial begin
  expected=0;$readmemh("noise_vectors.hex",vectors);
  repeat(4)@(negedge clk);rst=1;
  for(i=0;i<27206;i++)begin @(negedge clk);{u,l,v,data,expected}=vectors[i];end
  @(negedge clk);v=0;u=0;l=0;expected=0;repeat(5)@(negedge clk);
  completed=1;$display("PASS display noise: 27206 independent RGB groups, edge/black/neutral bounds, row/frame resets, invalid gaps and four-clock pipelined transport");$finish;
 end
endmodule
