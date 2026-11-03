`timescale 1ns/1ps
module tb_cartoon_routing;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,u=0,v=0,l=0;reg[95:0]data=0;reg[2:0]mode=7;
 reg[7:0]edge_threshold=96;wire ov,ou,ol;wire[95:0]out;wire[2:0]active;wire[7:0]threshold;
 image_modes_96 dut(.clk(clk),.rst_n(rst),.I_tlast(l),.I_tuser(u),.I_tvalid(v),.I_tdata(data),
  .requested_mode(mode),.requested_color(2'd2),.requested_binary_threshold(8'd112),
  .requested_edge_threshold(edge_threshold),.requested_red_threshold(8'd40),
  .O_tlast(ol),.O_tuser(ou),.O_tvalid(ov),.O_tdata(out),.active_mode(active),.active_threshold(threshold),.active_color());
 reg[95:0]rgb[0:230399],cartoon[0:230399],q[0:2];reg[2:0]vq=0,uq=0,lq=0;
 reg[2:0]mq[0:2];reg[7:0]tq[0:2];reg[95:0]expected=0;reg[2:0]expected_mode=7;reg[7:0]expected_th=96;
 integer checks=0,completed=0,f,x,y,index;
 always @(posedge clk)begin:monitor
  integer a;
  if(!rst)begin vq=0;uq=0;lq=0;for(a=0;a<3;a++)begin q[a]=0;mq[a]=3;tq[a]=96;end end
  else begin
   for(a=2;a>0;a--)begin q[a]=q[a-1];mq[a]=mq[a-1];tq[a]=tq[a-1];end
   q[0]=expected;mq[0]=expected_mode;tq[0]=expected_th;
   vq={vq[1:0],v};uq={uq[1:0],u};lq={lq[1:0],l};
  end
  #1;if(rst)begin
   if({ov,ou,ol}!=={vq[2],uq[2],lq[2]})$fatal(1,"cartoon mode stream framing");
   if(ov)begin
    if(out!==q[2])$fatal(1,"cartoon/RGB mode mux pixel mismatch group%0d mode%0d",checks,active);
    if(active!==mq[2]||threshold!==tq[2])$fatal(1,"cartoon mode/edge threshold not frame-atomic");
    checks++;
   end
  end
 end
 task idle(input integer n);begin @(negedge clk);v=0;u=0;l=0;repeat(n-1)@(negedge clk);end endtask
 initial begin
  $readmemh("full_rgb.hex",rgb);$readmemh("full_cartoon.hex",cartoon);
  idle(5);rst=1;idle(5);
  for(f=0;f<2;f++)begin
   expected_mode=f==0?7:0;expected_th=f==0?96:32;
   @(negedge clk);v=0;u=1;l=0;idle(4);index=0;
   for(y=0;y<720;y++)begin
    for(x=0;x<320;x++)begin
     @(negedge clk);v=1;u=0;l=x==319;data=rgb[index];expected=f==0?cartoon[index]:rgb[index];index++;
     if(f==0&&y==50&&x==4)begin mode=0;edge_threshold=32;end
     if(x%64==63)idle(1);
    end
    idle(8);
   end
   idle(15);
  end
  if(checks!=460800)$fatal(1,"routing coverage");
  completed=1;$display("PASS cartoon routing: 1843200 exact pixels through real image_modes, frame-atomic mode and edge threshold, midframe request, unchanged RGB and three-cycle metadata");$finish;
 end
 initial begin #20000000;$fatal(1,"cartoon routing watchdog");end
endmodule
