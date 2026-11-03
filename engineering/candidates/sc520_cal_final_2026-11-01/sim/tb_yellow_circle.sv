`timescale 1ns/1ps
module tb_yellow_circle;
  localparam integer IW=256,IH=192;
  reg clk=0; always #5 clk=~clk;
  reg rst_n=0,user=0,valid=0,enable=0;
  reg [95:0] data=0;
  reg [7:0] margin=32;
  wire result_valid,result_overflow;
  wire [255:0] boxes;
  wire [2:0] shown;
  wire [7:0] total,result_margin;
  wire [15:0] result_frame,capture_frame,skipped_frames;
  integer x,y,beat_x,tile_x,tile_y,cycles;
  reg [23:0] pixel;

  shape_detector_96 #(.IMG_WIDTH(IW),.IMG_HEIGHT(IH),.QLOG(10)) dut(
    .clk(clk),.rst_n(rst_n),.user(user),.valid(valid),.enable(enable),.data(data),.margin(margin),
    .result_valid(result_valid),.result_overflow(result_overflow),.result_boxes(boxes),
    .result_shown(shown),.result_total(total),.result_margin(result_margin),
    .result_frame(result_frame),.capture_frame(capture_frame),.skipped_frames(skipped_frames));


  initial begin
    repeat(4) @(posedge clk);
    rst_n=1;
    @(negedge clk); enable=1;
    for(y=0;y<IH;y=y+1)begin
      tile_y=y/4;
      for(beat_x=0;beat_x<IW/4;beat_x=beat_x+1)begin
        tile_x=beat_x;
        if((tile_x-32)*(tile_x-32)+(tile_y-24)*(tile_y-24)<=25)
          pixel={8'd230,8'd220,8'd20};
        else pixel=24'd0;
        @(negedge clk);
        user=(y==0 && beat_x==0);
        valid=1;
        data={pixel,pixel,pixel,pixel};
      end
    end
    @(negedge clk); user=0;valid=0;data=0;
    cycles=0;
    while(!result_valid && cycles<1000000)begin @(posedge clk);cycles=cycles+1;end
    if(!result_valid)begin $display("FAIL yellow circle timeout");$fatal(1);end
    if(result_overflow || shown!=1 || total!=1 || boxes[47:46]!=2'd1 || boxes[45:44]!=2'd0)begin
      $display("FAIL yellow circle: overflow=%b shown=%0d total=%0d shape=%0d color=%0d area=%0d bounds=(%0d,%0d)-(%0d,%0d)",
        result_overflow,shown,total,boxes[47:46],boxes[45:44],boxes[63:48],boxes[10:0],boxes[32:22],boxes[21:11],boxes[43:33]);
      $fatal(1);
    end
    $display("PASS yellow circle: shape=CIRCLE color=YELLOW cells=%0d cycles=%0d",boxes[63:48],cycles);
    $finish;
  end
endmodule
