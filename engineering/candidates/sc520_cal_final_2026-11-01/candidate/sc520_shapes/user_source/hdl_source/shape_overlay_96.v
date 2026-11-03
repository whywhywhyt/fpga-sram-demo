// Multicolor shape overlay; eight transport clocks, matching accepted design.
// Only frame-complete detection results are snapshotted, before DDR.
module target_overlay_96 #(parameter integer IMG_WIDTH=1280,IMG_HEIGHT=720,SEPARATE_DETECTION=0,PRESENTATION=0)(
 input wire clk,rst_n,I_tuser,I_tvalid,I_tlast,input wire [95:0] I_tdata,
 input wire [2:0] I_mode,input wire [7:0] I_threshold,input wire [1:0] I_color,
 output reg O_tuser,O_tvalid,O_tlast,output reg [95:0] O_tdata,
 input wire [95:0] I_detection_data,
 output reg [2:0] O_mode,output reg [7:0] O_threshold
);
 wire detected,overflow;wire [255:0] boxes;wire [2:0] shown;
 wire [7:0] total,detector_margin;wire [15:0] detector_frame,capture_frame,skipped;
 shape_detector_96 #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT)) detector(
  .clk(clk),.rst_n(rst_n),.user(I_tuser),.valid(I_tvalid),.enable(I_mode==5),.data(SEPARATE_DETECTION?I_detection_data:I_tdata),.margin(I_threshold),
  .result_valid(detected),.result_overflow(overflow),.result_boxes(boxes),.result_shown(shown),
  .result_total(total),.result_margin(detector_margin),.result_frame(detector_frame),
  .capture_frame(capture_frame),.skipped_frames(skipped));
 reg [15:0] label_frame;
 wire label_update=detected && detector_frame!=label_frame;
 wire label_done;wire [255:0] converted_boxes;wire [143:0] coordinate_bcd;
 reg [15:0] pending_frame,ready_frame;
 reg [7:0] pending_margin,pending_total,ready_margin,ready_total;
 reg [2:0] pending_shown,ready_shown;
 reg pending_overflow,ready_overflow,ready_valid;
 reg [255:0] ready_boxes;reg [143:0] ready_coordinates;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)begin
   label_frame<=0;pending_frame<=0;ready_frame<=0;pending_margin<=0;pending_total<=0;
   ready_margin<=0;ready_total<=0;pending_shown<=0;ready_shown<=0;
   pending_overflow<=0;ready_overflow<=0;ready_valid<=0;ready_boxes<=0;ready_coordinates<=0;
  end else begin
   if(label_update)begin
    label_frame<=detector_frame;pending_frame<=detector_frame;pending_margin<=detector_margin;
    pending_shown<=shown;pending_total<=total;pending_overflow<=overflow;
   end
   // Publish geometry and BCD as one completed transaction. A result that
   // arrives near SOF waits for the next frame instead of mixing old digits.
   if(label_done)begin
    ready_frame<=pending_frame;ready_margin<=pending_margin;ready_shown<=pending_shown;
    ready_total<=pending_total;ready_overflow<=pending_overflow;
    ready_boxes<=converted_boxes;ready_coordinates<=coordinate_bcd;ready_valid<=1;
   end
  end

 // Capture completed detector metadata at the incoming SOF. Geometry uses it
 // only when that SOF reaches stage five, so back-to-back frames stay atomic.
 reg [255:0] snapshot_boxes;reg [143:0] snapshot_coordinates,display_coordinates;
 reg [2:0] snapshot_shown;reg [7:0] snapshot_total;
 reg [3:0] snapshot_age;reg snapshot_overflow;
 wire [15:0] incoming_age=(capture_frame+16'd1)-ready_frame;
 wire incoming_fresh=detected && ready_valid && incoming_age<=3 && ready_margin==I_threshold;
 reg [95:0] rgb[0:4];reg [2:0] modes[0:4];reg [7:0] thresholds[0:4];
 reg [4:0] users,valids,lasts;
 reg [255:0] display_boxes;reg [2:0] display_shown;reg [7:0] display_total;
 reg [3:0] display_age;reg display_overflow;reg [10:0] x,y;
 wire [10:0] px=users[4]?11'd0:x,py=users[4]?11'd0:y;
 wire [255:0] rb=users[4]?snapshot_boxes:display_boxes;
 wire [143:0] coordinate_view=users[4]?snapshot_coordinates:display_coordinates;
 wire [2:0] rs=users[4]?snapshot_shown:display_shown;
 wire [7:0] rt=users[4]?snapshot_total:display_total;
 wire [3:0] ra=users[4]?snapshot_age:display_age;
 wire ro=users[4]?snapshot_overflow:display_overflow;
 wire enabled=modes[4]==5;
 wire header=!PRESENTATION && px>=184 && px<696 && py>=88 && py<112;
 wire legend=!PRESENTATION && px>=16 && px<528 && py>=608 && py<704;
 wire [6:0] ly=py-11'd608;
 wire [2:0] li=ly<24?0:ly<48?1:ly<72?2:3;
 wire [4:0] in_row=ly-(li*5'd24);
 wire [10:0] tx=header?px-11'd192:px-11'd16;
 wire [4:0] pos=tx[8:4];wire [2:0] row=header?((py-11'd92)>>1):(in_row>>1);
 wire [7:0] code;wire [4:0] glyph;
 shape_panel_char label(.clk(clk),.rst_n(rst_n),.update(label_update),.boxes(boxes),.total(total),
  .view_boxes(rb),.view_coordinates(coordinate_view),.shown(rs),.age(ra),.overflow(ro),
  .line(header?3'd0:li+3'd1),.pos(pos),.code(code),.coordinate_bcd(coordinate_bcd),
  .converted_boxes(converted_boxes),.conversion_done(label_done));
 osd_font5x7 font(.code(code),.row(row),.bits(glyph));
 // Independent geometry registers prevent four overlapping objects from
 // forming a serial coordinate-comparison / pixel-priority critical path.
 reg [15:0] border_g,center_g,id_g,tag_panel_g,tag_text_g;
 reg [95:0] inks_g,rgb_g;reg [3:0] text_g;reg panel_g,u_g,v_g,l_g;
 reg [2:0] mode_g;reg [7:0] th_g;
 genvar target,lane;
 generate for(target=0;target<4;target=target+1)begin:objects
  localparam [7:0] ID=49+target;
  wire [10:0] x0=rb[target*64 +:11],x1=rb[target*64+11 +:11];
  wire [10:0] y0=rb[target*64+22 +:11],y1=rb[target*64+33 +:11];
  wire [11:0] sumx={1'b0,x0}+{1'b0,x1},sumy={1'b0,y0}+{1'b0,y1};
  wire [10:0] cx=sumx[11:1],cy=sumy[11:1];
  wire [1:0] color=rb[target*64+44 +:2];wire [1:0] shape=rb[target*64+46 +:2];wire [4:0] digit;
  wire [2:0] drow=py-y0-11'd4;
  // Use the four existing transport stages before geometry to split tag
  // origin, character selection and font lookup without extra video delay.
  reg [10:0] early_x,early_y;reg [255:0] early_boxes;
  reg [143:0] early_coordinates;reg [2:0] early_shown;
  wire [10:0] ex=users[0]?11'd0:early_x,ey=users[0]?11'd0:early_y;
  wire [255:0] eb=users[0]?snapshot_boxes:early_boxes;
  wire [143:0] ec=users[0]?snapshot_coordinates:early_coordinates;
  wire [2:0] es=users[0]?snapshot_shown:early_shown;
  wire [10:0] bx=eb[target*64 +:11],by=eb[target*64+22 +:11];
  wire [1:0] bc=eb[target*64+44 +:2],bs=eb[target*64+46 +:2];
  wire [15:0] bcdx=ec[target*32 +:16],bcdy=ec[target*32+16 +:16];
  wire [4:0] pre_length;wire [7:0] unused_code;
  if(PRESENTATION)begin:zh_dimensions
   shape_tag_zh_char dimensions(.color(bc),.shape(bs),.position(5'd0),.x_bcd(bcdx),.y_bcd(bcdy),.code(unused_code),.length(pre_length));
  end else begin:ascii_dimensions
   shape_tag_char dimensions(.color(bc),.shape(bs),.position(5'd0),.x_bcd(bcdx),.y_bcd(bcdy),.code(unused_code),.length(pre_length));
  end
  wire [8:0] pre_width={pre_length,4'b0};
  reg [10:0] ax,ay,origin_x,origin_y;reg [8:0] awidth;
  reg [15:0] axb,ayb,bxb,byb;reg [1:0] acolor,ashape,bcolor,bshape;
  reg aenable,benable,cenable,denable;
  reg [4:0] bpos;reg [3:0] bcol,ccol,dcol;reg [2:0] brow,crow;reg [3:0] bzhrow;
  reg [7:0] char_c;reg [4:0] glyph_d;
  wire [7:0] next_char;wire [4:0] unused_length,font_bits;
  if(PRESENTATION)begin:zh_tag
   shape_tag_zh_char tag(.color(bcolor),.shape(bshape),.position(bpos),.x_bcd(bxb),.y_bcd(byb),.code(next_char),.length(unused_length));
  end else begin:ascii_tag
   shape_tag_char tag(.color(bcolor),.shape(bshape),.position(bpos),.x_bcd(bxb),.y_bcd(byb),.code(next_char),.length(unused_length));
  end
  wire [15:0] zh_bits;wire [15:0] zh_glyph_d=zh_bits;reg [3:0] zh_row;
  osd_font5x7 tag_font(.code(char_c),.row(crow),.bits(font_bits));
  if(PRESENTATION)begin:zh_font
   presentation_font16_sync #(.BANK(1)) font(.clk(clk),.code(char_c),.row(zh_row),.bits(zh_bits));
  end else assign zh_bits=0;
  reg panel_a,panel_b,panel_c,panel_d_tag;
  wire [10:0] relx=ax-origin_x,rely=ay-origin_y;
  always @(posedge clk or negedge rst_n)begin
   if(!rst_n)begin
    early_x<=0;early_y<=0;early_boxes<=0;early_coordinates<=0;early_shown<=0;
    ax<=0;ay<=0;origin_x<=0;origin_y<=0;awidth<=0;axb<=0;ayb<=0;bxb<=0;byb<=0;
    acolor<=0;ashape<=0;bcolor<=0;bshape<=0;aenable<=0;benable<=0;cenable<=0;denable<=0;
    bpos<=0;bcol<=0;ccol<=0;dcol<=0;brow<=0;crow<=0;char_c<=0;glyph_d<=0;
    panel_a<=0;panel_b<=0;panel_c<=0;panel_d_tag<=0;bzhrow<=0;zh_row<=0;
   end else begin
    if(users[0])begin early_boxes<=snapshot_boxes;early_coordinates<=snapshot_coordinates;early_shown<=snapshot_shown;early_x<=0;early_y<=0;end
    if(valids[0])begin early_x<=ex==IMG_WIDTH-4?11'd0:ex+11'd4;early_y<=ex==IMG_WIDTH-4?(ey==IMG_HEIGHT-1?11'd0:ey+1'b1):ey;end
    ax<=ex;ay<=ey;
    origin_x<=PRESENTATION?((bx+pre_width<=IMG_WIDTH?bx:IMG_WIDTH-pre_width)&11'h7fc):(bx+pre_width<=IMG_WIDTH?bx:IMG_WIDTH-pre_width);
    origin_y<=by>=16?by-11'd16:11'd0;awidth<=pre_width;
    axb<=bcdx;ayb<=bcdy;acolor<=bc;ashape<=bs;
    aenable<=modes[0]==5 && target<es && IMG_WIDTH>=pre_width;
    bpos<=relx[8:4];bcol<=relx[3:0];brow<=rely[3:1];bzhrow<=rely[3:0];
    bxb<=axb;byb<=ayb;bcolor<=acolor;bshape<=ashape;
    panel_b<=aenable && ax>=origin_x && relx<awidth && ay>=origin_y && rely<16;
    benable<=aenable && ax>=origin_x && relx<awidth && ay>=origin_y && rely<(PRESENTATION?16:14);
    char_c<=next_char;crow<=brow;zh_row<=bzhrow;ccol<=bcol;cenable<=benable;panel_c<=panel_b;
    glyph_d<=font_bits;dcol<=ccol;denable<=cenable;panel_d_tag<=panel_c;
   end
  end
  osd_font5x7 number(.code(ID),.row(drow),.bits(digit));
  always @(posedge clk or negedge rst_n)
   if(!rst_n)inks_g[target*24 +:24]<=0;
   else inks_g[target*24 +:24]<=color==0?24'hffe040:color==1?24'hff4040:color==2?24'h40ff70:24'h40c8ff;
  for(lane=0;lane<4;lane=lane+1)begin:lanes
   wire [11:0] xx={1'b0,px}+lane;

   wire selected=enabled && target<rs;
   always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin border_g[target*4+lane]<=0;center_g[target*4+lane]<=0;id_g[target*4+lane]<=0;tag_panel_g[target*4+lane]<=0;tag_text_g[target*4+lane]<=0;end
    else begin
     border_g[target*4+lane]<=selected && xx>=x0 && xx<=x1 && py>=y0 && py<=y1 &&
      (xx<x0+12'd2 || xx+12'd2>x1 || {1'b0,py}<y0+12'd2 || {1'b0,py}+12'd2>y1);
     center_g[target*4+lane]<=selected && ((py==cy && xx+12'd6>=cx && xx<=cx+12'd6) ||
      (xx==cx && {1'b0,py}+12'd6>=cy && {1'b0,py}<=cy+12'd6));
     id_g[target*4+lane]<=selected && xx>=x0+12'd4 && xx<x0+12'd9 && py>=y0+12'd4 && py<y0+12'd11 && digit[4-(xx-x0-4)];
     tag_panel_g[target*4+lane]<=panel_d_tag;
     tag_text_g[target*4+lane]<=denable && (PRESENTATION?(dcol+lane<16 && zh_glyph_d[15-(dcol+lane)]):(dcol+lane<10 && glyph_d[4-((dcol+lane)>>1)]));
    end
   end
  end
 end endgenerate
 reg [95:0] base_d,decorated;reg [3:0] text_d;reg panel_d,u_d,v_d,l_d;
 reg [2:0] mode_d;reg [7:0] th_d;
 integer i,j;reg [23:0] pixel;
 always @(*)begin
  decorated=rgb_g;pixel=0;
  for(i=0;i<4;i=i+1)begin
   pixel=rgb_g[95-i*24 -:24];
  for(j=0;j<4;j=j+1)begin
    if(border_g[j*4+i])pixel=inks_g[j*24 +:24];
    if(center_g[j*4+i])pixel=24'hffff00;
    if(id_g[j*4+i])pixel=24'hffffff;
    if(tag_panel_g[j*4+i])pixel=PRESENTATION?24'h101820:inks_g[j*24 +:24];
    if(tag_text_g[j*4+i])pixel=PRESENTATION?inks_g[j*24+:24]:24'hffffff;
   end
   decorated[95-i*24 -:24]=pixel;
  end
 end
 integer k;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   snapshot_boxes<=0;snapshot_coordinates<=0;display_coordinates<=0;
   snapshot_shown<=0;snapshot_total<=0;snapshot_age<=0;snapshot_overflow<=0;
   for(k=0;k<5;k=k+1)begin rgb[k]<=0;modes[k]<=0;thresholds[k]<=0;end
   users<=0;valids<=0;lasts<=0;display_boxes<=0;display_shown<=0;display_total<=0;display_age<=0;display_overflow<=0;x<=0;y<=0;
   rgb_g<=0;text_g<=0;panel_g<=0;u_g<=0;v_g<=0;l_g<=0;mode_g<=0;th_g<=0;
   base_d<=0;text_d<=0;panel_d<=0;u_d<=0;v_d<=0;l_d<=0;mode_d<=0;th_d<=0;
   O_tuser<=0;O_tvalid<=0;O_tlast<=0;O_tdata<=0;O_mode<=0;O_threshold<=0;
  end else begin
   if(I_tuser)begin
    snapshot_boxes<=incoming_fresh?ready_boxes:256'd0;snapshot_shown<=incoming_fresh?ready_shown:3'd0;snapshot_total<=incoming_fresh?ready_total:8'd0;
    snapshot_coordinates<=incoming_fresh?ready_coordinates:144'd0;
    snapshot_age<=incoming_age>9?4'd9:incoming_age[3:0];snapshot_overflow<=ready_overflow;
   end
   rgb[0]<=I_tdata;modes[0]<=I_mode;thresholds[0]<=I_threshold;
   for(k=1;k<5;k=k+1)begin rgb[k]<=rgb[k-1];modes[k]<=modes[k-1];thresholds[k]<=thresholds[k-1];end
   users<={users[3:0],I_tuser};valids<={valids[3:0],I_tvalid};lasts<={lasts[3:0],I_tlast};
   if(users[4])begin
    display_boxes<=snapshot_boxes;display_shown<=snapshot_shown;display_total<=snapshot_total;
    display_coordinates<=snapshot_coordinates;
    display_age<=snapshot_age;display_overflow<=snapshot_overflow;x<=0;y<=0;
   end
   if(valids[4])begin x<=px==IMG_WIDTH-4?11'd0:px+11'd4;y<=px==IMG_WIDTH-4?(py==IMG_HEIGHT-1?11'd0:py+1'b1):py;end
   rgb_g<=rgb[4];panel_g<=enabled && (header || (legend && li<rs));
   for(k=0;k<4;k=k+1)text_g[3-k]<=enabled && ((header && px>=192 && py>=92 && py<106) ||
    (legend && li<rs && in_row<14)) && tx[3:0]+k<10 && glyph[4-((tx[3:0]+k)>>1)];
   u_g<=users[4];v_g<=valids[4];l_g<=lasts[4];mode_g<=modes[4];th_g<=thresholds[4];
   base_d<=decorated;text_d<=text_g;panel_d<=panel_g;
   u_d<=u_g;v_d<=v_g;l_d<=l_g;mode_d<=mode_g;th_d<=th_g;
   O_tuser<=u_d;O_tvalid<=v_d;O_tlast<=l_d;O_mode<=mode_d;O_threshold<=th_d;
   for(k=0;k<4;k=k+1)O_tdata[95-k*24 -:24]<=!v_d?24'd0:text_d[3-k]?24'hffffff:panel_d?24'h101820:base_d[95-k*24 -:24];
  end
 end
endmodule

module shape_panel_char(
 input wire clk,rst_n,update,input wire [255:0] boxes,input wire [2:0] shown,line,
 input wire [255:0] view_boxes,input wire [143:0] view_coordinates,
 input wire [7:0] total,input wire [3:0] age,input wire overflow,input wire [4:0] pos,
 output reg [7:0] code,output wire [143:0] coordinate_bcd,
 output wire [255:0] converted_boxes,output reg conversion_done
);
 // One double-dabble engine converts all eight coordinates and total.
 reg [255:0] held;reg [7:0] held_total;reg [15:0] decimals[0:8],bcd;
 reg [10:0] binary;reg [3:0] remaining,index;reg [15:0] adjust;
 reg [63:0] next_box;reg [11:0] next_sum;integer n;
 always @(*)begin
  adjust=bcd;
  for(n=0;n<4;n=n+1)if(bcd[n*4 +:4]>=5)adjust[n*4 +:4]=bcd[n*4 +:4]+4'd3;
  next_box=held[((index+1'b1)>>1)*64 +:64];
  next_sum=index[0]?({1'b0,next_box[10:0]}+{1'b0,next_box[21:11]}):({1'b0,next_box[32:22]}+{1'b0,next_box[43:33]});
 end
 integer t;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   held<=0;held_total<=0;bcd<=0;binary<=0;remaining<=0;index<=0;conversion_done<=0;for(t=0;t<9;t=t+1)decimals[t]<=0;
  end else begin
   conversion_done<=0;
   if(update)begin
   held<=boxes;held_total<=total;index<=0;remaining<=11;bcd<=0;binary<=({1'b0,boxes[10:0]}+{1'b0,boxes[21:11]})>>1;
  end else if(remaining!=0)begin
   bcd<={adjust[14:0],binary[10]};binary<={binary[9:0],1'b0};remaining<=remaining-1'b1;
   if(remaining==1)begin
    decimals[index]<={adjust[14:0],binary[10]};
    if(index<8)begin index<=index+1'b1;remaining<=11;bcd<=0;binary<=index==7?{3'd0,held_total}:next_sum[11:1];end
    else conversion_done<=1;
   end
  end
  end
 end
 reg [255:0] text;reg [47:0] color_text;reg [63:0] shape_text,box;
 reg [15:0] xd,yd;reg [2:0] r;
 always @(*)begin
  r=line==0?3'd0:line-1'b1;box=view_boxes[r*64 +:64];xd=view_coordinates[r*32 +:16];yd=view_coordinates[r*32+16 +:16];
  case(box[45:44])0:color_text="YELLOW";1:color_text="RED   ";2:color_text="GREEN ";default:color_text="BLUE  ";endcase
  case(box[47:46])1:shape_text="CIRCLE  ";2:shape_text="TRIANGLE";3:shape_text="RECT    ";default:shape_text="UNKNOWN ";endcase
  text="                                ";
  if(line==0)begin
   text=overflow?"QUEUE OVERFLOW                  ":"OBJECTS 000 SHOW 0 AGE 0        ";
   if(!overflow)begin
    text[191:184]=8'd48+view_coordinates[139:136];text[183:176]=8'd48+view_coordinates[135:132];text[175:168]=8'd48+view_coordinates[131:128];
    text[119:112]=8'd48+shown;text[71:64]=8'd48+age;
   end
  end else begin
   text[255:248]=8'd48+line;text[239:192]=color_text;text[191:128]=shape_text;text[119:112]="X";text[63:56]="Y";
   text[103:96]=8'd48+xd[15:12];text[95:88]=8'd48+xd[11:8];text[87:80]=8'd48+xd[7:4];text[79:72]=8'd48+xd[3:0];
   text[47:40]=8'd48+yd[15:12];text[39:32]=8'd48+yd[11:8];text[31:24]=8'd48+yd[7:4];text[23:16]=8'd48+yd[3:0];
  end
  code=text[255-pos*8 -:8];
 end
 assign coordinate_bcd={decimals[8],decimals[7],decimals[6],decimals[5],decimals[4],decimals[3],decimals[2],decimals[1],decimals[0]};
 assign converted_boxes=held;
endmodule

module shape_tag_char(
 input wire [1:0] color,
 input wire [1:0] shape,
 input wire [4:0] position,
 input wire [15:0] x_bcd,y_bcd,
 output reg [7:0] code,
 output wire [4:0] length
);
 wire [4:0] color_length=color==0?5'd6:color==2?5'd5:color==1?5'd3:5'd4;
 wire [4:0] name_length=shape==1?5'd6:shape==2?5'd8:shape==3?5'd4:5'd7;
 wire [4:0] x_digits=x_bcd[15:12]!=0?5'd4:x_bcd[11:8]!=0?5'd3:x_bcd[7:4]!=0?5'd2:5'd1;
 wire [4:0] y_digits=y_bcd[11:8]!=0?5'd3:y_bcd[7:4]!=0?5'd2:5'd1;
 wire [4:0] shape_start=color_length+5'd1;
 wire [4:0] open_pos=shape_start+name_length+5'd1;
 wire [4:0] x_start=open_pos+5'd1;
 wire [4:0] comma_pos=x_start+x_digits;
 wire [4:0] y_start=comma_pos+5'd1;
 assign length=color_length+name_length+x_digits+y_digits+5'd5;
 reg [3:0] digit;
 reg [4:0] digit_index;
 always @*begin
  code=8'h20;digit=0;digit_index=0;
  if(position<color_length)begin
   case(color)
    0:case(position)0:code="Y";1:code="E";2:code="L";3:code="L";4:code="O";default:code="W";endcase
    1:case(position)0:code="R";1:code="E";default:code="D";endcase
    2:case(position)0:code="G";1:code="R";2:code="E";3:code="E";default:code="N";endcase
    default:case(position)0:code="B";1:code="L";2:code="U";default:code="E";endcase
   endcase
  end else if(position==color_length)code=8'h20;
  else if(position>=shape_start && position<shape_start+name_length)begin
   case(shape)
    1:case(position-shape_start)0:code="C";1:code="I";2:code="R";3:code="C";4:code="L";default:code="E";endcase
    2:case(position-shape_start)0:code="T";1:code="R";2:code="I";3:code="A";4:code="N";5:code="G";6:code="L";default:code="E";endcase
    3:case(position-shape_start)0:code="R";1:code="E";2:code="C";default:code="T";endcase
    default:case(position-shape_start)0:code="U";1:code="N";2:code="K";3:code="N";4:code="O";5:code="W";default:code="N";endcase
   endcase
  end else if(position==open_pos)code="(";
  else if(position>=x_start && position<comma_pos)begin
   digit_index=position-x_start;
   digit=(x_bcd >> ((x_digits-5'd1-digit_index)*4)) & 4'hf;
   code=8'd48+digit;
  end else if(position==comma_pos)code=",";
  else if(position>=y_start && position<y_start+y_digits)begin
   digit_index=position-y_start;
   digit=(y_bcd >> ((y_digits-5'd1-digit_index)*4)) & 4'hf;
   code=8'd48+digit;
  end else if(position==y_start+y_digits)code=")";
 end
endmodule

module shape_tag_zh_char(input wire [1:0] color,shape,input wire [4:0] position,
 input wire [15:0] x_bcd,y_bcd,output reg [7:0] code,output wire [4:0] length);
 wire [4:0] name_length=shape==2 || shape==0?3:2;
 wire [4:0] nx=x_bcd[15:12]!=0?4:x_bcd[11:8]!=0?3:x_bcd[7:4]!=0?2:1;
 wire [4:0] ny=y_bcd[11:8]!=0?3:y_bcd[7:4]!=0?2:1;
 wire [4:0] open_pos=4+name_length,x_start=open_pos+1,comma_pos=x_start+nx,y_start=comma_pos+1;
 assign length=2+name_length+nx+ny+5;
 reg [3:0] digit;reg [4:0] digit_index;
 always @*begin
  code=32;digit=0;digit_index=0;
  if(position==0)case(color)0:code=8'd189;1:code=8'd188;2:code=8'd190;default:code=8'd191;endcase
  else if(position==1)code=8'd129;
  else if(position==3)case(shape)1:code=8'd192;2:code=8'd193;3:code=8'd195;default:code=8'd154;endcase
  else if(position==4)case(shape)1,3:code=8'd144;2:code=8'd194;default:code=8'd196;endcase
  else if(position==5 && name_length==3)code=shape==2?8'd144:8'd180;
  else if(position==open_pos)code="(";
  else if(position>=x_start && position<comma_pos)begin
   digit_index=nx-1-(position-x_start);digit=(x_bcd>>(digit_index*4))&15;code=48+digit;
  end else if(position==comma_pos)code=",";
  else if(position>=y_start && position<y_start+ny)begin
   digit_index=ny-1-(position-y_start);digit=(y_bcd>>(digit_index*4))&15;code=48+digit;
  end else if(position==y_start+ny)code=")";
 end
endmodule
