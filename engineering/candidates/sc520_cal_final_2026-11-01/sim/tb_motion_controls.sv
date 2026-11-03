`timescale 1ns/1ps
module tb_motion_controls;
 reg clk=0;always #5 clk=~clk;
 reg rst=0;reg [3:0] buttons=15;wire [2:0] mode;wire wall;wire [7:0] edge_th;
 wire cap,tog,clear,home,bg,effect;integer homes=0,caps=0,togs=0;
 mode_button_control #(.DEBOUNCE_CYCLES(3),.LONG_PRESS_CYCLES(40)) keys(
  .clk(clk),.rst_n(rst),.buttons(buttons),.mode(mode),.binary_threshold(),.edge_threshold(edge_th),.red_threshold(),.target_color(),
  .cal_capture(cap),.cal_toggle(tog),.cal_clear(clear),.wall_enabled(wall),.wall_status(3'd2),
  .capture_request(bg),.effect_request(effect),.pen_toggle(),.paint_clear(),.color_request(),.home_request(home));
 always @(posedge clk)begin #1;if(home)homes++;if(cap)caps++;if(tog)togs++;end
 task cycles(input integer n);begin repeat(n)@(negedge clk);end endtask
 task press(input [3:0] b,input integer n);begin buttons=b;cycles(n);buttons=15;cycles(12);end endtask
 reg u=0,v=0,l=0;reg [2:0] ui_mode=0;reg g=0;wire ov,ou,ol;wire [95:0] od;
 presentation_status_96 ui(.clk(clk),.rst_n(rst),.I_tlast(l),.I_tuser(u),.I_tvalid(v),.I_tdata({4{24'h405060}}),
  .I_mode(ui_mode),.I_threshold(8'd96),.I_spatial_diag(160'd4),.I_motion_valid(1'b1),.I_motion_tiles(10'd123),.I_motion_global(g),
  .O_tlast(ol),.O_tuser(ou),.O_tvalid(ov),.O_tdata(od));
 reg [7:0] titles[0:3];integer completed=0,checks=0,f,x,y,pos,code;
 initial begin
  cycles(4);rst=1;cycles(12);
  press(14,12);press(14,12);press(14,12);if(mode!=6)$fatal(1,"mode 6 inaccessible from K1 cycle");
  press(11,12);press(7,12);if(mode!=6||wall||bg||effect)$fatal(1,"motion shorts changed lamp/threshold context");
  press(11,75);if(!wall||mode!=6||homes!=1)$fatal(1,"long K3 wall power broken in motion mode");
  press(14,12);if(mode!=7)$fatal(1,"cartoon mode missing");
  press(11,12);if(edge_th!=104||mode!=7)$fatal(1,"cartoon threshold up");
  press(7,12);if(edge_th!=96||mode!=7)$fatal(1,"cartoon threshold down");
  press(14,12);if(mode!=0)$fatal(1,"K1 did not wrap cartoon to RGB");
  press(13,60);if(togs!=0||caps!=0||mode!=0)$fatal(1,"long K2 emitted a removed calibration bypass");
  press(12,70);if(caps!=1||togs!=0||clear||mode!=0)$fatal(1,"CAL capture chord changed");
  press(11,75);if(wall||homes!=1)$fatal(1,"lamp OFF changed");
  titles[0]=166;titles[1]=167;titles[2]=139;titles[3]=140;
  for(f=0;f<4;f++)begin
   ui_mode=f==3?7:f==2?0:6;g=f==1;
   for(y=0;y<720;y++)for(x=0;x<1280;x+=4)begin
    @(negedge clk);u=x==0&&y==0;v=1;l=x==1276;#1;
    if((f<2||f==3) && x>=192&&x<320&&y==32)begin
     pos=(x-192)/32;if(ui.code!==(f==3?(pos==0?8'd201:pos==1?8'd202:pos==2?8'd179:8'd203):titles[pos]))$fatal(1,"motion Chinese title pos%0d",pos);checks++;
    end
    if(x>=952&&x<1064&&y==64)begin
     pos=(x-952)/16;
     if(f>=2)code=32;
     else if(f==1)code=pos<4?197+pos:32;
     else case(pos)0:code=166;1:code=167;2:code=168;3:code=32;4:code=49;5:code=50;6:code=51;default:code=32;endcase
     if(ui.code!==code[7:0])$fatal(1,"activity/global caption f%0d pos%0d got%0d want%0d",f,pos,ui.code,code);
     checks++;
    end
    if(f==2&&x==952&&y==64&&ui.motion_area)$fatal(1,"activity panel covers original image");
   end
   @(negedge clk);u=0;v=0;l=0;cycles(5);
  end
  completed=1;$display("PASS motion controls: eight modes/wrap and cartoon threshold keys, K2 original without bypass and CAL capture, K3 power independent, Chinese mode/global captions and clean original across 3686400 pixels, checks=%0d",checks);$finish;
 end
 initial begin #20000000;$fatal(1,"motion controls watchdog");end
endmodule
