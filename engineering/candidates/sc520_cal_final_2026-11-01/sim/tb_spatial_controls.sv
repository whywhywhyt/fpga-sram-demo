`timescale 1ns/1ps
module tb_spatial_controls;
 reg clk=0,rst=0;always #5 clk=~clk;
 reg[3:0]buttons=15;wire[2:0]mode;wire cap,tog,clear;
 mode_button_control #(.DEBOUNCE_CYCLES(3),.LONG_PRESS_CYCLES(30)) keys(
 .clk(clk),.rst_n(rst),.buttons(buttons),.mode(mode),.binary_threshold(),.edge_threshold(),.red_threshold(),
 .target_color(),.cal_capture(cap),.cal_toggle(tog),.cal_clear(clear),.wall_enabled(),.wall_status(3'd2),.capture_request(),.effect_request(),.pen_toggle(),.paint_clear(),.color_request(),.home_request());
 integer caps=0,togs=0,clears=0;
 always @(posedge clk)begin #1;if(cap)caps++;if(tog)togs++;if(clear)clears++;end
 task waitcycles(input integer n);begin repeat(n)@(negedge clk);end endtask
 task press(input[3:0]k,input integer n);begin @(negedge clk);buttons=k;waitcycles(n);buttons=15;waitcycles(12);end endtask
 reg u=0,v=0;reg[159:0]sp=0;wire[95:0]rgb;wire ov;
 frame_status_96 #(.IMG_WIDTH(1280),.IMG_HEIGHT(720)) panel(.clk(clk),.rst_n(rst),.I_tlast(1'b0),
 .I_tuser(u),.I_tvalid(v),.I_tdata({4{24'h234567}}),.I_mode(3'd0),.I_threshold(8'd96),
 .I_awb_diag(173'd0),.I_spatial_diag(sp),.O_tlast(),.O_tuser(),.O_tvalid(ov),.O_tdata(rgb));
 integer frame,x,y,cells=0,pos,line,ch;
 string expect_line[0:3];reg[159:0]snap;
 initial begin
  waitcycles(4);rst=1;waitcycles(8);
  press(4'b1101,12);if(caps||togs||clears || mode!=0)$fatal(1,"short K2 changed calibration");
  press(4'b1110,12);if(mode!=1)$fatal(1,"short K1 mode regression");
  press(4'b1100,48);if(caps!=1||togs||clears||mode!=0)$fatal(1,"one-second chord capture failed");
  press(4'b1101,48);if(caps!=1||togs!=0||clears||mode!=0)$fatal(1,"long K2 must not emit bypass");
  press(4'b1100,110);if(caps!=2||togs!=0||clears!=0)$fatal(1,"long chord must capture instead of erase");
  press(4'b1100,15);if(caps!=2||togs!=0||clears!=0)$fatal(1,"short chord triggered calibration");
  // Staggered releases and K2-before-K1 must not become an extra toggle.
  buttons=13;waitcycles(12);buttons=12;waitcycles(48);buttons=14;waitcycles(15);buttons=15;waitcycles(12);
  if(caps!=3||togs!=0||clears!=0)$fatal(1,"staggered chord release");
  for(frame=0;frame<5;frame++)begin
   snap={8'h12,16'h1234,16'h2345,16'h3456,16'h1789,16'h1abc,16'h15de,16'h14ef,16'h10ab,16'h0cde,5'd0,(3'(frame+1))};
   case(frame)
    0:expect_line[0]="CAL CAPT  U 12                  ";
    1:expect_line[0]="CAL WORK  U 12                  ";
    2:expect_line[0]="CAL ON    U 12                  ";
    3:expect_line[0]="CAL -     U 12                  ";
    4:expect_line[0]="CAL FAIL  U 12                  ";
   endcase
   expect_line[1]="L R 0CDE B 10AB N 3456          ";
   expect_line[2]="C R 14EF B 15DE N 2345          ";
   expect_line[3]="R R 1ABC B 1789 N 1234          ";
   for(y=0;y<720;y++)for(x=0;x<1280;x+=4)begin
    @(negedge clk);v=1;u=x==0&&y==0;sp=u?snap:~snap;#1;
    if(panel.spatial_area)begin
     line=(y-600)/16;pos=(x-16)/16;ch=expect_line[line].getc(pos);
     if(panel.spatial_code!==ch[7:0])$fatal(1,"cal panel state%0d row%0d pos%0d char%h/%h",frame+1,line,pos,panel.spatial_code,ch);
     cells++;
    end
   end
   @(negedge clk);v=0;u=0;waitcycles(5);
  end
  if(cells!=40960)$fatal(1,"panel raster coverage %0d",cells);
  $display("PASS spatial controls: short/long keys, release-only calibration, no bypass/key erase, staggered release, five status rasters, 40960 atomic diagnostic groups");$finish;
 end
 initial begin #20000000;$fatal(1,"spatial control watchdog");end
endmodule
