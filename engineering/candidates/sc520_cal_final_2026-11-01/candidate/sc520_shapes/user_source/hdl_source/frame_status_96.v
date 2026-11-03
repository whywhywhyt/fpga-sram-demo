// Fixed Simplified Chinese captions. Two stages and frame-atomic controls,
// preserved from the prior overlay. Only neutral diagnostic strips are added.
// No block RAM/DSP font. Four pixels share a pair of doubled bitmap dots.
module frame_status_96 #(parameter integer IMG_WIDTH=1280, IMG_HEIGHT=720)(
 input wire clk,rst_n,
 input wire I_tlast,I_tuser,I_tvalid,
 input wire [95:0] I_tdata,
 input wire [2:0] I_mode,
 input wire [7:0] I_threshold,
 input wire [172:0] I_awb_diag,
 input wire [159:0] I_spatial_diag,
 output reg O_tlast,O_tuser,O_tvalid,
 output reg [95:0] O_tdata
);
 reg [10:0] x,y;
 wire [10:0] px=I_tuser?11'd0:x,py=I_tuser?11'd0:y;
 reg [2:0] frame_mode;
 reg [7:0] frame_threshold;
 wire [2:0] mode=I_tuser?I_mode:frame_mode;
 wire [7:0] threshold=I_tuser?I_threshold:frame_threshold;
 reg [159:0] spatial_frame;
 wire [159:0] spatial_view=I_tuser?I_spatial_diag:spatial_frame;
 wire spatial_present=(spatial_view[2:0]===3'd1)||(spatial_view[2:0]===3'd2)||
     (spatial_view[2:0]===3'd3)||(spatial_view[2:0]===3'd4)||(spatial_view[2:0]===3'd5);
 wire spatial_area=spatial_present && px>=16 && px<528 && py>=600 && py<664;
 wire diagnostic_area=(px>=192 && px<672 && py>=100 && py<148);
 wire panel=(px>=184 && px<520 && py>=24 && py<92) || diagnostic_area || spatial_area;
 // Known neutral references bypass camera processing, then travel through the
 // same packing/DDR/HDMI path as the picture. Full-width samples distinguish
 // camera-side spatial cast from downstream or display-side spatial cast.
 wire reference_mid=px>=16 && px<1264 && py>=160 && py<176;
 wire reference_light=px>=16 && px<1264 && py>=184 && py<200;
 reg [1:0] reference_d;
 reg [172:0] diagnostic_frame;
 wire [172:0] diagnostic=I_tuser?I_awb_diag:diagnostic_frame;
 wire [15:0] diag_r=diagnostic[171:156],diag_b=diagnostic[155:140],diag_u=diagnostic[139:124];
 wire [19:0] diag_n=diagnostic[121:102];
 wire [15:0] diag_f=diagnostic[15:0];
 wire [27:0] diag_sr=diagnostic[101:74],diag_sg=diagnostic[73:46],diag_sb=diagnostic[45:18];
 wire [5:0] diagnostic_y=py-11'd100;
 wire [4:0] diagnostic_pos=(px-11'd192)>>4;
 // Below the drawing ROI, outside the final HDMI latency/Logo/preview panels.
 wire [5:0] spatial_y=py-11'd600;
 wire [1:0] spatial_line=spatial_y[5:4];
 wire [4:0] spatial_pos=(px-11'd16)>>4;
 wire [15:0] local_r=spatial_line==1?spatial_view[23:8]:spatial_line==2?spatial_view[55:40]:spatial_view[87:72];
 wire [15:0] local_b=spatial_line==1?spatial_view[39:24]:spatial_line==2?spatial_view[71:56]:spatial_view[103:88];
 wire [15:0] local_n=spatial_line==1?spatial_view[119:104]:spatial_line==2?spatial_view[135:120]:spatial_view[151:136];
 reg [7:0] spatial_code;
 always @(*)begin
   spatial_code=32;
   if(spatial_line==0)begin
     case(spatial_pos)
      0:spatial_code="C";1:spatial_code="A";2:spatial_code="L";
      4:case(spatial_view[2:0])
         1:spatial_code="C";2:spatial_code="W";3:spatial_code="O";4:spatial_code="-";5:spatial_code="F";
         default:spatial_code="-";endcase
      5:case(spatial_view[2:0])
         1:spatial_code="A";2:spatial_code="O";3:spatial_code="N";4:spatial_code=32;5:spatial_code="A";
         default:spatial_code=32;endcase
      6:case(spatial_view[2:0])
         1:spatial_code="P";2:spatial_code="R";5:spatial_code="I";
         default:spatial_code=32;endcase
      7:case(spatial_view[2:0])
         1:spatial_code="T";2:spatial_code="K";5:spatial_code="L";
         default:spatial_code=32;endcase
      10:spatial_code="U";
      12:spatial_code=hex_code(spatial_view[159:156]);13:spatial_code=hex_code(spatial_view[155:152]);
      default:spatial_code=32;
     endcase
   end else begin
     case(spatial_pos)
      0:spatial_code=spatial_line==1?"L":spatial_line==2?"C":"R";
      2:spatial_code="R";9:spatial_code="B";16:spatial_code="N";
      default:begin
       if(spatial_pos>=4 && spatial_pos<8)spatial_code=hex_code(local_r[(7-spatial_pos)*4+:4]);
       else if(spatial_pos>=11 && spatial_pos<15)spatial_code=hex_code(local_b[(14-spatial_pos)*4+:4]);
       else if(spatial_pos>=18 && spatial_pos<22)spatial_code=hex_code(local_n[(21-spatial_pos)*4+:4]);
      end
     endcase
   end
 end
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
 osd_font5x7 digits(.code(spatial_area?spatial_code:diagnostic_area?diagnostic_code:{4'h3,digit}),
                    .row(spatial_area?spatial_y[3:1]:diagnostic_area?diagnostic_y[3:1]:digit_y[3:1]),.bits(digit_bits));
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
 wire [1:0] ink_pair=(spatial_area||diagnostic_area||digit_area)?ascii_pair:text_area?han_pair:2'b00;
 reg [3:0] text_d;
 reg panel_d,valid_d,user_d,last_d;
 reg [95:0] base_d;
 integer i;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   x<=0;y<=0;frame_mode<=3;frame_threshold<=96;diagnostic_frame<=0;spatial_frame<=0;
   base_d<=0;text_d<=0;panel_d<=0;reference_d<=0;valid_d<=0;user_d<=0;last_d<=0;
   O_tdata<=0;O_tlast<=0;O_tuser<=0;O_tvalid<=0;
  end else begin
   if(I_tuser)begin x<=0;y<=0;frame_mode<=I_mode;frame_threshold<=I_threshold;diagnostic_frame<=I_awb_diag;spatial_frame<=I_spatial_diag;end
   if(I_tvalid)begin
    x<=(px==IMG_WIDTH-4)?11'd0:px+11'd4;
    y<=(px==IMG_WIDTH-4)?((py==IMG_HEIGHT-1)?11'd0:py+1'b1):py;
   end
   base_d<=I_tdata;panel_d<=panel;
   reference_d<={reference_light,reference_mid};
   valid_d<=I_tvalid;user_d<=I_tuser;last_d<=I_tvalid && px==IMG_WIDTH-4;
   text_d<=I_tvalid?{ink_pair[1],ink_pair[1],ink_pair[0],ink_pair[0]}:4'd0;
   O_tvalid<=valid_d;O_tuser<=user_d;O_tlast<=last_d;
   for(i=0;i<4;i=i+1)
    O_tdata[95-i*24 -:24]<=!valid_d?24'd0:reference_d[1]?24'hc0c0c0:
                         reference_d[0]?24'h808080:text_d[3-i]?24'h00e6ff:
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
module status_zh_glyph(input wire [5:0] glyph,input wire [3:0] row,
 input wire [2:0] pair,output wire [1:0] dots);
 reg [11:0] bitmap;
 always @(*) begin
  case({glyph,row})
   // 模
   10'd16:bitmap=12'h228;
   10'd17:bitmap=12'h2fe;
   10'd18:bitmap=12'h228;
   10'd19:bitmap=12'hf7c;
   10'd20:bitmap=12'h244;
   10'd21:bitmap=12'h67c;
   10'd22:bitmap=12'h744;
   10'd23:bitmap=12'ha7c;
   10'd24:bitmap=12'h210;
   10'd25:bitmap=12'h2fe;
   10'd26:bitmap=12'h228;
   10'd27:bitmap=12'h2c6;
   // 式
   10'd32:bitmap=12'h014;
   10'd33:bitmap=12'h012;
   10'd34:bitmap=12'h010;
   10'd35:bitmap=12'hffe;
   10'd36:bitmap=12'h010;
   10'd37:bitmap=12'h010;
   10'd38:bitmap=12'h7d0;
   10'd39:bitmap=12'h110;
   10'd40:bitmap=12'h108;
   10'd41:bitmap=12'h10a;
   10'd42:bitmap=12'h1e6;
   10'd43:bitmap=12'he02;
   // 彩
   10'd48:bitmap=12'h1c4;
   10'd49:bitmap=12'he04;
   10'd50:bitmap=12'h248;
   10'd51:bitmap=12'h952;
   10'd52:bitmap=12'h482;
   10'd53:bitmap=12'h104;
   10'd54:bitmap=12'hfc8;
   10'd55:bitmap=12'h110;
   10'd56:bitmap=12'h382;
   10'd57:bitmap=12'h544;
   10'd58:bitmap=12'h908;
   10'd59:bitmap=12'h130;
   // 色
   10'd64:bitmap=12'h100;
   10'd65:bitmap=12'h3f8;
   10'd66:bitmap=12'h408;
   10'd67:bitmap=12'h810;
   10'd68:bitmap=12'h7fc;
   10'd69:bitmap=12'h444;
   10'd70:bitmap=12'h444;
   10'd71:bitmap=12'h7fc;
   10'd72:bitmap=12'h400;
   10'd73:bitmap=12'h402;
   10'd74:bitmap=12'h402;
   10'd75:bitmap=12'h3fe;
   // 原
   10'd80:bitmap=12'h7fe;
   10'd81:bitmap=12'h440;
   10'd82:bitmap=12'h5fc;
   10'd83:bitmap=12'h504;
   10'd84:bitmap=12'h5fc;
   10'd85:bitmap=12'h504;
   10'd86:bitmap=12'h5fc;
   10'd87:bitmap=12'h420;
   10'd88:bitmap=12'h4a8;
   10'd89:bitmap=12'h524;
   10'd90:bitmap=12'ha62;
   // 图
   10'd96:bitmap=12'hffe;
   10'd97:bitmap=12'h882;
   10'd98:bitmap=12'h9f2;
   10'd99:bitmap=12'hb12;
   10'd100:bitmap=12'h8e2;
   10'd101:bitmap=12'hf1e;
   10'd102:bitmap=12'h8c2;
   10'd103:bitmap=12'h822;
   10'd104:bitmap=12'h982;
   10'd105:bitmap=12'h862;
   10'd106:bitmap=12'hffe;
   10'd107:bitmap=12'h802;
   // 灰
   10'd112:bitmap=12'h200;
   10'd113:bitmap=12'h200;
   10'd114:bitmap=12'hffe;
   10'd115:bitmap=12'h200;
   10'd116:bitmap=12'h220;
   10'd117:bitmap=12'h2a4;
   10'd118:bitmap=12'h2a4;
   10'd119:bitmap=12'h2a8;
   10'd120:bitmap=12'h520;
   10'd121:bitmap=12'h450;
   10'd122:bitmap=12'h888;
   10'd123:bitmap=12'h306;
   // 度
   10'd128:bitmap=12'h020;
   10'd129:bitmap=12'h7fe;
   10'd130:bitmap=12'h488;
   10'd131:bitmap=12'h7fe;
   10'd132:bitmap=12'h488;
   10'd133:bitmap=12'h4f8;
   10'd134:bitmap=12'h400;
   10'd135:bitmap=12'h5fc;
   10'd136:bitmap=12'h484;
   10'd137:bitmap=12'h448;
   10'd138:bitmap=12'h430;
   10'd139:bitmap=12'h9ce;
   // 像
   10'd144:bitmap=12'h280;
   10'd145:bitmap=12'h2f8;
   10'd146:bitmap=12'h508;
   10'd147:bitmap=12'h7fc;
   10'd148:bitmap=12'hd24;
   10'd149:bitmap=12'h5fc;
   10'd150:bitmap=12'h440;
   10'd151:bitmap=12'h5a4;
   10'd152:bitmap=12'h458;
   10'd153:bitmap=12'h5b4;
   10'd154:bitmap=12'h452;
   10'd155:bitmap=12'h5b0;
   // 二
   10'd160:bitmap=12'h7fc;
   10'd168:bitmap=12'hffe;
   // 值
   10'd176:bitmap=12'h220;
   10'd177:bitmap=12'h2fe;
   10'd178:bitmap=12'h420;
   10'd179:bitmap=12'h4fc;
   10'd180:bitmap=12'hc84;
   10'd181:bitmap=12'h4fc;
   10'd182:bitmap=12'h484;
   10'd183:bitmap=12'h4fc;
   10'd184:bitmap=12'h484;
   10'd185:bitmap=12'h4fc;
   10'd186:bitmap=12'h484;
   10'd187:bitmap=12'h5fe;
   // 边
   10'd192:bitmap=12'h420;
   10'd193:bitmap=12'h220;
   10'd194:bitmap=12'h020;
   10'd195:bitmap=12'h0fe;
   10'd196:bitmap=12'he22;
   10'd197:bitmap=12'h222;
   10'd198:bitmap=12'h222;
   10'd199:bitmap=12'h242;
   10'd200:bitmap=12'h242;
   10'd201:bitmap=12'h29c;
   10'd202:bitmap=12'h500;
   10'd203:bitmap=12'h8fe;
   // 缘
   10'd208:bitmap=12'h440;
   10'd209:bitmap=12'h47c;
   10'd210:bitmap=12'h884;
   10'd211:bitmap=12'haf8;
   10'd212:bitmap=12'hc08;
   10'd213:bitmap=12'h4fe;
   10'd214:bitmap=12'h840;
   10'd215:bitmap=12'hea4;
   10'd216:bitmap=12'h058;
   10'd217:bitmap=12'h2b4;
   10'd218:bitmap=12'hc54;
   10'd219:bitmap=12'h1b2;
   // 检
   10'd224:bitmap=12'h210;
   10'd225:bitmap=12'h210;
   10'd226:bitmap=12'h228;
   10'd227:bitmap=12'hf44;
   10'd228:bitmap=12'h282;
   10'd229:bitmap=12'h67c;
   10'd230:bitmap=12'h700;
   10'd231:bitmap=12'ha24;
   10'd232:bitmap=12'h294;
   10'd233:bitmap=12'h254;
   10'd234:bitmap=12'h248;
   10'd235:bitmap=12'h2fe;
   // 测
   10'd240:bitmap=12'h002;
   10'd241:bitmap=12'hbe2;
   10'd242:bitmap=12'h62a;
   10'd243:bitmap=12'h2aa;
   10'd244:bitmap=12'h2aa;
   10'd245:bitmap=12'haaa;
   10'd246:bitmap=12'h6aa;
   10'd247:bitmap=12'h2aa;
   10'd248:bitmap=12'h2aa;
   10'd249:bitmap=12'h482;
   10'd250:bitmap=12'h942;
   10'd251:bitmap=12'h226;
   // 增
   10'd256:bitmap=12'h244;
   10'd257:bitmap=12'h2fe;
   10'd258:bitmap=12'h292;
   10'd259:bitmap=12'h2d6;
   10'd260:bitmap=12'hf92;
   10'd261:bitmap=12'h2fe;
   10'd262:bitmap=12'h200;
   10'd263:bitmap=12'h27c;
   10'd264:bitmap=12'h244;
   10'd265:bitmap=12'h37c;
   10'd266:bitmap=12'hc44;
   10'd267:bitmap=12'h07c;
   // 强
   10'd272:bitmap=12'h07c;
   10'd273:bitmap=12'he44;
   10'd274:bitmap=12'h244;
   10'd275:bitmap=12'h27c;
   10'd276:bitmap=12'he10;
   10'd277:bitmap=12'h8fe;
   10'd278:bitmap=12'h892;
   10'd279:bitmap=12'he92;
   10'd280:bitmap=12'h2fe;
   10'd281:bitmap=12'h210;
   10'd282:bitmap=12'h214;
   10'd283:bitmap=12'hcfe;
   // 颜
   10'd288:bitmap=12'h13e;
   10'd289:bitmap=12'h7c8;
   10'd290:bitmap=12'h290;
   10'd291:bitmap=12'h13e;
   10'd292:bitmap=12'h7e2;
   10'd293:bitmap=12'h4aa;
   10'd294:bitmap=12'h72a;
   10'd295:bitmap=12'h4aa;
   10'd296:bitmap=12'h72a;
   10'd297:bitmap=12'h448;
   10'd298:bitmap=12'h494;
   10'd299:bitmap=12'hb22;
   // 形
   10'd304:bitmap=12'h004;
   10'd305:bitmap=12'hfc4;
   10'd306:bitmap=12'h488;
   10'd307:bitmap=12'h492;
   10'd308:bitmap=12'h482;
   10'd309:bitmap=12'hfc4;
   10'd310:bitmap=12'h488;
   10'd311:bitmap=12'h490;
   10'd312:bitmap=12'h482;
   10'd313:bitmap=12'h484;
   10'd314:bitmap=12'h488;
   10'd315:bitmap=12'h8b0;
   // 状
   10'd320:bitmap=12'h210;
   10'd321:bitmap=12'h214;
   10'd322:bitmap=12'ha12;
   10'd323:bitmap=12'h610;
   10'd324:bitmap=12'h2fe;
   10'd325:bitmap=12'h210;
   10'd326:bitmap=12'h228;
   10'd327:bitmap=12'h628;
   10'd328:bitmap=12'ha28;
   10'd329:bitmap=12'h244;
   10'd330:bitmap=12'h244;
   10'd331:bitmap=12'h282;
   // 识
   10'd336:bitmap=12'h400;
   10'd337:bitmap=12'h2fc;
   10'd338:bitmap=12'h084;
   10'd339:bitmap=12'h084;
   10'd340:bitmap=12'hc84;
   10'd341:bitmap=12'h484;
   10'd342:bitmap=12'h4fc;
   10'd343:bitmap=12'h400;
   10'd344:bitmap=12'h400;
   10'd345:bitmap=12'h648;
   10'd346:bitmap=12'h484;
   10'd347:bitmap=12'h102;
   // 别
   10'd352:bitmap=12'h7e2;
   10'd353:bitmap=12'h422;
   10'd354:bitmap=12'h42a;
   10'd355:bitmap=12'h42a;
   10'd356:bitmap=12'h7ea;
   10'd357:bitmap=12'h10a;
   10'd358:bitmap=12'hfea;
   10'd359:bitmap=12'h12a;
   10'd360:bitmap=12'h22a;
   10'd361:bitmap=12'h222;
   10'd362:bitmap=12'h422;
   10'd363:bitmap=12'h9c6;
   // 阈
   10'd368:bitmap=12'h9fe;
   10'd369:bitmap=12'h42a;
   10'd370:bitmap=12'h022;
   10'd371:bitmap=12'hbfa;
   10'd372:bitmap=12'h822;
   10'd373:bitmap=12'hba2;
   10'd374:bitmap=12'haaa;
   10'd375:bitmap=12'haaa;
   10'd376:bitmap=12'hbb2;
   10'd377:bitmap=12'h8aa;
   10'd378:bitmap=12'hb5a;
   10'd379:bitmap=12'h88e;
   // 差
   10'd384:bitmap=12'h208;
   10'd385:bitmap=12'h110;
   10'd386:bitmap=12'hffe;
   10'd387:bitmap=12'h040;
   10'd388:bitmap=12'h7fc;
   10'd389:bitmap=12'h080;
   10'd390:bitmap=12'hffe;
   10'd391:bitmap=12'h100;
   10'd392:bitmap=12'h3fc;
   10'd393:bitmap=12'h420;
   10'd394:bitmap=12'h820;
   10'd395:bitmap=12'h3fe;
   // 低
   10'd400:bitmap=12'h10c;
   10'd401:bitmap=12'h1f0;
   10'd402:bitmap=12'h290;
   10'd403:bitmap=12'h290;
   10'd404:bitmap=12'h690;
   10'd405:bitmap=12'hafe;
   10'd406:bitmap=12'h290;
   10'd407:bitmap=12'h290;
   10'd408:bitmap=12'h2aa;
   10'd409:bitmap=12'h2ca;
   10'd410:bitmap=12'h2a6;
   10'd411:bitmap=12'h212;
   // 中
   10'd416:bitmap=12'h040;
   10'd417:bitmap=12'h040;
   10'd418:bitmap=12'h040;
   10'd419:bitmap=12'h7fc;
   10'd420:bitmap=12'h444;
   10'd421:bitmap=12'h444;
   10'd422:bitmap=12'h444;
   10'd423:bitmap=12'h7fc;
   10'd424:bitmap=12'h444;
   10'd425:bitmap=12'h040;
   10'd426:bitmap=12'h040;
   10'd427:bitmap=12'h040;
   // 高
   10'd432:bitmap=12'h040;
   10'd433:bitmap=12'hffe;
   10'd435:bitmap=12'h3f8;
   10'd436:bitmap=12'h208;
   10'd437:bitmap=12'h3f8;
   10'd439:bitmap=12'hffe;
   10'd440:bitmap=12'h802;
   10'd441:bitmap=12'h9f2;
   10'd442:bitmap=12'h912;
   10'd443:bitmap=12'h9f6;
   default:bitmap=0;
  endcase
 end
 assign dots=pair<6?bitmap[11-pair*2 -:2]:2'b00;
endmodule

// Two video stages, exactly matching the accepted frame_status_96 interface.
// Metadata snapshots change at SOF; no pixel feedback into any image algorithm.
module presentation_status_96 #(parameter IMG_WIDTH=1280,IMG_HEIGHT=720)(
 input wire clk,rst_n,I_tlast,I_tuser,I_tvalid,input wire [95:0] I_tdata,
 input wire [2:0] I_mode,input wire [7:0] I_threshold,
 input wire [159:0] I_spatial_diag,input wire I_motion_valid,
 input wire [9:0] I_motion_tiles,input wire I_motion_global,
 output reg O_tlast,O_tuser,O_tvalid,output reg [95:0] O_tdata
);
 reg [10:0] x,y;
 wire [10:0] px=I_tuser?0:x,py=I_tuser?0:y;
 reg [2:0] mode_f,cal_f;reg [7:0] threshold_f;
 reg [6:0] parameter_frames;
 wire [2:0] mode=I_tuser?I_mode:mode_f;
 wire [2:0] cal_raw=I_tuser?I_spatial_diag[2:0]:cal_f;
 // A stale legacy OFF code cannot claim valid calibration.
 wire [2:0] cal=cal_raw==3'd4 ? 3'd0 : cal_raw;
 reg [9:0] moving_f,binary;
 reg global_f;reg moving_valid_f;reg [11:0] scratch,decimals;reg [3:0] remaining;
 reg [11:0] adjusted;integer j;
 always @*begin
  adjusted=scratch;
  for(j=0;j<3;j=j+1)if(scratch[j*4+:4]>=5)adjusted[j*4+:4]=scratch[j*4+:4]+4'd3;
 end
 wire mode_area=px>=180 && px<(mode==5?396:332) && py>=24 && py<72;
 wire parameter_area=parameter_frames!=0 && ((mode>=2 && mode<=5) || mode==7) && px>=184 && px<(mode==4?264:296) && py>=80 && py<112;
 wire motion_area=mode==6 && px>=944 && px<1264 && py>=56 && py<88;
 wire calibration_area=px>=16 && px<144 && py>=672 && py<704;
 wire meter_area=mode==6 && !global_f && px>=1120 && px<1248 && py>=68 && py<76;
 wire [6:0] motion_level=({1'b0,moving_f}+11'd15)>>4;
 wire meter_on=moving_valid_f && ((px-1120)>>2)<motion_level;
 wire [23:0] motion_ink=moving_f>=128?24'hff7050:moving_f>=32?24'hffd060:24'h50d890;
 reg [10:0] dx,dy;reg [4:0] pos;reg [7:0] code;
 reg [3:0] row;reg [3:0] col;reg scaled;
 reg [7:0] tr;reg [3:0] hundred,ten,one;
 always @*begin
  code=32;dx=0;dy=0;scaled=0;pos=0;
  hundred=threshold_f/100;tr=threshold_f-hundred*100;ten=tr/10;one=tr-ten*10;
  if(mode_area)begin
   dx=px-192;dy=py-32;scaled=1;pos=dx>>5;
   case(pos)
    0:case(mode)0:code=8'd128;1:code=8'd132;2:code=8'd135;3:code=8'd137;4:code=8'd131;5:code=8'd143;6:code=8'd166;7:code=8'd201;default:code=32;endcase
    1:case(mode)0:code=8'd129;1:code=8'd133;2:code=8'd136;3:code=8'd138;4:code=8'd134;5:code=8'd129;6:code=8'd167;7:code=8'd202;default:code=32;endcase
    2:case(mode)0:code=8'd130;1,2:code=8'd131;3:code=8'd139;4:code=8'd141;5:code=8'd144;6:code=8'd139;7:code=8'd179;default:code=32;endcase
    3:case(mode)0:code=8'd131;1,2:code=8'd134;3:code=8'd140;4:code=8'd142;5:code=8'd145;6:code=8'd140;7:code=8'd203;default:code=32;endcase
    4:if(mode==5)code=8'd146;
    5:if(mode==5)code=8'd147;
    default:code=32;
   endcase
   if(px<192 || py<32 || py>=64)code=32;
  end else if(parameter_area)begin
   dx=px-192;dy=py-88;pos=dx>>4;
   case(pos)
    0:code=mode==4?8'd142:mode==5?8'd129:8'd148;
    1:code=mode==4?8'd133:mode==5?8'd152:8'd136;
    2:code=":";
    3:if(mode==4)case(threshold_f[4:3])1:code=8'd149;2:code=8'd150;default:code=8'd151;endcase else code=48+hundred;
    4:if(mode!=4)code=48+ten;
    5:if(mode!=4)code=48+one;
    default:code=32;
   endcase
   if(px<192 || py<88 || py>=104)code=32;
  end else if(motion_area)begin
   dx=px-952;dy=py-64;pos=dx>>4;
   case(pos)
    0:code=global_f?8'd197:8'd166;1:code=global_f?8'd198:8'd167;2:code=global_f?8'd199:8'd168;3:if(global_f)code=8'd200;
    4:code=global_f?8'd32:moving_valid_f?48+decimals[11:8]:"-";
    5:code=global_f?8'd32:moving_valid_f?48+decimals[7:4]:"-";
    6:code=global_f?8'd32:moving_valid_f?48+decimals[3:0]:"-";
    default:code=32;
   endcase
   if(px<952 || py<64 || py>=80)code=32;
  end else if(calibration_area)begin
   dx=px-24;dy=py-680;pos=dx>>4;
   case(pos)
    0:code=8'd153;1:code=8'd129;2:code=":";
    4:case(cal)1:code=8'd156;2:code=8'd158;3:code="O";5:code=8'd164;default:code=8'd154;endcase
    5:case(cal)1:code=8'd157;2:code=8'd159;3:code="N";5:code=8'd165;default:code=8'd153;endcase
    6:case(cal)1,2:code=8'd150;0:code=8'd155;default:code=32;endcase
    default:code=32;
   endcase
   if(px<24 || py<680 || py>=696)code=32;
  end
  row=scaled?dy[4:1]:dy[3:0];col=scaled?dx[4:1]:dx[3:0];
 end
 wire [15:0] glyph;
 presentation_font16_sync font(.clk(clk),.code(code),.row(row),.bits(glyph));
 wire panel=mode_area||parameter_area||motion_area||calibration_area;
 wire [23:0] ink=calibration_area?(cal==3?24'h60e0a0:cal==5?24'hff9860:24'hffd080):24'hf0f4f8;
 reg [3:0] column_q;reg scaled_q;reg panel_q,meter_q,meter_on_q,vq,uq,lq;
 reg [95:0] data_q;reg [23:0] ink_q,meter_ink_q;
 integer lane;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   x<=0;y<=0;mode_f<=3;cal_f<=0;threshold_f<=96;parameter_frames<=0;
   global_f<=0;moving_f<=0;moving_valid_f<=0;binary<=0;scratch<=0;decimals<=0;remaining<=0;
   column_q<=0;scaled_q<=0;panel_q<=0;meter_q<=0;meter_on_q<=0;vq<=0;uq<=0;lq<=0;data_q<=0;ink_q<=0;meter_ink_q<=0;
   O_tvalid<=0;O_tuser<=0;O_tlast<=0;O_tdata<=0;
  end else begin
   if(I_tuser)begin
    mode_f<=I_mode;threshold_f<=I_threshold;cal_f<=I_spatial_diag[2:0];
    moving_f<=I_motion_tiles;moving_valid_f<=I_motion_valid;global_f<=I_motion_global;
    binary<=I_motion_tiles>999?10'd999:I_motion_tiles;scratch<=0;remaining<=10;
    if(mode_f!=I_mode || threshold_f!=I_threshold)parameter_frames<=90;
    else if(parameter_frames!=0)parameter_frames<=parameter_frames-1'b1;
   end else if(remaining!=0)begin
    scratch<={adjusted[10:0],binary[9]};binary<=binary<<1;remaining<=remaining-1'b1;
    if(remaining==1)decimals<={adjusted[10:0],binary[9]};
   end
   if(I_tuser)begin x<=0;y<=0;end
   if(I_tvalid)begin x<=px==IMG_WIDTH-4?0:px+4;y<=px==IMG_WIDTH-4?(py==IMG_HEIGHT-1?0:py+1'b1):py;end
   data_q<=I_tdata;panel_q<=panel;meter_q<=meter_area;meter_on_q<=meter_on;
   vq<=I_tvalid;uq<=I_tuser;lq<=I_tlast;ink_q<=ink;meter_ink_q<=motion_ink;
   column_q<=col;scaled_q<=scaled;
   O_tvalid<=vq;O_tuser<=uq;O_tlast<=lq;
   for(lane=0;lane<4;lane=lane+1)O_tdata[95-lane*24-:24]<=!vq?24'd0:
     meter_q?(meter_on_q?meter_ink_q:24'h283440):(panel_q && glyph[15-(column_q+(scaled_q?(lane>>1):lane))])?ink_q:panel_q?24'h101820:data_q[95-lane*24-:24];
  end
 end
endmodule
