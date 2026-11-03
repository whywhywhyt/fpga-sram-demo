`timescale 1ns/1ps
// Production overlay with controlled, already-completed detection metadata.
// Classification itself is covered separately by yellow_circle/stability.
module tb_shape_overlay;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,user=0,valid=0,last=0;
 reg [95:0] data={4{24'h203040}};
 wire ou,ov,ol;wire [95:0] od;wire [2:0] mode;wire [7:0] threshold;
 reg [255:0] detections=0;
 reg [15:0] frame_number=1;
 integer x,y,lane,ox=0,oy=0,checked=0,reds=0,texts=0,image_file;
 reg [23:0] pixel;
 reg [7:0] expected_users=0,expected_valids=0,expected_lasts=0;
 always @(posedge clk)begin
  if(!rst_n)begin expected_users<=0;expected_valids<=0;expected_lasts<=0;end
  else begin expected_users<={expected_users[6:0],user};expected_valids<={expected_valids[6:0],valid};expected_lasts<={expected_lasts[6:0],last};end
 end
 target_overlay_96 dut(.clk(clk),.rst_n(rst_n),.I_tuser(user),.I_tvalid(valid),.I_tlast(last),.I_tdata(data),
   .I_mode(3'd5),.I_threshold(8'd32),.I_color(2'd0),.O_tuser(ou),.O_tvalid(ov),.O_tlast(ol),.O_tdata(od),
   .O_mode(mode),.O_threshold(threshold));
 always @(negedge clk)begin
  if(rst_n && (ou!==expected_users[7] || ov!==expected_valids[7] || ol!==expected_lasts[7]))
    $fatal(1,"8-clock user/valid/last transport changed");
  if(ou)begin ox=0;oy=0;end
  if(ov)begin
   if((^od)===1'bx)$fatal(1,"unknown overlay pixel at (%0d,%0d): %h",ox,oy,od);
   if(mode!==5 || threshold!==32)$fatal(1,"metadata alignment");
   for(lane=0;lane<4;lane=lane+1)begin
    pixel=od[95-lane*24 -:24];
    $fwrite(image_file,"%c%c%c",pixel[23:16],pixel[15:8],pixel[7:0]);
    // First box has integer lattice bounds (96,200)-(195,299).
    if(oy==220 && ox+lane==96 && pixel!==24'hff4040)$fatal(1,"red border missing");
    if(oy==220 && ox+lane==100 && pixel!==24'h203040)$fatal(1,"border bleeds into scene");
    if(oy==280 && ox+lane==700 && pixel!==24'h40ff70)$fatal(1,"green border missing");
    if(oy==460 && ox+lane==1052 && pixel!==24'h40c8ff)$fatal(1,"blue border missing");
    if(oy==530 && ox+lane==500 && pixel!==24'hffe040)$fatal(1,"yellow border missing");
    // BLUE title is clamped against the right edge and must stay colored.
    if(oy==428 && ox+lane==1279 && pixel!==24'h40c8ff)$fatal(1,"right-edge title clip/gap");
    // 19-character red title sits at (96,184), entirely above the box.
    if(oy>=184 && oy<198 && ox+lane>=96 && ox+lane<400)begin
     if(pixel!==24'hff4040 && pixel!==24'hffffff)$fatal(1,"title not red/white at (%0d,%0d)",ox+lane,oy);
     if(pixel==24'hff4040)reds=reds+1;
     if(pixel==24'hffffff)texts=texts+1;
    end
   end
   checked=checked+4;
   if(ox==1276)begin ox=0;oy=oy+1;end else ox=ox+4;
  end
 end
 initial begin
  image_file=$fopen("../reports/shape_overlay_rtl.ppm","wb");
  if(!image_file)$fatal(1,"cannot open raster preview");
  $fwrite(image_file,"P6\n1280 720\n255\n");
  detections[63:0]={16'd625,2'd1,2'd1,11'd299,11'd200,11'd195,11'd96};
  detections[127:64]={16'd625,2'd2,2'd2,11'd349,11'd252,11'd799,11'd700};
  detections[191:128]={16'd625,2'd3,2'd3,11'd531,11'd432,11'd1151,11'd1052};
  detections[255:192]={16'd625,2'd3,2'd0,11'd599,11'd500,11'd599,11'd500};
  force dut.detected=1'b1;force dut.boxes=detections;force dut.shown=3'd4;
  force dut.total=8'd4;force dut.detector_frame=frame_number;force dut.capture_frame=frame_number;
  force dut.detector_margin=8'd32;force dut.overflow=1'b0;
  repeat(4)@(negedge clk);rst_n=1;
  // Allow serial binary-to-BCD engine to finish all coordinate conversions.
  repeat(120)@(negedge clk);
  if(dut.coordinate_bcd[31:0]!==32'h02490145)$fatal(1,"coordinate BCD mismatch: %h",dut.coordinate_bcd[31:0]);
  for(y=0;y<720;y=y+1)for(x=0;x<1280;x=x+4)begin
   @(negedge clk);user=(x==0 && y==0);valid=1;last=(x==1276);
  end
  @(negedge clk);user=0;valid=0;last=0;
  repeat(12)@(negedge clk);
  if(checked!=1280*720 || reds==0 || texts==0)$fatal(1,"raster counts pixels=%0d red=%0d text=%0d",checked,reds,texts);
  $fclose(image_file);
  // A result arriving just before SOF must not mix new boxes with old BCD.
  detections[63:0]={16'd625,2'd1,2'd1,11'd299,11'd200,11'd295,11'd196};
  frame_number=2;
  repeat(3)@(negedge clk);
  user=1;@(negedge clk);user=0;
  if(!((dut.snapshot_boxes[10:0]==96 && dut.snapshot_coordinates[15:0]==16'h0145) ||
       (dut.snapshot_boxes[10:0]==196 && dut.snapshot_coordinates[15:0]==16'h0245)))
    $fatal(1,"mixed frame metadata: x0=%0d center_BCD=%h",dut.snapshot_boxes[10:0],dut.snapshot_coordinates[15:0]);
  repeat(120)@(negedge clk);
  user=1;@(negedge clk);user=0;
  if(dut.snapshot_boxes[10:0]!=196 || dut.snapshot_coordinates[15:0]!=16'h0245)
    $fatal(1,"completed metadata not published on next SOF");
  $display("PASS overlay raster: 921600 known pixels, four-color borders/title, edge clamping, white text, 8-clock transport, center BCD and near-SOF atomic publication");
  $finish;
 end
endmodule
