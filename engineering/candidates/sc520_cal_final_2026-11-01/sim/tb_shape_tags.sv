`timescale 1ns/1ps
module tb_shape_tags;
  tb_shape_overlay raster();
  reg [1:0] shape;
  reg [1:0] color;
  reg [4:0] position;
  reg [15:0] x_bcd,y_bcd;
  wire [7:0] code;
  wire [4:0] length;
  integer failures=0;
  integer i;
  reg [7:0] expected[0:23];

  shape_tag_char dut(.color(color),.shape(shape),.position(position),.x_bcd(x_bcd),.y_bcd(y_bcd),.code(code),.length(length));

  task check_string;
    input integer count;
    begin
      for(i=0;i<count;i=i+1)begin
        position=i;#1;
        if(code!==expected[i])begin
          $display("FAIL tag shape=%0d pos=%0d expected=%c got=%c",shape,i,expected[i],code);
          failures=failures+1;
        end
      end
      if(length!==count)$fatal(1,"tag length mismatch shape=%0d got=%0d expected=%0d",shape,length,count);
    end
  endtask

  initial begin
    // Match the reference style: color, shape and center without padded zeros.
    color=1;shape=1;x_bcd=16'h0120;y_bcd=16'h0080;
    expected[0]="R";expected[1]="E";expected[2]="D";expected[3]=" ";
    expected[4]="C";expected[5]="I";expected[6]="R";expected[7]="C";expected[8]="L";expected[9]="E";
    expected[10]=" ";expected[11]="(";expected[12]="1";expected[13]="2";expected[14]="0";
    expected[15]=",";expected[16]="8";expected[17]="0";expected[18]=")";
    check_string(19);
    color=2;shape=2;x_bcd=16'h0007;y_bcd=16'h0008;
    expected[0]="G";expected[1]="R";expected[2]="E";expected[3]="E";expected[4]="N";expected[5]=" ";
    expected[6]="T";expected[7]="R";expected[8]="I";expected[9]="A";expected[10]="N";expected[11]="G";expected[12]="L";expected[13]="E";
    expected[14]=" ";expected[15]="(";expected[16]="7";expected[17]=",";expected[18]="8";expected[19]=")";
    check_string(20);
    color=0;shape=3;x_bcd=16'h1280;y_bcd=16'h0720;
    expected[0]="Y";expected[1]="E";expected[2]="L";expected[3]="L";expected[4]="O";expected[5]="W";expected[6]=" ";
    expected[7]="R";expected[8]="E";expected[9]="C";expected[10]="T";expected[11]=" ";expected[12]="(";
    expected[13]="1";expected[14]="2";expected[15]="8";expected[16]="0";expected[17]=",";
    expected[18]="7";expected[19]="2";expected[20]="0";expected[21]=")";
    check_string(22);
    if(failures==0)$display("PASS shape tags: color/shape labels and compact center coordinates");
    else $fatal(1,"shape tag failures=%0d",failures);
    // The raster subtest finishes after frame and atomic-publication checks.
  end
endmodule
