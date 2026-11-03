`timescale 1ns/1ps
module tb_presentation_states;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,v=0,u=0,l=0;reg [2:0] mode=0;reg [7:0] threshold=96;reg [159:0] cal=0;reg [9:0] moving=0;
 wire ov,ou,ol;wire [95:0] data;
 presentation_status_96 dut(.clk(clk),.rst_n(rst),.I_tlast(l),.I_tuser(u),.I_tvalid(v),.I_tdata({4{24'h234567}}),
  .I_mode(mode),.I_threshold(threshold),.I_spatial_diag(cal),.I_motion_valid(1'b1),.I_motion_tiles(moving),.I_motion_global(1'b0),
  .O_tlast(ol),.O_tuser(ou),.O_tvalid(ov),.O_tdata(data));
 reg [159:0] names[0:5],states[0:5],motion[0:5],params[0:5];
 reg [1:0] vq=0,uq=0,lq=0;integer count=0,checked=0,frame,x,y,pos,code,completed=0;
 always @(posedge clk)begin
  vq={vq[0],v};uq={uq[0],u};lq={lq[0],l};
  #1;if(rst)begin
   if({ov,ou,ol}!=={vq[1],uq[1],lq[1]})$fatal(1,"presentation status framing");
   if(ov)begin
    if(^data===1'bx)$fatal(1,"status pixel unknown");
    count++;
   end
  end
 end
 initial begin
  names[0]=160'h8081828320202020202020202020202020202020;
  names[1]=160'h8485838620202020202020202020202020202020;
  names[2]=160'h8788838620202020202020202020202020202020;
  names[3]=160'h898a8b8c20202020202020202020202020202020;
  names[4]=160'h83868d8e20202020202020202020202020202020;
  names[5]=160'h8f81909192932020202020202020202020202020;
  states[0]=160'h99813a209a999b20202020202020202020202020;
  states[1]=160'h99813a209c9d9620202020202020202020202020;
  states[2]=160'h99813a209e9f9620202020202020202020202020;
  states[3]=160'h99813a204f4e2020202020202020202020202020;
  states[4]=160'h99813a209a999b20202020202020202020202020;
  states[5]=160'h99813a20a4a52020202020202020202020202020;
  motion[0]=160'ha6a7a82030303020202020202020202020202020;
  motion[1]=160'ha6a7a82030313620202020202020202020202020;
  motion[2]=160'ha6a7a82030333220202020202020202020202020;
  motion[3]=160'ha6a7a82031323820202020202020202020202020;
  motion[4]=160'ha6a7a82032353520202020202020202020202020;
  motion[5]=160'ha6a7a82035313120202020202020202020202020;
  params[0]=160'h2020202020202020202020202020202020202020;
  params[1]=160'h2020202020202020202020202020202020202020;
  params[2]=160'h94883a3130342020202020202020202020202020;
  params[3]=160'h94883a3131322020202020202020202020202020;
  params[4]=160'h8e853a9620202020202020202020202020202020;
  params[5]=160'h81983a3034302020202020202020202020202020;
  repeat(4)@(negedge clk);rst=1;
  for(frame=0;frame<6;frame++)begin
   for(y=0;y<720;y++)begin
    for(x=0;x<1280;x+=4)begin
     @(negedge clk);u=x==0&&y==0;v=1;l=x==1276;
     if(u)begin
      mode=frame;cal=frame;
      case(frame)0:begin moving=0;threshold=96;end 1:begin moving=16;threshold=96;end
       2:begin moving=32;threshold=104;end 3:begin moving=128;threshold=112;end
       4:begin moving=255;threshold=16;end 5:begin moving=511;threshold=40;end
      endcase
     end else begin mode=7;cal=7;threshold=255;moving=999;end
     #1;
     if(x>=192 && x<(frame==5?384:320) && y==32)begin
      pos=(x-192)/32;code=(names[frame]>>((19-pos)*8))&255;
      if(dut.code!==code[7:0])$fatal(1,"mode caption frame%0d pos%0d %h/%h",frame,pos,dut.code,code);checked++;
     end
     if(x>=24 && x<136 && y==680)begin
      pos=(x-24)/16;code=(states[frame]>>((19-pos)*8))&255;
      if(dut.code!==code[7:0])$fatal(1,"CAL caption frame%0d pos%0d %h/%h",frame,pos,dut.code,code);checked++;
     end
     if(x>=952 && x<1064 && y==64)begin
      pos=(x-952)/16;code=32; // Activity is shown only in independent motion mode 6.
      if(dut.code!==code[7:0])$fatal(1,"motion caption frame%0d pos%0d %h/%h",frame,pos,dut.code,code);checked++;
     end
     if(frame>=2 && x>=192 && x<304 && y==88)begin
      pos=(x-192)/16;code=(params[frame]>>((19-pos)*8))&255;
      if(dut.code!==code[7:0])$fatal(1,"parameter caption frame%0d pos%0d %h/%h",frame,pos,dut.code,code);checked++;
     end
    end
    @(negedge clk);v=0;u=0;l=0;
   end
  end
  repeat(4)@(negedge clk);
  if(count!=1382400 || checked<500)$fatal(1,"status coverage count%0d checks%0d",count,checked);
  completed=1;$display("PASS presentation states: six image modes, CAL states with removed legacy OFF mapped to uncalibrated, thresholds/strength, six motion levels and mid-frame atomic metadata across 5529600 pixels");$finish;
 end
endmodule
