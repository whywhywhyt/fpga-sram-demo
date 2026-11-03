`timescale 1ns/1ps
module tb_spatial_probe;
 reg clk=0,rst=0,v=0,u=0,l=0;
 always #5 clk=~clk;
 reg [95:0] data=0;
 reg [172:0] ds=0;
 reg [23:0] reference_in=0;
 reg reference_on=0;
 wire [95:0] od,bd;
 wire ov,ou,ol,bv,bu,bl;
 frame_status_96 dut(.clk(clk),.rst_n(rst),.I_tlast(l),.I_tuser(u),
  .I_tvalid(v),.I_tdata(data),.I_mode(3'd0),.I_threshold(8'd96),
  .I_awb_diag(ds),.O_tlast(ol),.O_tuser(ou),.O_tvalid(ov),.O_tdata(od));
 frame_status_baseline baseline(.clk(clk),.rst_n(rst),.I_tlast(l),.I_tuser(u),
  .I_tvalid(v),.I_tdata(data),.I_mode(3'd0),.I_threshold(8'd96),
  .I_awb_diag(ds),.O_tlast(bl),.O_tuser(bu),.O_tvalid(bv),.O_tdata(bd));
 reg previous_v=0,previous_reference=0;
 reg [23:0] previous_rgb=0;
 integer checks=0,neutral_checks=0,unchanged_checks=0,frame,x,y,lane;
 always @(posedge clk) begin
  #1;
  if(rst)begin
   if({ov,ou,ol}!=={bv,bu,bl})$fatal(1,"transport differs from recovery version");
   if(ov!==previous_v)$fatal(1,"two-stage valid latency changed");
   if(ov)begin
    if(previous_reference)begin
     if(od!=={4{previous_rgb}})$fatal(1,"neutral reference differs: %h expected %h",od,previous_rgb);
     neutral_checks=neutral_checks+1;
    end else begin
     if(od!==bd)$fatal(1,"pixel outside reference strips changed");
     unchanged_checks=unchanged_checks+1;
    end
    checks=checks+1;
   end else if(od!==96'd0)$fatal(1,"invalid output is not black");
   previous_v=v;previous_reference=reference_on;previous_rgb=reference_in;
  end else begin previous_v=0;previous_reference=0;previous_rgb=0;end
 end
 task bubble;
  begin @(negedge clk);v=0;u=0;l=0;reference_on=0;end
 endtask
 initial begin
  repeat(4)@(negedge clk);rst=1;
  for(frame=0;frame<2;frame=frame+1)begin
   for(y=0;y<720;y=y+1)begin
    for(x=0;x<1280;x=x+4)begin
     if(x==636)bubble();
     @(negedge clk);v=1;u=(x==0 && y==0);l=(x==1276);
     ds=(frame==0)?{1'b1,16'h1234,16'h5678,16'h9abc,22'h123456,
                     28'h1234567,28'h89abcde,28'hfedcba9,18'h38400}:
                   {1'b0,16'h4321,16'h8765,16'hcba9,22'h234567,
                     28'hfedcba9,28'h8765432,28'h1234567,18'h12345};
     for(lane=0;lane<4;lane=lane+1)
      data[lane*24+:24]={8'(x+lane),8'(y+frame),8'(x+y+lane)};
     reference_on=(x>=16 && x<1264 && ((y>=160 && y<176)||(y>=184 && y<200)));
     reference_in=(y<180)?24'h808080:24'hc0c0c0;
    end
    bubble();
   end
  end
  bubble();repeat(4)@(negedge clk);
  if(checks!=460800 || neutral_checks!=19968 || unchanged_checks!=440832)
   $fatal(1,"incomplete coverage all=%0d neutral=%0d rest=%0d",checks,neutral_checks,unchanged_checks);
  $display("PASS spatial probe: 2 full 720p frames, 19968 neutral groups, 440832 unchanged groups, all RGB lanes, bubbles and unchanged two-stage transport");
  $finish;
 end
 initial begin #6000000;$fatal(1,"spatial probe watchdog");end
endmodule
