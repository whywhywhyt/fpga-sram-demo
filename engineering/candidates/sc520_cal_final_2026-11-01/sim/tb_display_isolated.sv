`timescale 1ns/1ps
// Only demosaic is synthetic. The real ISP, AWB, image algorithms, display
// bridge, detector/CCL, overlays, and DDR packer execute unchanged production RTL.
module demosaic #(parameter IMG_HEIGHT=720,IMG_WIDTH=1280,data_complete_delay=50,parameter BAYER_MODE="BGGR")(
 input I_clk,I_rst_n,input [39:0] axi4s_video_tdata,input [9:0] axi4s_video_tdest,
 input axi4s_video_tlast,axi4s_video_tvalid,axi4s_video_tuser,output axi4s_video_tready,
 output O_tlast,O_tuser,output [127:0] O_tdata,output O_tvalid,input O_tready);
 assign O_tdata={4{{8'd0,axi4s_video_tdata[23:0]}}};
 assign {O_tlast,O_tuser,O_tvalid}={axi4s_video_tlast,axi4s_video_tuser,axi4s_video_tvalid};
 assign axi4s_video_tready=O_tready;
endmodule
module tb_display_isolated;
 reg clk=0,rst=0,v=0,u=0,l=0;always #4.83 clk=~clk;
 reg[39:0]data=0;reg[2:0]mode=0;
 wire[95:0]wall;wire wv,wu,wl;wire[127:0]packed_rgb;wire pv,pu,pl;
 isp_top #(.ENABLE_LATENCY(0)) dut(.I_frame_tag(96'd0),.cal_capture(1'b0),.cal_toggle(1'b0),.cal_clear(1'b0),
 .requested_mode(mode),.requested_color(2'd2),.requested_binary_threshold(8'd96),.requested_edge_threshold(8'd96),.requested_red_threshold(8'd40),
 .axi4s_video_aclk(clk),.I_rst_n(rst),.I_tlast(l),.I_tuser(u),.I_tdata(data),.I_tvalid(v),.I_tdest(10'd0),.O_tready(1'b1),
 .O_tdata(packed_rgb),.O_tlast(pl),.O_tuser(pu),.O_tvalid(pv),.I_tready(),.wall_rgb(wall),.wall_valid(wv),.wall_user(wu),.wall_last(wl));
 // Freeze automatic gain only in this bench to retain an exact RGB oracle.
 defparam dut.u_awb.MIN_SAMPLES=4194303;
 reg[95:0]rawq[0:3],toneq[0:3],wq;reg[2:0]mq[0:3];reg[7:0]thq[0:3];
 reg[3:0]vq=0,uq=0,lq=0;reg wvq=0,wuq=0,wlq=0;
 integer frame,x,y,groups=0,wall_groups=0,packed_words=0,colored=0,unchanged=0,different=0,votes=0,blue_votes=0,yellow_votes=0;
 integer completed=0;
 function automatic[23:0] ref_tone(input[23:0]p);
  integer r,g,b,peak,s;
  begin
   r=p[23:16];g=p[15:8];b=p[7:0];peak=r>g?r:g;if(b>peak)peak=b;
   s=peak<=8?0:peak<48?4*(peak-8):peak<74?160:(7*(255-peak)+7)/8;
   ref_tone={8'((r*(256+s)+128)/256),8'((g*(256+s)+128)/256),8'((b*(256+s)+128)/256)};
  end
 endfunction
 reg [23:0] reference_left=0;
 reg reference_has_left=0;reg [95:0] reference_filtered;reg [23:0] cp,lp;
 integer lane_ref,rr,gg,bb;
 function automatic [23:0] ref_smooth(input [23:0] current,left,input bit allowed);
  integer r,g,b,pr,pg,pb;
  begin
   r=current[23:16];g=current[15:8];b=current[7:0];pr=left[23:16];pg=left[15:8];pb=left[7:0];
   if(allowed && (r>8||g>8||b>8) && r-pr<=12 && pr-r<=12 && g-pg<=12 && pg-g<=12 && b-pb<=12 && pb-b<=12)
    ref_smooth={8'((3*r+pr+2)/4),8'((3*g+pg+2)/4),8'((3*b+pb+2)/4)};
   else ref_smooth=current;
  end
 endfunction
 always @(posedge clk)begin:monitor
  integer a,addr,xx,yy,expected_class;
  reg[95:0]expected;
  if(!rst)begin
   reference_left=0;reference_has_left=0;vq=0;uq=0;lq=0;wvq=0;wuq=0;wlq=0;wq=0;
   for(a=0;a<4;a++)begin rawq[a]=0;toneq[a]=0;mq[a]=0;thq[a]=0;end
  end else begin
   for(a=3;a>0;a--)begin rawq[a]=rawq[a-1];toneq[a]=toneq[a-1];mq[a]=mq[a-1];thq[a]=thq[a-1];end
   rawq[0]=dut.process_data;mq[0]=dut.active_mode;thq[0]=dut.active_threshold;
   for(lane_ref=0;lane_ref<4;lane_ref++)begin
    cp=dut.process_data[95-lane_ref*24-:24];
    lp=lane_ref==0?reference_left:dut.process_data[119-lane_ref*24-:24];
    reference_filtered[95-lane_ref*24-:24]=ref_smooth(cp,lp,lane_ref!=0 || (reference_has_left && !dut.process_user));
   end
   for(a=0;a<4;a++)toneq[0][a*24+:24]=ref_tone(reference_filtered[a*24+:24]);
   if(dut.process_user)reference_has_left=0;
   if(dut.process_valid)begin reference_left=dut.process_data[23:0];reference_has_left=!dut.process_last;end
   vq={vq[2:0],dut.process_valid};uq={uq[2:0],dut.process_user};lq={lq[2:0],dut.process_last};
   wq=dut.awb_O_tdata;wvq=dut.awb_O_tvalid;wuq=dut.awb_O_tuser;wlq=dut.awb_O_tlast;
  end
  #1;
  if(rst)begin
   if({wv,wu,wl}!=={wvq,wuq,wlq})$fatal(1,"raw wall framing changed");
   if(wv)begin if(wall!==wq)$fatal(1,"display tone leaked into wall/marker input");wall_groups++;end
   if({dut.display_tone_valid,dut.display_tone_user,dut.display_tone_last}!=={vq[3],uq[3],lq[3]})$fatal(1,"bridge framing");
   if(dut.display_mode[3]!==mq[3]||dut.display_threshold[3]!==thq[3])$fatal(1,"bridge metadata alignment");
   if(dut.display_tone_valid)begin
    if(dut.analysis_rgb[3]!==rawq[3])$fatal(1,"analysis RGB does not preserve raw processed input");
    expected=(mq[3]==0||mq[3]==4||mq[3]==5||mq[3]==6)?toneq[3]:rawq[3];
    if(dut.display_rgb!==expected)$fatal(1,"display mapping/algorithm passthrough mismatch mode%0d",mq[3]);
    if(dut.u_target_overlay.detector.data!==rawq[3])$fatal(1,"detector consumes display-mapped pixels");
    groups++;
    if(mq[3]==0||mq[3]==4||mq[3]==5||mq[3]==6)begin colored++;if(expected!==rawq[3])different++;end
    else unchanged++;
   end
   if(dut.u_target_overlay.detector.vote.tile_valid)begin
    addr=dut.u_target_overlay.detector.vote.tile_addr;xx=addr%320*4;yy=addr/320*4;
    expected_class=0;
    if(dut.u_target_overlay.detector.vote.tile_frame==3)begin
     if(xx>=128&&xx<384&&yy>=128&&yy<384)expected_class=3;
     if(xx>=768&&xx<1024&&yy>=128&&yy<384)expected_class=4;
    end else if(dut.u_target_overlay.detector.vote.tile_frame!=2)$fatal(1,"unexpected active detector frame");
    if(dut.u_target_overlay.detector.vote.tile_color!==3'(expected_class))$fatal(1,"tile expected class%0d got%0d x%0d y%0d frame%0d",expected_class,dut.u_target_overlay.detector.vote.tile_color,xx,yy,dut.u_target_overlay.detector.vote.tile_frame);
    votes++;if(expected_class==3)blue_votes++;if(expected_class==4)yellow_votes++;
   end
   if(pv)begin if(^packed_rgb===1'bx)$fatal(1,"unknown packed_rgb output");packed_words++;end
  end
 end
 task idle(input integer n);begin @(negedge clk);v=0;u=0;l=0;repeat(n-1)@(negedge clk);end endtask
 initial begin
  repeat(5)@(negedge clk);rst=1;idle(5);
  for(frame=0;frame<9;frame++)begin
   case(frame)0:mode=0;1,2:mode=5;3:mode=1;4:mode=2;5:mode=3;6:mode=4;7:mode=6;8:mode=7;endcase
   @(negedge clk);u=1;v=0;l=0;idle(3);
   for(y=0;y<720;y++)begin
    for(x=0;x<1280;x+=4)begin
     @(negedge clk);u=0;v=1;l=x==1276;
     if(frame==1||frame==2)begin
      data={16'd0,24'h60687c}; // Weak blue background: must be rejected.
      if(frame==2&&x>=128&&x<384&&y>=128&&y<384)data={16'd0,24'h183078}; // Dim real blue.
      if(frame==2&&x>=768&&x<1024&&y>=128&&y<384)data={16'd0,24'h704010}; // Borderline yellow.
     end else data={16'd0,8'(16+(x/4)%145),8'(16+y%145),8'(16+((x+y)/4)%145)};
     // Existing 96->128 packer resets phase on an invalid cycle. Inject gaps
     // at complete four-group boundaries, matching its transport contract;
     // arbitrary partial-word bubbles are not supported by the baseline.
     if((x/4)%64==63)idle(1);
    end
    idle(12);
   end
   idle(2000);
  end
  idle(150);
  if(groups!=2073600||wall_groups!=2073600||packed_words!=1555200||colored!=1152000||unchanged!=921600||different<100000||votes!=115200||blue_votes!=4096||yellow_votes!=4096)
   $fatal(1,"coverage groups%0d wall%0d packed_rgb%0d colored%0d mono%0d different%0d votes%0d blue%0d yellow%0d",groups,wall_groups,packed_words,colored,unchanged,different,votes,blue_votes,yellow_votes);
  completed=1;$display("PASS display isolation: nine full 720p frames, 2073600 groups, 1555200 DDR words, eight modes, unchanged monochrome algorithms and wall/marker tap, aligned raw detector/display metadata, 115200 exact tiles including neutral-background rejection and dim-blue/yellow positives");$finish;
 end
 initial begin #40000000;$fatal(1,"display isolation watchdog");end
endmodule
