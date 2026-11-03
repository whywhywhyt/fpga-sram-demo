`timescale 1ns/1ps
module tb_spatial_720p;
 reg clk=0,rst=0,u=0,v=0,cap=0;reg[95:0]data=0;
 always #5 clk=~clk;
 wire request,busy,done,en;wire[27:0]r,g,b;wire[15:0]rr,bb,pr,pb;wire[159:0]diag;
 awb_spatial_calibration dut(.clk(clk),.rst_n(rst),.user(u),.valid(v),.data(data),
 .calibrate(cap),.toggle(1'b0),.clear(1'b0),.ratio_request(request),.ratio_accept(request&&!busy),
 .sum_r(r),.sum_g(g),.sum_b(b),.ratio_done(done),.ratio_r(rr),.ratio_b(bb),
 .enabled(en),.pixel_r(pr),.pixel_b(pb),.diagnostics(diag));
 awb_serial_ratio div(.clk(clk),.rst_n(rst),.start(request&&!busy),.sum_r(r),.sum_g(g),.sum_b(b),
 .busy(busy),.done(done),.gain_r(rr),.gain_b(bb));
 integer completed=0;
 integer f,x,y,k,z,sr[0:2],sg[0:2],sb[0:2],nn[0:2],kr[0:2],kb[0:2];
 integer er,eb,checks=0,guard=0;reg[23:0]p;
 function[23:0] field(input integer xx,yy);
  integer red,blue,green;
  begin
   red=xx<=128?128:xx>=1152?96:xx<=640?128-(48*(xx-128)/512):80+16*(xx-640)/512;
   blue=xx<=128?96:xx>=1152?128:xx<=640?96-(24*(xx-128)/512):72+56*(xx-640)/512;
   green=100+(yy%3)-1;field={red[7:0],green[7:0],blue[7:0]};
  end
 endfunction
 function integer interpolated(input integer xx,a,m,z);
  if(xx<=128)interpolated=a;else if(xx>=1152)interpolated=z;
  else if(xx<=640)interpolated=a+((m-a)*(xx-128)>>>9);
  else interpolated=m+((z-m)*(xx-640)>>>9);
 endfunction
 initial begin
  for(k=0;k<3;k++)begin sr[k]=0;sg[k]=0;sb[k]=0;nn[k]=0;kr[k]=4096;kb[k]=4096;end
  // Constants below are independently enumerated sampling rectangles, not DUT
  // parameters. This guards the actual 720p sample count and 512-pixel spans.
  for(y=92;y<=628;y+=4)for(x=0;x<1280;x+=16)
   if((x>=64&&x<=176)||(x>=576&&x<=688)||(x>=1088&&x<=1200))begin
    z=x<576?0:x<1088?1:2;p=field(x,y);
    sr[z]+=4*p[23:16];sg[z]+=4*p[15:8];sb[z]+=4*p[7:0];nn[z]+=4;
   end
  for(k=0;k<3;k++)begin
   kr[k]=sg[k]*4096/sr[k];kb[k]=sg[k]*4096/sb[k];
   if(nn[k]!=4320)$fatal(1,"golden sample count");
  end
  repeat(4)@(negedge clk);rst=1;cap=1;@(negedge clk);cap=0;
  for(f=0;f<7;f++)begin
   @(negedge clk);u=1;v=0;
   @(negedge clk);u=0;
   for(y=0;y<720;y++)for(x=0;x<1280;x+=4)begin
    p=field(x,y);data={4{p}};v=1;#1;
    if(f>=5)begin
     er=interpolated(x,kr[0],kr[1],kr[2]);eb=interpolated(x,kb[0],kb[1],kb[2]);
     if(!en || pr!==er[15:0] || pb!==eb[15:0])
      $fatal(1,"720p coefficient f%0d x%0d y%0d actual%0d,%0d expected%0d,%0d",f,x,y,pr,pb,er,eb);
     checks++;
    end
    @(negedge clk);
    if((x/4+y)%97==6)begin v=0;repeat(2)@(negedge clk);end
   end
   v=0;repeat(400)@(negedge clk);
   if(f==4)begin
    if(!dut.publish || en)$fatal(1,"720p early/absent publication");
    for(k=0;k<3;k++)if(dut.reds[k]!==sr[k][27:0] || dut.greens[k]!==sg[k][27:0] ||
       dut.blues[k]!==sb[k][27:0] || dut.counts[k]!==nn[k][15:0])$fatal(1,"720p statistics zone%0d",k);
   end
  end
  if(checks!=460800)$fatal(1,"720p coverage");
  $display("PASS spatial 720p: 4320 real samples per zone, full four-frame raw RGB sums, two corrected complete frames / 460800 interpolation groups, line boundaries and bubbles");completed=1;$finish;
 end
 initial begin #25000000;$fatal(1,"720p calibration watchdog");end
endmodule
