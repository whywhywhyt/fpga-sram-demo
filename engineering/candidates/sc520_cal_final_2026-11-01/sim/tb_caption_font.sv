`timescale 1ns/1ps
module tb_caption_font;
 reg clk=0;always #5 clk=~clk;
 reg [7:0] code=0;reg [3:0] row=0;
 wire [15:0] combinational,full,compact;
 presentation_font16 comb(.code(code),.row(row),.bits(combinational));
 presentation_font16_sync sync(.clk(clk),.code(code),.row(row),.bits(full));
 presentation_font16_sync #(.BANK(1)) compact_font(.clk(clk),.code(code),.row(row),.bits(compact));
 reg [15:0] reference[0:4095];reg [15:0] expected,small_expected;
 integer c,r,checked=0,completed=0;
 function is_compact(input integer ch);
  begin case(ch)
   188,189,190,191,129,154,196,180,192,144,193,194,195:is_compact=1;
   default:is_compact=0;
  endcase end
 endfunction
 initial begin
  $readmemh("caption_font_reference.hex",reference);
  for(c=0;c<256;c++)for(r=0;r<16;r++)begin
   @(negedge clk);code=c;row=r;#1;
   expected=c>=128?reference[c*16+r]:combinational;
   small_expected=c<128?expected:is_compact(c)?expected:0;
   if(combinational!==expected)$fatal(1,"complete font mismatch code%0d row%0d got%h expected%h",c,r,combinational,expected);
   @(posedge clk);#1;
   if(full!==expected || compact!==small_expected)$fatal(1,"clocked font alignment code%0d row%0d full%h/%h compact%h/%h",c,r,full,expected,compact,small_expected);
   checked++;
  end
  if(checked!=4096)$fatal(1,"font coverage incomplete");
  completed=1;$display("PASS caption font: all 4096 code/row addresses, complete independent font reference, both synchronous banks and combinational HDMI readers");$finish;
 end
endmodule
