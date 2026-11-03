`timescale 1ns/1ps
module tb_cartoon;
 parameter integer WIDTH=64,HEIGHT=48,FRAMES=7;
 parameter INPUT_FILE="small_rgb.hex",EXPECTED_FILE="small_cartoon.hex";
 localparam integer GROUPS=WIDTH/4,N=GROUPS*HEIGHT*FRAMES;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,u=0,v=0,l=0;reg[95:0]d=0;
 reg[10:0]th=96;reg[1:0]level=1;
 wire[95:0]edge_rgb,cartoon,enhance,reference_color;
 wire ev,eu,el;
 prewitt_detect_96 #(.IMG_WIDTH(WIDTH),.IMG_HEIGHT(HEIGHT)) edge_stage(
  .I_clk(clk),.I_rst_n(rst),.I_tlast(l),.I_tuser(u),.I_tdata(d),.I_tvalid(v),.I_tready(1'b1),
  .threshold(th),.O_tdata(edge_rgb),.O_tvalid(ev),.O_tuser(eu),.O_tlast(el),.O_tready());
 natural_enhance_96 #(.IMG_WIDTH(WIDTH),.IMG_HEIGHT(HEIGHT)) dut(
  .clk(clk),.rst_n(rst),.user(u),.valid(v),.data(d),.level(level),
  .edge_mask({edge_rgb[95],edge_rgb[71],edge_rgb[47],edge_rgb[23]}),.color(enhance),.cartoon_color(cartoon));
 natural_enhance_reference #(.IMG_WIDTH(WIDTH),.IMG_HEIGHT(HEIGHT)) old(
  .clk(clk),.rst_n(rst),.user(u),.valid(v),.data(d),.level(level),
  .edge_mask({edge_rgb[95],edge_rgb[71],edge_rgb[47],edge_rgb[23]}),.color(reference_color));
 reg[95:0]input_words[0:N-1],expected_words[0:N-1];
 reg[2:0]vq=0,uq=0,lq=0;reg[95:0]q[0:2];
 integer accepted=0,checked=0,epoch=0,black=0,colored=0,completed=0;
 always @(posedge clk)begin:monitor
  integer i;
  if(!rst)begin vq=0;uq=0;lq=0;accepted=0;for(i=0;i<3;i++)q[i]=0;end
  else begin
   for(i=2;i>0;i--)q[i]=q[i-1];
   q[0]=v?expected_words[accepted]:0;
   if(v)accepted++;
   vq={vq[1:0],v};uq={uq[1:0],u};lq={lq[1:0],l};
  end
  #1;
  if(rst)begin
   if({ev,eu,el}!=={vq[2],uq[2],lq[2]})$fatal(1,"Prewitt/cartoon framing not three cycles");
   if(enhance!==reference_color)$fatal(1,"existing enhancement changed, level=%0d",level);
   if(vq[2])begin
    if(cartoon!==q[2])$fatal(1,"cartoon oracle epoch%0d group%0d got%h expected%h",epoch,checked,cartoon,q[2]);
    if(cartoon==0)black++;else colored++;
    checked++;
   end
  end
 end
 task idle(input integer n);begin @(negedge clk);v=0;u=0;l=0;repeat(n-1)@(negedge clk);end endtask
 integer f,y,x,idx,rounds;
 initial begin
  $readmemh(INPUT_FILE,input_words);$readmemh(EXPECTED_FILE,expected_words);
  rounds=WIDTH==64?2:1;
  for(epoch=0;epoch<rounds;epoch++)begin
   rst=0;idle(6);rst=1;idle(4);idx=0;
   for(f=0;f<FRAMES;f++)begin
    case(f)4:th=32;5:th=160;6:th=248;default:th=96;endcase
    level=1+f%3;
    @(negedge clk);u=1;v=0;l=0;idle(3);
    for(y=0;y<HEIGHT;y++)begin
     for(x=0;x<GROUPS;x++)begin
      @(negedge clk);v=1;u=0;l=x==GROUPS-1;d=input_words[idx];idx++;
      if((idx%19)==5)idle(1);
      if((idx%53)==9)idle(3);
     end
     idle(7);
    end
    idle(12);
   end
   idle(8);
   if(accepted!=N)$fatal(1,"input count");
  end
  if(checked!=N*rounds||black==0||colored==0)$fatal(1,"coverage");
  completed=1;$display("PASS cartoon: %0d exact pixels, %0d epochs, varied edge thresholds and enhancement levels, random bubbles, row/frame boundaries, three-cycle alignment, old enhancement bit-exact",checked*4,rounds);$finish;
 end
 initial begin #40000000;$fatal(1,"cartoon watchdog");end
endmodule
