`timescale 1ns/1ps
module tb_capture;
 reg cc=0,lc=0,rst=0,v=0,u=0,l=0;
 always #4.83 cc=~cc;
 always #10 lc=~lc;
 reg [95:0] rgb=0;
 reg [8:0] rd=0;
 reg [1:0] ack=0;
 wire [23:0] a,b;
 wire [1:0] req;
 wire [15:0] pub,drop;
 wall_rgb96_capture dut(cc,lc,rst,v,u,l,rgb,rd,a,b,req,ack,pub,drop);
 integer sums[0:1535],expected0[0:511],expected1[0:511];
 integer checks=0,bank,base_pub,s;
 function integer channel(input integer x,y,id,ch);
  channel=(x*3+y*7+id*43+ch*67+(x%4)*19)%256;
 endfunction
 task send(input integer id,lines,bad_line,gaps);
  integer x,y,p,r,g,bl,t,k;
  begin
   for(k=0;k<1536;k=k+1)sums[k]=0;
   // Mix ordinary AXI SOF+valid frames with the actual AWB early-SOF contract.
   if(id%2==0)begin
    @(negedge cc);v=0;u=1;l=0;
    @(negedge cc);u=0;repeat(65)@(negedge cc);
   end
   for(y=0;y<lines;y=y+1)for(x=0;x<320;x=x+1)begin
    @(negedge cc);v=1;u=id%2==1&&x==0&&y==0;l=x==319;
    if(y==bad_line&&x==7)l=1;
    for(p=0;p<4;p=p+1)begin
     r=channel(x*4+p,y,id,0);g=channel(x*4+p,y,id,1);bl=channel(x*4+p,y,id,2);
     rgb[95-p*24-:24]={r[7:0],g[7:0],bl[7:0]};
     t=(y/45)*32+(x/10);
     sums[t*3]=sums[t*3]+r;sums[t*3+1]=sums[t*3+1]+g;sums[t*3+2]=sums[t*3+2]+bl;
    end
    if(gaps&&x%23==5)begin @(negedge cc);v=0;u=0;l=0;end
   end
   @(negedge cc);v=0;u=(id==7);l=0;
   if(id==7)begin @(negedge cc);v=0;u=0;end
   repeat(22)@(negedge cc);
  end
 endtask
 task remember(input integer which);
  integer i,r,g,bl;
  begin for(i=0;i<512;i=i+1)begin
   // Independent exact integer division. The fixed reciprocal is allowed
   // at most one LSB rounding error, checked channel by channel below.
   r=(sums[i*3]+900)/1800;g=(sums[i*3+1]+900)/1800;bl=(sums[i*3+2]+900)/1800;
   if(which==0)expected0[i]=(r<<16)|(g<<8)|bl;
   else expected1[i]=(r<<16)|(g<<8)|bl;
  end end
 endtask
 task check(input integer which);
  integer i,c,e,got,delta;reg [23:0] val;
  begin for(i=0;i<512;i=i+1)begin
   @(negedge lc);rd=i;@(posedge lc);#1;val=which?b:a;
   for(c=0;c<3;c=c+1)begin
    e=((which?expected1[i]:expected0[i])>>(c*8))&255;got=(val>>(c*8))&255;
    delta=got-e;if(delta>1||delta< -1)$fatal(1,"capture bank%0d tile%0d ch%0d=%0d expected%0d",which,i,c,got,e);
    if(^val===1'bx)$fatal(1,"capture unknown pixel");checks=checks+1;
   end
  end end
 endtask
 initial begin
  #73;rst=1;
  send(1,720,-1,1);if(pub!=1||req!=1)$fatal(1,"first publish");remember(0);check(0);
  send(2,720,-1,0);if(pub!=2||req!=3)$fatal(1,"second publish");remember(1);check(1);check(0);
  send(3,720,-1,0);if(pub!=2||drop!=1)$fatal(1,"full bank not dropped");check(0);check(1);
  ack=1;repeat(6)@(negedge cc);
  send(4,60,-1,0);if(pub!=2)$fatal(1,"truncated frame published");
  send(5,720,5,0);if(pub!=2)$fatal(1,"malformed line published");check(1);
  send(6,720,-1,1);if(pub!=3||req!=2)$fatal(1,"recovery failed");remember(0);check(0);check(1);
  // Free the other bank and place an immediate SOF after final input. It
  // must be discarded while the final averaging pipeline still owns it.
  ack=3;repeat(6)@(negedge cc);
  send(7,720,-1,0);
  repeat(30)@(negedge cc);
  if(pub!=4||drop!=2)$fatal(1,"final pipeline guard pub%0d dropped%0d",pub,drop);
  remember(1);check(1);
  rst=0;#57;rst=1;ack=0;repeat(10)@(negedge cc);
  if(req!=0||pub!=0||drop!=0)$fatal(1,"reset ownership");
  send(8,720,-1,0);remember(0);check(0);
  $display("PASS capture: %0d independent channel averages; coincident and early SOF, spatial boundaries, stalls, ownership/backpressure, truncated/malformed recovery, final-pipeline early-SOF guard, reset",checks);$finish;
 end
 initial begin #100000000;$fatal(1,"capture watchdog");end
endmodule
