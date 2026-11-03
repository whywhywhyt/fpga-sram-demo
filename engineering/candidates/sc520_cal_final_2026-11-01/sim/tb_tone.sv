`timescale 1ns/1ps
module tb_tone;
 reg clk=0,rst=0,v=0,u=0,l=0; always #5 clk=~clk;
 reg [95:0] data=0;
 wire [95:0] out,bypass;wire ov,ou,ol,bv,bu,bl;
 axis_tone_rgb96 #(.DENOISE(0)) dut(clk,rst,l,u,v,data,ol,ou,ov,out);
 axis_tone_rgb96 #(.ENABLE(0),.DENOISE(0)) reference_delay(clk,rst,l,u,v,data,bl,bu,bv,bypass);
 integer completed=0,checks=0,cycle=0,index,lane,prior_peak=-1;
 reg [95:0] expect_rgb[0:3],expect_raw[0:3];
 reg [3:0] validq=0,userq=0,lastq=0;
 function automatic [23:0] ref_pixel(input [23:0] p);
  integer r,g,b,peak,s;
  begin
   r=p[23:16];g=p[15:8];b=p[7:0];peak=r>g?r:g;if(b>peak)peak=b;
   // Mathematical common gain, independently in full integer arithmetic.
   if(peak<=8)s=0;else if(peak<48)s=4*(peak-8);else if(peak<74)s=160;else s=(7*(255-peak)+7)/8;
   r=(r*(256+s)+128)/256;g=(g*(256+s)+128)/256;b=(b*(256+s)+128)/256;
   if(r>255||g>255||b>255)$fatal(1,"reference peak clipping");
   ref_pixel={8'(r),8'(g),8'(b)};
  end
 endfunction
 always @(posedge clk)begin:scoreboard
  integer j;reg[23:0]p,q;integer rp,gp,bp,rq,gq,bq;
  if(!rst)begin
   validq=0;userq=0;lastq=0;for(j=0;j<4;j++)begin expect_rgb[j]=0;expect_raw[j]=0;end
  end else begin
   for(j=3;j>0;j--)begin expect_rgb[j]=expect_rgb[j-1];expect_raw[j]=expect_raw[j-1];end
   for(j=0;j<4;j++)expect_rgb[0][j*24+:24]=ref_pixel(data[j*24+:24]);
   expect_raw[0]=data;validq={validq[2:0],v};userq={userq[2:0],u};lastq={lastq[2:0],l};
  end
  #1;
  if(!rst)begin if({ov,ou,ol,out}!==0)$fatal(1,"reset output");end
  else begin
   if({ov,ou,ol}!=={validq[3],userq[3],lastq[3]})$fatal(1,"tone framing not exactly 4 cycles");
   if({bv,bu,bl}!=={ov,ou,ol})$fatal(1,"bypass framing");
   if(ov)begin
    if(out!==expect_rgb[3] || bypass!==expect_raw[3])$fatal(1,"tone mismatch at check %0d raw=%h got=%h expected=%h",checks,expect_raw[3],out,expect_rgb[3]);
    for(j=0;j<4;j++)begin
     p=expect_raw[3][j*24+:24];q=out[j*24+:24];rp=p[23:16];gp=p[15:8];bp=p[7:0];rq=q[23:16];gq=q[15:8];bq=q[7:0];
     if(rq<rp||gq<gp||bq<bp)$fatal(1,"a channel darkened");
     if(rp==gp && gp==bp && !(rq==gq && gq==bq))$fatal(1,"neutral acquired tint");
     if((rp>gp && rq<gq)||(rp>bp && rq<bq)||(gp>bp && gq<bq))$fatal(1,"channel ordering reversed");
     if(rq*8>rp*13+4 || gq*8>gp*13+4 || bq*8>bp*13+4)$fatal(1,"gain cap exceeded");
    end
    checks++;
   end else if(out!==0 || bypass!==0)$fatal(1,"invalid output not zero");
  end
 end
 task bubble;begin @(negedge clk);v=0;u=0;l=0;end endtask
 initial begin
  repeat(4)@(negedge clk);rst=1;
  // Every RGB888 input exactly once, four distinct lanes per clock.
  for(index=0;index<16777216;index+=4)begin
   @(negedge clk);v=1;u=index%4096==0;l=index%320==316;
   for(lane=0;lane<4;lane++)data[lane*24+:24]=24'(index+lane);
   if(index%1024==1020)bubble();
  end
  bubble();repeat(6)@(negedge clk);
  if(checks!=4194304)$fatal(1,"incomplete exhaustive coverage %0d",checks);
  // Exercise reset while occupied and SOF without a valid pixel.
  v=1;data={4{24'h20a034}};repeat(2)@(negedge clk);rst=0;repeat(3)@(negedge clk);rst=1;
  u=1;v=0;@(negedge clk);u=0;repeat(65)@(negedge clk);v=1;l=1;data={4{24'h405080}};
  bubble();repeat(6)@(negedge clk);
  completed=1;
  $display("PASS tone exhaustive: 16777216 RGB values, all four lanes, common gain bounds, neutral preservation, channel order, bubbles, reset, early SOF and EOL");
  $finish;
 end
endmodule
