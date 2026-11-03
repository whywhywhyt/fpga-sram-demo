`timescale 1ns/1ps
module tb_wall_switch_keys;
 reg clk=0,rst=0;always #5 clk=~clk;
 reg[3:0]keys=15;reg[2:0]status=2;wire[2:0]mode;
 wire cap,tog,clr,on,bg,eff,pen,pc,col,home;wire[7:0]bt,et,rt;wire[1:0]strength;
 mode_button_control #(.DEBOUNCE_CYCLES(3),.LONG_PRESS_CYCLES(40)) dut(
 .clk(clk),.rst_n(rst),.buttons(keys),.wall_status(status),.mode(mode),
 .binary_threshold(bt),.edge_threshold(et),.red_threshold(rt),.target_color(strength),
 .cal_capture(cap),.cal_toggle(tog),.cal_clear(clr),.wall_enabled(on),
 .capture_request(bg),.effect_request(eff),.pen_toggle(pen),.paint_clear(pc),.color_request(col),.home_request(home));
 integer caps=0,togs=0,clears=0,bgs=0,effs=0,pens=0,pcs=0,cols=0,homes=0,checks=0;
 always @(posedge clk)begin #1;
 if(cap)caps++;if(tog)togs++;if(clr)clears++;if(bg)bgs++;if(eff)effs++;
 if(pen)pens++;if(pc)pcs++;if(col)cols++;if(home)homes++;
 if((cap+tog+clr)>1)$fatal(1,"multiple CAL commands");
 end
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task press(input[3:0]k,input integer n);begin keys=k;cycles(n);keys=15;cycles(12);end endtask
 task check(input bit ok,input string why);begin if(!ok)$fatal(1,"%s",why);checks++;end endtask
 integer j;reg[7:0]saved;
 initial begin
 cycles(4);rst=1;cycles(12);
 check(!on&&mode==3,"reset OFF PREWITT");
 press(11,2);check(et==96&&!on,"bounce ignored");
 keys=11;cycles(20);check(et==96,"threshold waits for release");keys=15;cycles(12);
 check(et==104&&!on,"short K3 edge threshold");press(7,16);check(et==96,"short K4 edge threshold");
 keys=11;cycles(52);check(!on&&et==96,"power must not trigger early");cycles(25);
 check(on&&et==96&&homes==1&&mode==3,"long K3 enables at threshold only");cycles(300);
 check(on&&homes==1,"hold does not repeat");keys=15;cycles(12);check(et==96&&mode==3,"long release does not change threshold/mode");
 press(11,90);check(!on&&et==96&&homes==1,"long K3 switches OFF once");
 press(14,160);check(mode==4&&!on,"long K1 switches image once; never wall");
 press(11,16);check(strength==3,"enhance up");press(7,16);check(strength==2,"enhance down");
 press(14,16);check(mode==5,"SHAPES selectable");press(11,16);check(rt==40,"recognition threshold up");press(7,16);check(rt==32,"recognition threshold down");
 press(13,16);check(mode==0&&togs==0,"short K2 RGB no CAL");
 press(7,16);press(11,16);check(effs==0&&bgs==0,"OFF ignores wall effects/background");
 press(11,90);check(on&&mode==0&&homes==2&&bgs==0,"enable RGB goes HOME without capture");
 keys=11;cycles(20);check(bgs==0,"background not captured on press");keys=15;cycles(12);check(bgs==1,"short K3 captures background once");
 press(7,16);check(effs==1,"short K4 effect");
 status=3;press(11,16);check(pens==1&&bgs==1,"DRAW short K3 pen only");
 press(7,90);check(cols==1&&effs==1,"DRAW long K4 color only");
 press(7,16);check(effs==2&&cols==1,"DRAW short K4 effect only");
 keys=3;cycles(160);check(pcs==1&&pens==1&&cols==1&&on,"held clear chord no power/color/pen");
 keys=7;cycles(30);keys=15;cycles(12);check(pcs==1&&effs==2&&on,"staggered clear release consumed");
 keys=7;cycles(12);keys=3;cycles(55);keys=11;cycles(40);keys=15;cycles(12);
 check(pcs==2&&cols==1&&effs==2&&on,"K4 first clear, reversed release");
 keys=11;cycles(12);keys=3;cycles(12);keys=15;cycles(12);
 check(pcs==2&&pens==1&&on,"short chord cancels singles");
 press(11,90);check(!on&&pens==1&&pcs==2,"DRAW long K3 power not clear/pen");
 press(7,16);check(effs==2,"OFF cannot silently select DRAW");
 status=2;press(11,90);check(on&&homes==3,"reopen home");
 press(12,70);check(caps==1&&clears==0&&togs==0&&on&&mode==0,"CAL capture preserved");
 press(12,150);check(caps==2&&clears==0&&togs==0&&on,"long CAL chord recaptures without erasing");
 keys=13;cycles(15);keys=12;cycles(70);keys=14;cycles(20);keys=15;cycles(12);
 check(caps==3&&clears==0&&togs==0,"CAL staggered K2-first");
 keys=14;cycles(15);keys=12;cycles(70);keys=13;cycles(20);keys=15;cycles(12);
 check(caps==4&&togs==0,"CAL staggered K1-first");
 press(13,70);check(togs==0&&caps==4&&clears==0,"long K2 never bypasses or erases calibration");
 press(14,16);press(14,16);check(mode==2,"BINARY selectable");
 press(11,16);check(bt==104,"binary threshold up");press(7,16);check(bt==96,"binary down");
 for(j=0;j<24;j++)press(7,16);check(bt==8,"threshold lower clamp");
 for(j=0;j<35;j++)press(11,16);check(bt==248,"threshold upper clamp");
 // K3 press starts in BINARY; K1 changes mode before its release.
 saved=et;keys=11;cycles(15);keys=10;cycles(15);keys=11;cycles(12);keys=15;cycles(12);
 check(mode==3&&et==saved,"cross-mode release cancelled");
 press(3,100);check(on&&et==saved&&pcs==2,"non-DRAW chord does not power/adjust/clear");
 rst=0;cycles(4);rst=1;cycles(12);check(!on&&mode==3&&et==96,"reset OFF");
 $display("PASS wall switch keys: %0d checks; global K3, exact scaled boundary, release-only shorts, no repeats, threshold clamps, mode guard, paint chord, CAL retained",checks);$finish;
 end
 initial begin #1000000;$fatal(1,"key watchdog");end
endmodule
