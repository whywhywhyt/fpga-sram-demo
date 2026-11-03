`timescale 1ns/1ps
module tb_motion_regions #(parameter FULL=0,AUTO=0);
 localparam W=FULL?1280:160,H=FULL?720:80,TW=FULL?40:8,TH=FULL?40:8;
 localparam GW=W/TW,GH=H/TH,N=GW*GH,AW=$clog2(N),FRAMES=FULL?10:22;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,u=0,v=0,l=0;reg [95:0] data=0;reg [2:0] mode=6;
 wire valid,visible,global_change,map_bit;wire [9:0] count;wire [5:0] x0,x1;wire [4:0] y0,y1;
 wire [AW-1:0] map_addr;reg manual=0;reg [AW-1:0] manual_addr=0;reg manual_sof=0;
 wire ou,ov,ol;wire [95:0] od;wire [2:0] om;wire [7:0] ot;
 motion_region_detect_96 #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.TILE_WIDTH(TW),.TILE_HEIGHT(TH)) dut(
  .clk(clk),.rst_n(rst),.I_tuser(u),.I_tvalid(v),.I_tlast(l),.I_tdata(data),
  .display_sof(manual?manual_sof:u),.map_addr(manual?manual_addr:map_addr),.map_bit(map_bit),
  .result_valid(valid),.moving_tiles(count),.box_visible(visible),.global_change(global_change),
  .box_x0(x0),.box_x1(x1),.box_y0(y0),.box_y1(y1));
 motion_region_overlay_96 #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.TILE_WIDTH(TW),.TILE_HEIGHT(TH)) overlay(
  .clk(clk),.rst_n(rst),.I_tuser(u),.I_tvalid(v),.I_tlast(l),.I_tdata(data),.I_mode(mode),.I_threshold(8'd96),
  .result_valid(valid),.box_visible(visible),.global_change(global_change),.box_x0(x0),.box_x1(x1),.box_y0(y0),.box_y1(y1),
  .map_addr(map_addr),.map_bit(map_bit),.O_tuser(ou),.O_tvalid(ov),.O_tlast(ol),.O_tdata(od),.O_mode(om),.O_threshold(ot));
 reg [383:0] samples[0:FRAMES*N-1];reg masks[0:FRAMES*N-1];reg [63:0] meta[0:FRAMES-1];
 reg [95:0] rgbq[0:2];reg [2:0] vq=0,uq=0,lq=0;
 reg [2:0] modeq[0:2];integer qi,frame,x,y,lane,idx,k,sample_index,pixel_x;
 reg [95:0] expectedq[0:2];integer mx=0,my=0,mf=-1,ml,mi,xx;
 reg mb=0,mg=0,mvalid=0;integer mlft,mrgt,mtop,mbot;reg [23:0] ep;
 integer completed=0,checks=0,raster_checks=0,settled=0,ppm=0;reg [383:0] cell_samples;
 always @(posedge clk)begin
  if(!rst)begin vq=0;uq=0;lq=0;for(qi=0;qi<3;qi++)begin rgbq[qi]=0;modeq[qi]=0;expectedq[qi]=0;end end
  else begin
   for(qi=2;qi>0;qi--)begin rgbq[qi]=rgbq[qi-1];modeq[qi]=modeq[qi-1];expectedq[qi]=expectedq[qi-1];end
   rgbq[0]=data;modeq[0]=mode;vq={vq[1:0],v};uq={uq[1:0],u};lq={lq[1:0],l};
   if(u)begin
    mx=0;my=0;mf=frame-1;mb=visible;mg=global_change;mvalid=valid;
    mlft=x0*TW;mrgt=(x1+1)*TW-1;mtop=y0*TH;mbot=(y1+1)*TH-1;
   end
   for(ml=0;ml<4;ml++)begin
    xx=mx+ml;ep=data[95-ml*24-:24];mi=(my/TH)*GW+mx/TW;
    if(mode==6&&mb&&mvalid&&!mg&&xx>=mlft&&xx<=mrgt&&my>=mtop&&my<=mbot&&
      (xx-mlft<2||mrgt-xx<2||my-mtop<2||mbot-my<2))ep=24'hffd040;
    // Production overlay must preserve every non-border source pixel; no green grid.
    expectedq[0][95-ml*24-:24]=ep;
   end
   if(v)begin mx=l?0:mx+4;if(l)my=my+1;end
   #1;
   if({ou,ov,ol}!=={uq[2],vq[2],lq[2]})$fatal(1,"motion transport framing");
   if(ov)begin
    if(^od===1'bx)$fatal(1,"unknown motion pixel");
    if(om!==modeq[2] || ot!==96)$fatal(1,"motion metadata alignment");
    if(modeq[2]!=6 && od!==rgbq[2])$fatal(1,"motion overlay leaked into original/other modes");
    if(od!==expectedq[2])$fatal(1,"motion raster mismatch frame%0d got%h want%h",frame,od,expectedq[2]);
    if(FULL&&frame==4&&ppm!=0)for(ml=0;ml<4;ml++)begin
     ep=od[95-ml*24-:24];$fwrite(ppm,"%c%c%c",ep[23:16],ep[15:8],ep[7:0]);end
    raster_checks++;
   end
  end
 end
 task idle(input integer clocks);begin @(negedge clk);u=0;v=0;l=0;repeat(clocks-1)@(negedge clk);end endtask
 task settle_and_check(input integer f);
  integer j,cycles;
  begin
   cycles=0;
   while(!dut.pending_result && cycles<40000)begin idle(1);cycles++;end
   if(!dut.pending_result)$fatal(1,"processing failed to finish frame%0d state%0d",f,dut.state);
   if(dut.pending_valid!==meta[f][60] || dut.pending_global!==meta[f][56] || dut.pending_count!==meta[f][55:44])
    $fatal(1,"frame%0d metadata got valid%0d global%0d count%0d expected%h",f,dut.pending_valid,dut.pending_global,dut.pending_count,meta[f]);
   if(!dut.pending_global && dut.best_count!==meta[f][43:32])$fatal(1,"largest component frame%0d got%0d wanted%0d",f,dut.best_count,meta[f][43:32]);
   if(!dut.pending_global && dut.best_count!=0 && {2'b0,dut.bestx0,2'b0,dut.bestx1,3'b0,dut.besty0,3'b0,dut.besty1}!==meta[f][31:0])
    $fatal(1,"largest component geometry frame%0d",f);
   // Commit while invalid; inspect every cell independently of RAM layout.
   if(!AUTO)begin
   manual=1;@(negedge clk);manual_sof=1;@(negedge clk);manual_sof=0;
   if(valid!==meta[f][60] || global_change!==(meta[f][60]&&meta[f][56]))$fatal(1,"published metadata frame%0d",f);
   for(j=0;j<N;j++)begin
    manual_addr=j;@(negedge clk);#1;
    if(map_bit!==masks[f*N+j])$fatal(1,"map cell mismatch frame%0d cell%0d got%b expected%b",f,j,map_bit,masks[f*N+j]);
    checks++;
   end
   if(f==2 && visible)$fatal(1,"single-frame change should not immediately confirm a box");
   if((f==3||f==4)&&(!visible||x0!=3||x1!=6||y0!=2||y1!=4))$fatal(1,"stable major box not confirmed frame%0d",f);
   if(f==13 && visible)$fatal(1,"stationary stale box did not expire");
   if(global_change&&visible)$fatal(1,"global change created a giant box");
   manual=0;end
   settled++;
  end
 endtask
 initial begin
  if(FULL)begin
   $readmemh("motion_720_samples.hex",samples);$readmemh("motion_720_mask.hex",masks);$readmemh("motion_720_meta.hex",meta);
  end else begin
   $readmemh("motion_small_samples.hex",samples);$readmemh("motion_small_mask.hex",masks);$readmemh("motion_small_meta.hex",meta);
  end
  repeat(5)@(negedge clk);rst=1;idle(5);
  for(frame=0;frame<FRAMES;frame++)begin
   // Alternate early and coincident SOF, valid bubbles, and original-mode bypass.
   mode=frame==4?6:frame%3==1?0:6;
   if(FULL&&frame==4)begin ppm=$fopen("../reports/motion_rtl_preview.ppm","wb");$fwrite(ppm,"P6\n1280 720\n255\n");end
   if(frame%2==0)begin @(negedge clk);u=1;v=0;l=0;idle(7);end
   for(y=0;y<H;y++)for(x=0;x<W;x+=4)begin
    @(negedge clk);u=frame%2==1&&x==0&&y==0;v=1;l=x==W-4;
    idx=(y/TH)*GW+x/TW;cell_samples=samples[frame*N+idx];
    data={4{cell_samples[383:360]}};
    if((y%TH==TH/4 || y%TH==3*TH/4)&&((x/4)%(TW/4)==(TW/4)/4 || (x/4)%(TW/4)==3*(TW/4)/4))begin
     sample_index=(y%TH==TH/4?0:8)+((x/4)%(TW/4)==(TW/4)/4?0:4);
     for(lane=0;lane<4;lane++)data[95-lane*24-:24]=cell_samples[383-(sample_index+lane)*24-:24];
    end
    if(x/4%37==11)idle(1);
   end
   idle(8);if(FULL&&frame==4)begin $fclose(ppm);ppm=0;end
   settle_and_check(frame);
  end
  // Interrupted/malformed frame must invalidate the reference. A subsequent
  // complete frame rebuilds it before motion can be reported again.
  @(negedge clk);u=1;v=0;l=0;idle(2);
  @(negedge clk);v=1;l=1;idle(3);
  if(valid || dut.baseline)$fatal(1,"malformed frame retained valid motion reference");
  completed=1;$display("PASS motion regions: full720=%0d autoSOF=%0d frames=%0d mapchecks=%0d rasterbeats=%0d; 16 samples, independent BFS oracle, isolated rejection, largest separated region, confirmation/hold/expiry, global suppression, exact bypass, early SOF/bubbles/protocol rejection",FULL,AUTO,settled,checks,raster_checks);$finish;
 end
 initial begin #200000000;$fatal(1,"motion test watchdog");end
endmodule
