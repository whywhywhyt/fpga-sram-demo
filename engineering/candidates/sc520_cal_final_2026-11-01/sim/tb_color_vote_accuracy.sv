`timescale 1ns/1ps
module tb_color_vote_accuracy;
  localparam integer IW=16,IH=4;
  reg clk=0;always #5 clk=~clk;
  reg rst_n=0,user=0,valid=0,enable=0;
  reg [95:0] data=0;
  reg [7:0] margin=32;
  wire tile_valid,frame_complete;
  wire [15:0] tile_addr,tile_frame,capture_frame;
  wire [2:0] tile_color;
  wire [7:0] tile_margin;
  reg [2:0] observed[0:3];
  integer row,beat,lane,addr;

  shape_color_vote_96 #(.IMG_WIDTH(IW),.IMG_HEIGHT(IH)) dut(
    .clk(clk),.rst_n(rst_n),.user(user),.valid(valid),.enable(enable),.data(data),.margin(margin),
    .tile_valid(tile_valid),.frame_complete(frame_complete),.tile_addr(tile_addr),.tile_frame(tile_frame),
    .tile_color(tile_color),.tile_margin(tile_margin),.capture_frame(capture_frame));

  function [23:0] sample_pixel;
    input integer r,b,l;
    begin
      case(b)
        0: sample_pixel=(r<2)?24'hd02020:24'h000000; // Exactly 8 red votes: reject.
        1: sample_pixel=(r<2 || (r==2 && l==0))?24'h20dc20:24'h000000; // 9 green votes: accept.
        2: sample_pixel=24'h2050dc;
        default: sample_pixel=24'he6dc14;
      endcase
    end
  endfunction

  always @(posedge clk)if(tile_valid)observed[tile_addr]=tile_color;

  initial begin
    for(addr=0;addr<4;addr=addr+1)observed[addr]=3'bxxx;
    repeat(4)@(posedge clk);rst_n=1;enable=1;
    for(row=0;row<IH;row=row+1)for(beat=0;beat<IW/4;beat=beat+1)begin
      @(negedge clk);user=(row==0 && beat==0);valid=1;
      data={sample_pixel(row,beat,0),sample_pixel(row,beat,1),sample_pixel(row,beat,2),sample_pixel(row,beat,3)};
    end
    @(negedge clk);user=0;valid=0;data=0;
    repeat(4)@(posedge clk);
    if(observed[0]!==0 || observed[1]!==2 || observed[2]!==3 || observed[3]!==4)
      $fatal(1,"color vote threshold mismatch red8=%0d green9=%0d blue=%0d yellow=%0d",observed[0],observed[1],observed[2],observed[3]);
    $display("PASS color votes: 8/16 rejected, 9/16 accepted; blue/yellow classes retained");
    $finish;
  end
endmodule
