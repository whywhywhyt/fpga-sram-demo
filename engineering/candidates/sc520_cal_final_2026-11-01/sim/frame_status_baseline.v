// Fixed Simplified Chinese captions. Two stages and frame-atomic controls,
// identical to the prior status overlay. Algorithms/keys are unchanged.
// No block RAM/DSP font. Four pixels share a pair of doubled bitmap dots.
module frame_status_baseline #(parameter integer IMG_WIDTH=1280, IMG_HEIGHT=720)(
 input wire clk,rst_n,
 input wire I_tlast,I_tuser,I_tvalid,
 input wire [95:0] I_tdata,
 input wire [2:0] I_mode,
 input wire [7:0] I_threshold,
 input wire [172:0] I_awb_diag,
 output reg O_tlast,O_tuser,O_tvalid,
 output reg [95:0] O_tdata
);
 reg [10:0] x,y;
 wire [10:0] px=I_tuser?11'd0:x,py=I_tuser?11'd0:y;
 reg [2:0] frame_mode;
 reg [7:0] frame_threshold;
 wire [2:0] mode=I_tuser?I_mode:frame_mode;
 wire [7:0] threshold=I_tuser?I_threshold:frame_threshold;
 wire diagnostic_area=(px>=192 && px<672 && py>=100 && py<148);
 wire panel=(px>=184 && px<520 && py>=24 && py<92) || diagnostic_area;
 reg [172:0] diagnostic_frame;
 wire [172:0] diagnostic=I_tuser?I_awb_diag:diagnostic_frame;
 wire [15:0] diag_r=diagnostic[171:156],diag_b=diagnostic[155:140],diag_u=diagnostic[139:124];
 wire [19:0] diag_n=diagnostic[121:102];
 wire [15:0] diag_f=diagnostic[15:0];
 wire [27:0] diag_sr=diagnostic[101:74],diag_sg=diagnostic[73:46],diag_sb=diagnostic[45:18];
 wire [5:0] diagnostic_y=py-11'd100;
 wire [4:0] diagnostic_pos=(px-11'd192)>>4;
 reg [7:0] diagnostic_code;
 reg [3:0] diagnostic_nibble;
 function [7:0] hex_code;
  input [3:0] nibble;
  begin hex_code=nibble<10?8'd48+nibble:8'd55+nibble;end
 endfunction
 always @(*)begin
  diagnostic_code=8'd32;diagnostic_nibble=0;
  case(diagnostic_y[5:4])
   0:begin
    case(diagnostic_pos)
     0:diagnostic_code="W";1:diagnostic_code="B";3:diagnostic_code="R";
     10:diagnostic_code="B";17:diagnostic_code="A";
     19:diagnostic_code=diagnostic[172]?"1":"0";
     21:diagnostic_code="U";
     default:begin
      if(diagnostic_pos>=5 && diagnostic_pos<=8)begin
       diagnostic_nibble=diag_r[(8-diagnostic_pos)*4+:4];
       diagnostic_code=hex_code(diagnostic_nibble);
      end else if(diagnostic_pos>=12 && diagnostic_pos<=15)begin
       diagnostic_nibble=diag_b[(15-diagnostic_pos)*4+:4];
       diagnostic_code=hex_code(diagnostic_nibble);
      end else if(diagnostic_pos>=23 && diagnostic_pos<=26)begin
       diagnostic_nibble=diag_u[(26-diagnostic_pos)*4+:4];
       diagnostic_code=hex_code(diagnostic_nibble);
      end
     end
    endcase
   end
   1:begin
    case(diagnostic_pos)
     0:diagnostic_code="N";9:diagnostic_code="F";
     2:diagnostic_code=hex_code({2'b0,diagnostic[123:122]});
     11:diagnostic_code=hex_code({2'b0,diagnostic[17:16]});
     default:begin
      if(diagnostic_pos>=3 && diagnostic_pos<=7)begin
       diagnostic_nibble=diag_n[(7-diagnostic_pos)*4+:4];
       diagnostic_code=hex_code(diagnostic_nibble);
      end else if(diagnostic_pos>=12 && diagnostic_pos<=15)begin
       diagnostic_nibble=diag_f[(15-diagnostic_pos)*4+:4];
       diagnostic_code=hex_code(diagnostic_nibble);
      end
     end
    endcase
   end
   2:begin
    case(diagnostic_pos)
     0:diagnostic_code="R";10:diagnostic_code="G";20:diagnostic_code="B";
     default:begin
      if(diagnostic_pos>=2 && diagnostic_pos<=8)begin
       diagnostic_nibble=diag_sr[(8-diagnostic_pos)*4+:4];
       diagnostic_code=hex_code(diagnostic_nibble);
      end else if(diagnostic_pos>=12 && diagnostic_pos<=18)begin
       diagnostic_nibble=diag_sg[(18-diagnostic_pos)*4+:4];
       diagnostic_code=hex_code(diagnostic_nibble);
      end else if(diagnostic_pos>=22 && diagnostic_pos<=28)begin
       diagnostic_nibble=diag_sb[(28-diagnostic_pos)*4+:4];
       diagnostic_code=hex_code(diagnostic_nibble);
      end
     end
    endcase
   end
  endcase
 end
 wire text_area=(px>=192 && px<512 &&
                ((py>=28 && py<52)||(py>=60 && py<84)));
 wire [10:0] tx=px-11'd192,ty=py-11'd28;
 wire [3:0] pos=tx[8:5];
 wire line1=ty[5];
 reg [5:0] glyph;
 wire [1:0] han_pair;
 status_zh_glyph font(.glyph(glyph),.row(ty[4:1]),.pair(tx[4:2]),.dots(han_pair));
 reg [3:0] hundreds,tens,ones;
 reg [7:0] remainder;
 reg [3:0] digit;
 always @(*) begin
  hundreds=threshold/100;
  remainder=threshold-hundreds*100;
  tens=remainder/10;
  ones=remainder-tens*10;
  digit=tx<112?hundreds:tx<128?tens:ones;
 end
 wire [10:0] digit_y=py-11'd64;
 wire [4:0] digit_bits;
 osd_font5x7 digits(.code(diagnostic_area?diagnostic_code:{4'h3,digit}),
                    .row(diagnostic_area?diagnostic_y[3:1]:digit_y[3:1]),.bits(digit_bits));
 reg [1:0] ascii_pair;
 always @(*) begin
  case(tx[3:2])
   0:ascii_pair=digit_bits[4:3];
   1:ascii_pair=digit_bits[2:1];
   2:ascii_pair={digit_bits[0],1'b0};
   default:ascii_pair=0;
  endcase
 end
 wire digit_area=(mode==2 || mode==3 || mode>=5) &&
                 px>=288 && px<336 && py>=64 && py<78;
 wire [1:0] ink_pair=(diagnostic_area||digit_area)?ascii_pair:text_area?han_pair:2'b00;
 reg [3:0] text_d;
 reg panel_d,valid_d,user_d,last_d;
 reg [95:0] base_d;
 integer i;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   x<=0;y<=0;frame_mode<=3;frame_threshold<=96;diagnostic_frame<=0;
   base_d<=0;text_d<=0;panel_d<=0;valid_d<=0;user_d<=0;last_d<=0;
   O_tdata<=0;O_tlast<=0;O_tuser<=0;O_tvalid<=0;
  end else begin
   if(I_tuser)begin x<=0;y<=0;frame_mode<=I_mode;frame_threshold<=I_threshold;diagnostic_frame<=I_awb_diag;end
   if(I_tvalid)begin
    x<=(px==IMG_WIDTH-4)?11'd0:px+11'd4;
    y<=(px==IMG_WIDTH-4)?((py==IMG_HEIGHT-1)?11'd0:py+1'b1):py;
   end
   base_d<=I_tdata;panel_d<=panel;
   valid_d<=I_tvalid;user_d<=I_tuser;last_d<=I_tvalid && px==IMG_WIDTH-4;
   text_d<=I_tvalid?{ink_pair[1],ink_pair[1],ink_pair[0],ink_pair[0]}:4'd0;
   O_tvalid<=valid_d;O_tuser<=user_d;O_tlast<=last_d;
   for(i=0;i<4;i=i+1)
    O_tdata[95-i*24 -:24]<=!valid_d?24'd0:text_d[3-i]?24'h00e6ff:
                         panel_d?24'h101820:base_d[95-i*24 -:24];
  end
 end
 always @(*) begin
  glyph=0;
  if(!line1)begin
   case(pos)
    0:glyph=6'd1;
    1:glyph=6'd2;
    3:case(mode)
     3'd0:glyph=6'd3; // 彩
     3'd1:glyph=6'd7; // 灰
     3'd2:glyph=6'd10; // 二
     3'd3:glyph=6'd12; // 边
     3'd4:glyph=6'd6; // 图
     3'd5:glyph=6'd18; // 颜
     default:glyph=0;
    endcase
    4:case(mode)
     3'd0:glyph=6'd4; // 色
     3'd1:glyph=6'd8; // 度
     3'd2:glyph=6'd11; // 值
     3'd3:glyph=6'd13; // 缘
     3'd4:glyph=6'd9; // 像
     3'd5:glyph=6'd4; // 色
     default:glyph=0;
    endcase
    5:case(mode)
     3'd0:glyph=6'd5; // 原
     3'd1:glyph=6'd6; // 图
     3'd2:glyph=6'd6; // 图
     3'd3:glyph=6'd14; // 检
     3'd4:glyph=6'd16; // 增
     3'd5:glyph=6'd19; // 形
     default:glyph=0;
    endcase
    6:case(mode)
     3'd0:glyph=6'd6; // 图
     3'd1:glyph=6'd9; // 像
     3'd2:glyph=6'd9; // 像
     3'd3:glyph=6'd15; // 测
     3'd4:glyph=6'd17; // 强
     3'd5:glyph=6'd20; // 状
     default:glyph=0;
    endcase
    7:case(mode)
     3'd5:glyph=6'd21; // 识
     default:glyph=0;
    endcase
    8:case(mode)
     3'd5:glyph=6'd22; // 别
     default:glyph=0;
    endcase
    default:glyph=0;
   endcase
  end else begin
   case(pos)
    0:case(mode)
     3'd2:glyph=6'd23;
     3'd3:glyph=6'd23;
     3'd4:glyph=6'd17;
     3'd5:glyph=6'd4;
     default:glyph=0;
    endcase
    1:case(mode)
     3'd2:glyph=6'd11;
     3'd3:glyph=6'd11;
     3'd4:glyph=6'd8;
     3'd5:glyph=6'd24;
     default:glyph=0;
    endcase
    3:if(mode==4)begin
     case(threshold[4:3])
      1:glyph=6'd25;
      2:glyph=6'd26;
      default:glyph=6'd27;
     endcase
    end
    default:glyph=0;
   endcase
  end
 end
endmodule

// Baked 12x12 glyph dots generated locally from SimSun at native size.
// Glyphs are doubled to 24x24 on screen. No .ttc/font library is shipped.
