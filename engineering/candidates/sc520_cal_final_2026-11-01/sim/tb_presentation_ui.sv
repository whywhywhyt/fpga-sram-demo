`timescale 1ns/1ps
module tb_presentation_ui;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,v=0,u=0,l=0;reg [95:0] data={4{24'h586068}};
 wire tv,tu,tl,pv,pu,pl;wire [95:0] td,pd;
 reg [255:0] boxes=0;reg [159:0] cal=3;
 reg [2:0] mode=5;
 target_overlay_96 #(.PRESENTATION(1)) target(.clk(clk),.rst_n(rst),.I_tuser(u),.I_tvalid(v),.I_tlast(l),.I_tdata(data),
  .I_detection_data(data),.I_mode(mode),.I_color(2'd0),.I_threshold(8'd32),.O_tuser(tu),.O_tvalid(tv),.O_tlast(tl),.O_tdata(td),.O_mode(),.O_threshold());
 presentation_status_96 ui(.clk(clk),.rst_n(rst),.I_tuser(tu),.I_tvalid(tv),.I_tlast(tl),.I_tdata(td),
  .I_mode(mode),.I_threshold(8'd32),.I_spatial_diag(cal),.I_motion_valid(1'b1),.I_motion_tiles(10'd32),
  .O_tuser(pu),.O_tvalid(pv),.O_tlast(pl),.O_tdata(pd));
 reg [53:0] fixtures[0:6144-1];reg [1:0] c,s;reg [4:0] pos;reg [15:0] xb,yb;
 wire [7:0] code;wire [4:0] len;reg [7:0] expected;reg [4:0] expected_len;
 shape_tag_zh_char grammar(.color(c),.shape(s),.position(pos),.x_bcd(xb),.y_bcd(yb),.code(code),.length(len));
 reg [23:0] raster[0:921599];integer count=0,i,x,y,k,xx,yy,white=0,red=0,clean=0;
 reg [23:0] pixel;reg [9:0] vq=0,uq=0,lq=0;
 reg hd=0,hu=0,hl=0,done=0,valid_sample=1;reg [23:0] hp=0;wire [23:0] lp,wp;
 reg [2:0] wall_state=7;
 latency_panel latency(.clk(clk),.rst_n(rst),.de(hd),.user(hu),.last(hl),.pixel(hp),
  .sample_done(done),.sample_valid(valid_sample),.latency_ticks(24'd496),.displayed_id(16'hbeef),.repeat_count(16'habcd),.repeated(1'b0),.out_pixel(lp));
 wall_status_panel wall(.clk(clk),.rst_n(rst),.de(hd),.user(hu),.last(hl),.status_async(wall_state),.pixel(lp),.out_pixel(wp));
 always @(posedge clk)begin
  if(!rst)begin vq<=0;uq<=0;lq<=0;end
  else begin vq<={vq[8:0],v};uq<={uq[8:0],u};lq<={lq[8:0],l};end
 end
 always @(negedge clk)if(rst)begin
  if({pv,pu,pl}!=={vq[9],uq[9],lq[9]})$fatal(1,"UI changed ten-stage framing");
  if(pv)begin
   if(^pd===1'bx)$fatal(1,"UI unknown raster word %0d",count);
   for(k=0;k<4;k=k+1)begin
    pixel=pd[95-k*24-:24];xx=(count+k)%1280;yy=(count+k)/1280;
    raster[count+k]=pixel;
    if(yy>=160 && yy<200 && !(xx>=96 && xx<336 && yy>=184) && pixel!==24'h586068)$fatal(1,"obsolete gray bars still visible");
    if(xx<528 && yy>=608 && yy<672)begin
     if(pixel!==24'h586068)$fatal(1,"duplicate lower-left target table still visible");
     clean++;
    end
    if(xx>=96 && xx<336 && yy>=184 && yy<200)begin
     if(pixel!==24'h101820 && pixel!==24'hff4040)$fatal(1,"Chinese target title missing");
     if(pixel==24'hff4040)white++;
    end
    if(xx==96 && yy==220)begin
     if(pixel!==24'hff4040)$fatal(1,"red bounding box changed");red++;
    end
   end
   count+=4;
  end
 end
 integer f,frame,checked=0,completed=0;
 initial begin
  $readmemh("presentation_tags.hex",fixtures);
  for(i=0;i<6144;i++)begin
   {c,s,pos,xb,yb,expected,expected_len}=fixtures[i];#1;
   if(code!==expected || len!==expected_len)$fatal(1,"Chinese tag grammar case %0d code%h/%h len%0d/%0d",i,code,expected,len,expected_len);
  end
  boxes[63:0]={16'd625,2'd1,2'd1,11'd299,11'd200,11'd195,11'd96};
  boxes[127:64]={16'd625,2'd2,2'd2,11'd349,11'd252,11'd799,11'd700};
  boxes[191:128]={16'd625,2'd3,2'd3,11'd531,11'd432,11'd1151,11'd1052};
  boxes[255:192]={16'd625,2'd3,2'd0,11'd599,11'd500,11'd599,11'd500};
  force target.detected=1'b1;force target.boxes=boxes;force target.shown=3'd4;force target.total=8'd4;
  force target.detector_frame=16'd1;force target.capture_frame=16'd1;force target.detector_margin=8'd32;force target.overflow=1'b0;
  repeat(4)@(negedge clk);rst=1;repeat(120)@(negedge clk);
  for(y=0;y<720;y++)begin
   for(x=0;x<1280;x+=4)begin
    @(negedge clk);u=x==0&&y==0;v=1;l=x==1276;
   end
   @(negedge clk);u=0;v=0;l=0;
  end
  @(negedge clk);v=0;u=0;l=0;repeat(20)@(negedge clk);
  if(count!=921600 || clean!=33792 || white<100 || red!=1)$fatal(1,"UI raster coverage %0d %0d %0d %0d",count,clean,white,red);
  // First valid measurement, then a frame with an invalid measurement.
  // Unrelated pixels and the old large latency panel must pass unchanged.
  for(frame=0;frame<2;frame++)begin
   @(negedge clk);done=1;valid_sample=frame==0;
   @(negedge clk);done=0;repeat(30)@(negedge clk);
   f=$fopen(frame==0?"../reports/presentation_on_rtl.ppm":"../reports/presentation_wait_rtl.ppm","wb");
   $fwrite(f,"P6\n1280 720\n255\n");
   for(y=0;y<720;y++)for(x=0;x<1280;x++)begin
    @(negedge clk);hd=1;hu=x==0&&y==0;hl=x==1279;hp=raster[y*1280+x];
    #1;
    if(^wp===1'bx)$fatal(1,"unknown final HDMI pixel %0d,%0d",x,y);
    if(x>=704 && x<944 && y>=16 && y<112 && wp!==hp)$fatal(1,"obsolete latency panel still covers scene");
    if(!(x>=944 && x<1264 && y>=16 && y<48) && !(x>=1008 && x<1264 && y>=672 && y<704) && wp!==hp)
      $fatal(1,"HDMI panels modify unrelated pixel %0d,%0d",x,y);
    $fwrite(f,"%c%c%c",wp[23:16],wp[15:8],wp[7:0]);checked++;
   end
   @(negedge clk);hd=0;hu=0;hl=0;$fclose(f);
   if(latency.valid_hold!==(frame==0))$fatal(1,"valid/stale latency status incorrect");
  end
  completed=1;
  $display("PASS presentation UI: 6144 Chinese labels, 921600-pixel camera raster, 1843200 HDMI pixels, clean diagnostics regions, colored boxes, valid/wait latency and unchanged ten-stage transport");
  $finish;
 end
 initial begin #100000000;$fatal(1,"presentation watchdog");end
endmodule
