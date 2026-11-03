`timescale 1ns/1ps
module tb_spatial_calibration;
 reg clk=0,rst=0,u=0,v=0,l=0,cap=0,tog=0,clear=0;
 reg[95:0]data=0;
 wire[95:0]od;wire ov,ou,ol;wire[159:0]diag;
 always #5 clk=~clk;
 awb #(.IMG_WIDTH(128),.IMG_HEIGHT(32)) dut(.I_clk(clk),.I_rst_n(rst),.I_tuser(u),.I_tvalid(v),.I_tlast(l),
  .I_tdata(data),.O_tready(1'b1),.I_tready(),.O_tdata(od),.O_tvalid(ov),.O_tuser(ou),.O_tlast(ol),
  .I_calibrate(cap),.I_cal_toggle(tog),.I_cal_clear(clear),.O_diagnostics(),.O_spatial_diag(diag));
 integer completed=0;
 integer cycle=0,checks=0,groups=0,ax=0,ay=0,rr,bb,idx,j,f,x,y,lane,kind;
 integer sr[0:2],sg[0:2],sb[0:2],nn[0:2],gr[0:2],gb[0:2];
 reg gv[0:127],gl[0:127];reg[95:0]gd[0:127];reg[95:0]expected;
 integer r,g,b;reg[23:0]p;reg[95:0]word;
 function integer coeff(input integer xx,a,m,z);
  if(xx<=32)coeff=a;else if(xx>=96)coeff=z;
  else if(xx<=64)coeff=a+((m-a)*(xx-32)>>>5);
  else coeff=m+((z-m)*(xx-64)>>>5);
 endfunction
 function[23:0] pixel(input integer xx,yy,which);
  integer pr,pg,pb;
  begin
   pg=100;
   pr=xx<=32?128:xx>=96?96:xx<=64?128-(48*(xx-32)/32):80+16*(xx-64)/32;
   pb=xx<=32?96:xx>=96?128:xx<=64?96-(24*(xx-32)/32):72+56*(xx-64)/32;
   case(which)
    1:begin pr=0;pg=0;pb=0;end
    2:begin pr=200;pg=10;pb=10;end
    3:begin pr=250;pg=250;pb=250;end
    4:if(xx<40)begin pr=230;pg=12;pb=5;end
    5:begin pr=47;pg=47;pb=47;end
    6:begin pr=(xx*37+yy*53)%256;pg=(xx*17+yy*11)%256;pb=(xx*7+yy*31)%256;end
   endcase
   pixel={pr[7:0],pg[7:0],pb[7:0]};
  end
 endfunction
 task tick(input bit su,sv,sl,input[95:0]d);
  begin
   @(negedge clk);u=su;v=sv;l=sl;data=d;#1;
   if(su)begin ax=0;ay=0;for(j=0;j<128;j=j+1)begin gv[j]=0;gl[j]=0;gd[j]=0;end end
   if(dut.cal_enabled)begin
    rr=coeff(ax,gr[0],gr[1],gr[2]);bb=coeff(ax,gb[0],gb[1],gb[2]);
    if(dut.spatial_r!==rr[15:0] || dut.spatial_b!==bb[15:0])
     $fatal(1,"spatial interpolation x%0d y%0d got %0d,%0d want %0d,%0d",ax,ay,dut.spatial_r,dut.spatial_b,rr,bb);
    checks=checks+1;
   end else begin rr=dut.use_r;bb=dut.use_b;end
   expected=0;
   for(lane=0;lane<4;lane=lane+1)begin
    p=d[95-lane*24-:24];r=p[23:16]*rr/4096;g=p[15:8];b=p[7:0]*bb/4096;
    expected[95-lane*24-:24]={(r>255?8'd255:r[7:0]),g[7:0],(b>255?8'd255:b[7:0])};
   end
   if(sv)begin
    idx=(cycle+64)%128;gv[idx]=1;gl[idx]=sl;gd[idx]=expected;
    ax=ax==124?0:ax+4;if(ax==0)ay=ay+1;
   end
   @(posedge clk);#1;idx=cycle%128;
   if(ou!==su || ov!==gv[idx] || ol!==(gv[idx] && gl[idx]) || od!==(gv[idx]?gd[idx]:96'd0))
    $fatal(1,"64-clock RGB transport cycle%0d v%0b/%0b got%h want%h",cycle,ov,gv[idx],od,gd[idx]);
   if(ov)groups=groups+1;
   gv[idx]=0;gl[idx]=0;gd[idx]=0;cycle=cycle+1;
  end
 endtask
 task idle(input integer n);integer k;begin for(k=0;k<n;k=k+1)tick(0,0,0,0);end endtask
 task frame(input integer which,input bit sof_pixel);
  integer xx,yy,ln;reg[95:0]w;
  begin
   if(!sof_pixel)tick(1,0,0,0);
   for(yy=0;yy<32;yy=yy+1)for(xx=0;xx<128;xx=xx+4)begin
    for(ln=0;ln<4;ln=ln+1)w[95-ln*24-:24]=pixel(xx+ln,yy,which);
    tick(sof_pixel && xx==0 && yy==0,1,xx==124,w);
    if((xx/4+yy)%11==5)tick(0,0,0,96'hffffffffffffffffffffffff);
   end
   idle(360);
  end
 endtask
 task request;
  begin cap=1;tick(0,0,0,0);cap=0;tick(0,0,0,0);end
 endtask
 task reject_field(input integer which);
  begin
   request();for(f=0;f<5;f=f+1)frame(which,f%2);idle(300);
   if(!dut.spatial.failed || !dut.spatial.table_valid || !dut.cal_enabled || diag[159:152]!=1)
    $fatal(1,"invalid field did not preserve previous calibration, kind%0d diag%h",which,diag);
   for(j=0;j<3;j=j+1)if(dut.spatial.knots_r[j]!==gr[j][15:0] || dut.spatial.knots_b[j]!==gb[j][15:0])
    $fatal(1,"invalid field mutated active knots");
  end
 endtask
 initial begin
  for(j=0;j<128;j=j+1)begin gv[j]=0;gl[j]=0;gd[j]=0;end
  for(j=0;j<3;j=j+1)begin sr[j]=0;sg[j]=0;sb[j]=0;nn[j]=0;gr[j]=4096;gb[j]=4096;end
  // Reference sums are computed from generated input pixels, with direct
  // integer division; no reference to the implementation's accumulators/DDA.
  for(y=4;y<28;y=y+4)for(x=0;x<128;x=x+4)
   if((x>=28&&x<36)||(x>=60&&x<68)||(x>=92&&x<100))begin
    idx=x<60?0:x<92?1:2;p=pixel(x,y,0);
    sr[idx]+=4*p[23:16];sg[idx]+=4*p[15:8];sb[idx]+=4*p[7:0];nn[idx]+=4;
   end
  for(j=0;j<3;j=j+1)begin gr[j]=sg[j]*4096/sr[j];gb[j]=sg[j]*4096/sb[j];end
  repeat(4)@(negedge clk);rst=1;
  frame(0,0);if(diag!==160'd0)$fatal(1,"unsolicited calibration");
  request();for(f=0;f<5;f=f+1)frame(0,f%2);idle(400);
  if(!dut.spatial.publish || dut.cal_enabled)$fatal(1,"new knots published without SOF");
  for(j=0;j<3;j=j+1)begin
   if(dut.spatial.counts[j]!==nn[j][15:0] || dut.spatial.reds[j]!==sr[j][27:0] ||
      dut.spatial.greens[j]!==sg[j][27:0] || dut.spatial.blues[j]!==sb[j][27:0] ||
      dut.spatial.pending_r[j]!==gr[j][15:0] || dut.spatial.pending_b[j]!==gb[j][15:0])
    $fatal(1,"reference sum/count/ratio mismatch zone%0d got n%0d R%0d B%0d want n%0d R%0d B%0d",j,dut.spatial.counts[j],dut.spatial.pending_r[j],dut.spatial.pending_b[j],nn[j],gr[j],gb[j]);
  end
  frame(6,1);if(!dut.cal_enabled || diag[2:0]!=3 || diag[159:152]!=1)$fatal(1,"calibration not atomic ON");
  // Four independent input lanes, saturation, valid bubbles and both SOF styles.
  frame(6,0);frame(0,1);
  tog=1;tick(0,0,0,0);tog=0;idle(10);if(!dut.cal_enabled)$fatal(1,"toggle mid-frame");
  frame(6,1);if(dut.cal_enabled || diag[2:0]!=4)$fatal(1,"toggle OFF failed");
  tog=1;tick(0,0,0,0);tog=0;frame(6,0);if(!dut.cal_enabled)$fatal(1,"toggle ON failed");
  reject_field(1);reject_field(2);reject_field(3);reject_field(4);reject_field(5);
  // Interrupted capture must not accept mixed frame fragments.
  request();frame(0,0);frame(0,0);tick(1,0,0,0);
  tick(0,1,0,{4{24'h808080}});tick(1,0,0,0);idle(20);
  if(!dut.spatial.failed || !dut.spatial.table_valid)$fatal(1,"truncated frame not rejected");
  clear=1;tick(0,0,0,0);clear=0;idle(4);
  if(!dut.cal_enabled)$fatal(1,"clear before SOF");frame(0,1);
  if(dut.cal_enabled || dut.spatial.table_valid || diag!==0)$fatal(1,"clear failed");
  request();frame(0,0);@(negedge clk);rst=0;repeat(4)@(negedge clk);rst=1;
  if(dut.cal_enabled || dut.spatial.table_valid)$fatal(1,"reset retained correction");
  $display("PASS spatial calibration: independent raw RGB sums/ratios, four white frames, SOF atomic publication, continuous DDA all x, %0d checked cycles and %0d RGB groups, 64-clock four-lane transport, five rejected fields, keep old table, truncation, toggle/clear/reset",checks,groups);
  completed=1;$finish;
 end
 initial begin #10000000;$fatal(1,"spatial calibration watchdog");end
endmodule
