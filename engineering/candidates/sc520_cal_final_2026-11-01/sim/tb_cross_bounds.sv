`timescale 1ns/1ps
module tb_cross_bounds;
 parameter integer WIDTH=1280,HEIGHT=720,CASES=6;
 localparam STEP=1<<($clog2(WIDTH)-2),K0=WIDTH/2-STEP,K1=WIDTH/2,K2=WIDTH/2+STEP;
 localparam YSTEP=1<<($clog2(HEIGHT)-2),T0=HEIGHT/2-YSTEP,T1=HEIGHT/2,T2=HEIGHT/2+YSTEP;
 reg clk=0,rst=0,u=0,v=0;always #5 clk=~clk;
 wire enabled;wire[15:0]r,b;wire[159:0]diag;
 awb_spatial_calibration #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) dut(
  .clk(clk),.rst_n(rst),.user(u),.valid(v),.data(96'd0),.calibrate(1'b0),.toggle(1'b0),.clear(1'b0),
  .ratio_request(),.ratio_accept(1'b0),.sum_r(),.sum_g(),.sum_b(),.ratio_done(1'b0),.ratio_r(16'd0),.ratio_b(16'd0),
  .enabled(enabled),.pixel_r(r),.pixel_b(b),.diagnostics(diag));
 integer kr[0:4],kb[0:4];integer completed=0,checks=0,clip_low=0,clip_high=0;
 integer c,i,x,y,er,eb;
 function integer linear(input integer p,a,m,z,k0,k1,k2);
  begin
   if(p<=k0)linear=a;else if(p>=k2)linear=z;
   else if(p<=k1)linear=a+((m-a)*(p-k0)>>>$clog2(k1-k0));
   else linear=m+((z-m)*(p-k1)>>>$clog2(k2-k1));
  end
 endfunction
 function integer expected(input integer xx,yy,input bit blue);
  integer h,vertical,total;
  begin
   if(blue)begin
    h=linear(xx,kb[0],kb[1],kb[2],K0,K1,K2);
    vertical=linear(yy,kb[3],kb[1],kb[4],T0,T1,T2)-kb[1];
   end else begin
    h=linear(xx,kr[0],kr[1],kr[2],K0,K1,K2);
    vertical=linear(yy,kr[3],kr[1],kr[4],T0,T1,T2)-kr[1];
   end
   total=h+vertical;expected=total<2048?2048:total>10240?10240:total;
  end
 endfunction
 task tick(input integer xx,yy,input bit su);
  begin
   @(negedge clk);u=su;v=1;#1;
   er=expected(xx,yy,0);eb=expected(xx,yy,1);
   if(r!==er[15:0]||b!==eb[15:0])$fatal(1,"2D gain case%0d x%0d y%0d got%0d,%0d expected%0d,%0d",c,xx,yy,r,b,er,eb);
   if(r<2048||r>10240||b<2048||b>10240)$fatal(1,"gain outside bounded range");
   if(r==2048||b==2048)clip_low++;
   if(r==10240||b==10240)clip_high++;
   checks++;@(posedge clk);#1;
  end
 endtask
 initial begin
  repeat(4)@(negedge clk);rst=1;
  for(c=0;c<CASES;c++)begin
   @(negedge clk);u=0;v=0;
   for(i=0;i<5;i++)begin
    if(CASES==32)begin kr[i]=(c&(1<<i))?10240:2048;kb[i]=12288-kr[i];end
    else if(c==0)begin kr[i]=4096;kb[i]=4096;end
    else if(c==1)begin kr[i]=i==1?10240:2048;kb[i]=12288-kr[i];end
    else if(c==2)begin kr[i]=i==1?2048:10240;kb[i]=12288-kr[i];end
    else begin kr[i]=2048+(c*733+i*1511)%8193;kb[i]=2048+(c*313+i*1777)%8193;end
    dut.knots_r[i]=kr[i];dut.knots_b[i]=kb[i];
   end
   dut.table_valid=1;
   if(c%2)begin u=1;@(posedge clk);#1;end
   for(y=0;y<HEIGHT;y++)for(x=0;x<WIDTH;x+=4)begin
    tick(x,y,c%2==0 && x==0 && y==0);
    if((x/4+y)%67==13)begin @(negedge clk);u=0;v=0;@(posedge clk);#1;end
   end
  end
  @(negedge clk);u=0;v=0;rst=0;@(posedge clk);#1;
  if(enabled!==0 || r!==4096 || b!==4096)$fatal(1,"reset gain identity");
  if(checks!=CASES*(WIDTH/4)*HEIGHT||clip_low==0||clip_high==0)$fatal(1,"incomplete spatial bound coverage");
  completed=1;$display("PASS cross bounds: %0d exact gains at %0dx%0d, independent closed-form 2D reference, negative offsets, both saturation limits, line/SOF/valid gaps, identity reset",checks,WIDTH,HEIGHT);$finish;
 end
 initial begin #200000000;$fatal(1,"bounds watchdog");end
endmodule
