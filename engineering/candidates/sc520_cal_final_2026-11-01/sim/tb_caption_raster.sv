`timescale 1ns/1ps
// Render real four-pixel captions through real HDMI panels. The existing full
// composite regression separately covers the unchanged final Logo stage.
// An independent bitmap renderer checks every pixel of all caption rectangles.
module tb_caption_raster;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,v=0,u=0,l=0;reg [2:0] mode=0,wall_state=0;
 reg [7:0] threshold=96;reg [159:0] cal=0;
 wire ov,ou,ol;wire [95:0] rgb;
 presentation_status_96 status(.clk(clk),.rst_n(rst),.I_tlast(l),.I_tuser(u),.I_tvalid(v),
  .I_tdata({4{24'h586068}}),.I_mode(mode),.I_threshold(threshold),.I_spatial_diag(cal),
  .I_motion_valid(1'b1),.I_motion_tiles(10'd123),.I_motion_global(1'b0),
  .O_tlast(ol),.O_tuser(ou),.O_tvalid(ov),.O_tdata(rgb));
 reg [23:0] memory[0:921599];integer written=0,k;
 reg [1:0] vq=0,uq=0,lq=0;
 always @(posedge clk)begin
  vq={vq[0],v};uq={uq[0],u};lq={lq[0],l};#1;
  if(rst)begin
   if({ov,ou,ol}!=={vq[1],uq[1],lq[1]})$fatal(1,"caption changed two-stage framing");
   if(ov)begin
    if(^rgb===1'bx)$fatal(1,"unknown status pixel");
    for(k=0;k<4;k++)memory[written+k]=rgb[95-k*24-:24];
    written+=4;
   end
  end
 end
 reg hd=0,hu=0,hl=0;reg [23:0] hp=0;wire [23:0] lp,wp;
 reg [23:0] fp=0;reg fd=0;
 latency_panel delay(.clk(clk),.rst_n(rst),.de(hd),.user(hu),.last(hl),.pixel(hp),
  .sample_done(1'b0),.sample_valid(1'b0),.latency_ticks(24'd0),.displayed_id(16'd0),
  .repeat_count(16'd0),.repeated(1'b0),.out_pixel(lp));
 wall_status_panel wall(.clk(clk),.rst_n(rst),.de(hd),.user(hu),.last(hl),
  .status_async(wall_state),.pixel(lp),.out_pixel(wp));
 // Snapshot the combinational HDMI pixels before the coordinate counters move.
 always @(posedge clk)begin fp<=wp;fd<=hd;end
 integer frame,n,file,displayed=0,checked=0,completed=0;
 reg scoring=0;
 always @(posedge clk)begin #2;if(rst && scoring && fd)begin
  if(^fp===1'bx)$fatal(1,"unknown final HDMI caption pixel");
  $fwrite(file,"%c%c%c",fp[23:16],fp[15:8],fp[7:0]);displayed++;checked++;
 end end
 initial begin
  repeat(4)@(negedge clk);rst=1;
  for(frame=0;frame<8;frame++)begin
   written=0;mode=frame;wall_state=frame;cal=frame<6?frame:frame==6?3:4;
   case(frame)2:threshold=104;3:threshold=112;4:threshold=16;5:threshold=40;default:threshold=96;endcase
   for(n=0;n<230400;n++)begin
    @(negedge clk);v=1;u=n==0;l=n%320==319;
   end
   @(negedge clk);v=0;u=0;l=0;repeat(5)@(negedge clk);
   if(written!=921600)$fatal(1,"incomplete caption frame %0d",written);
   file=$fopen($sformatf("../reports/caption_rtl_%0d.ppm",frame),"wb");
   if(file==0)$fatal(1,"cannot open caption raster");
   $fwrite(file,"P6\n1280 720\n255\n");displayed=0;scoring=1;
   for(n=0;n<921600;n++)begin
    hd=1;hu=n==0;hl=n%1280==1279;hp=memory[n];@(negedge clk);
   end
   hd=0;hu=0;hl=0;repeat(5)@(negedge clk);scoring=0;$fclose(file);
   if(displayed!=921600)$fatal(1,"incomplete final raster %0d",displayed);
  end
  if(checked!=7372800)$fatal(1,"caption raster coverage");
  completed=1;$display("PASS caption raster: eight modes, all eight wall states and six CAL states, unchanged transport and 7372800 HDMI overlay pixels");$finish;
 end
 initial begin #100000000;$fatal(1,"caption raster watchdog");end
endmodule
