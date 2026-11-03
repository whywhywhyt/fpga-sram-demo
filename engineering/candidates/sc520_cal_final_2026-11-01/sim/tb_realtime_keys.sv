`timescale 1ns/1ps
module tb_realtime_keys;
 reg completed=0;
 reg sys=0,cam=0,rst=0,run_cam=1,bursty=0;always #10 sys=~sys;
 integer gate=0;always #7 begin gate=gate+1;if(run_cam&&(!bursty||gate%19<3))cam=~cam;else cam=0;end
 reg[3:0]keys=15;reg[2:0]status=2;wire[2:0]mode;wire[7:0]bt,et,rt;wire[1:0]strength;
 wire cap,tog,clr,on,bg,eff,pen,pc,col,home;
 realtime_mode_control #(.CLOCK_HZ(100),.DEBOUNCE_CYCLES(3))dut(
 .sys_clk(sys),.cam_clk(cam),.rst_n(rst),.buttons(keys),.wall_status(status),
 .mode(mode),.binary_threshold(bt),.edge_threshold(et),.red_threshold(rt),.target_color(strength),
 .cal_capture(cap),.cal_toggle(tog),.cal_clear(clr),.wall_enabled(on),.capture_request(bg),
 .effect_request(eff),.pen_toggle(pen),.paint_clear(pc),.color_request(col),.home_request(home));
 integer homes=0,bgs=0,effs=0,checks=0,received=0,produced=0;
 reg[1:0]expected[0:31];reg[30:0]held;reg was_waiting=0;
 task cycles(input integer n);repeat(n)@(negedge sys);endtask
 task press(input[3:0]k,input integer n);begin keys=k;cycles(n);keys=15;cycles(15);end endtask
 task check(input bit ok,input string why);begin if(!ok)$fatal(1,"%s",why);checks++;end endtask
 always @(posedge sys)begin #1;
 if(home)homes++;if(bg)bgs++;if(eff)effs++;
 if(dut.src_capture||dut.src_toggle||dut.src_clear)begin
  expected[produced]=dut.src_clear?3:(dut.src_toggle?2:1);produced++;
 end
 // A request must hold all payload bits through receiver copy and ACK.
 if(rst)begin
  if(was_waiting&&dut.request!=dut.ack_s2&&dut.mailbox!==held)$fatal(1,"CDC payload changed in flight");
  held=dut.mailbox;was_waiting=dut.request!=dut.ack_s2;
 end else was_waiting=0;
 end
 always @(posedge cam)begin #2;
 if(rst&&(cap||tog||clr))begin
  if(received>=produced||(clr?3:(tog?2:1))!==expected[received])$fatal(1,"CAL lost/duplicated/reordered %0d",received);
  received++;
 end
 if(rst)begin
  if(mode>7||strength<1||strength>3||bt<8||bt>248||et<8||et>248||rt<8||rt>120)$fatal(1,"incoherent camera config");
 end
 end
 integer q;
 initial begin
 cycles(5);rst=1;cycles(30);check(!on&&mode==3,"reset defaults");
 // Exact timing relative to the debounced system-domain K3; camera halted.
 run_cam=0;cycles(5);keys=11;wait(dut.keys.qualified[2]==0);
 cycles(140);check(!on,"power boundary early while camera stopped");cycles(12);
 check(on&&homes==1,"150 system ticks enable without camera clock");cycles(700);
 check(on&&homes==1&&bgs==0,"long hold has no repeated/short action");keys=15;cycles(15);
 check(dut.keys.edge_threshold==96&&mode==3,"no hidden image action on release");
 press(13,20);press(14,20);press(11,20); // RGB -> gray (K3 unused)
 press(14,20);press(11,20); // binary threshold 104
 check(mode==3&&dut.src_mode==2&&dut.src_binary==104,"camera stop holds destination, source remains responsive");
 // Deprecated long K2 does nothing; repeated recaptures stay ordered while camera is stopped.
 press(13,130);press(13,130);press(12,180);press(12,360);press(12,180);press(12,360);
 check(produced==4&&received==0,"four CAL commands queued while camera stopped");
 run_cam=1;bursty=1;cycles(1000);
 check(received==produced&&mode==0&&bt==104&&et==96,"bursty camera receives ordered commands and coherent config");
 press(7,20);check(effs==1,"wall effect works under bursty camera");
 press(11,180);check(!on&&homes==1&&bgs==0,"OFF independent of camera duty");
 for(q=0;q<3;q++)press(7,20);check(effs==1,"no hidden effect changes while OFF");
 press(11,180);check(on&&homes==2,"reopen always requests LIVE");
 press(11,20);check(bgs==1,"short capture after reopen");
 // Rapid configuration changes coalesce to the latest complete tuple.
 run_cam=0;cycles(10);press(14,20);press(14,20);press(11,20);press(11,20);
 run_cam=1;cycles(500);check(mode==2&&bt==120&&et==96&&rt==32,"latest coherent thresholds after stopped camera");
 run_cam=0;cycles(5);press(12,180);check(produced==5&&received==4,"one pending CAL before reset");
 rst=0;cycles(5);produced=0;received=0;rst=1;run_cam=1;bursty=0;cycles(100);
 check(!on&&mode==3&&bt==96&&et==96&&received==0,"reset clears power, mailbox and pending commands");
 completed=1;$display("PASS realtime keys: %0d checks; stopped/bursty camera, system-clock hold, coherent CDC, ordered repeated CAL captures and removed bypass, OFF gating, reset",checks);$finish;
 end
 initial begin #10000000;$fatal(1,"realtime watchdog");end
endmodule

// Exercise the production defaults with a real 20ns oscillator period,
// rather than deriving wall time from the accelerated-count unit tests.
module tb_realtime_50m;
 reg clk=0,rst=0;always #10 clk=~clk;
 reg[3:0]buttons=15;wire on,home;wire[2:0]mode;wire[7:0]edge_threshold;
 reg completed=0;time pressed,elapsed;integer homes=0;
 realtime_mode_control dut(.sys_clk(clk),.cam_clk(1'b0),.rst_n(rst),.buttons(buttons),.wall_status(3'd2),
 .mode(mode),.binary_threshold(),.edge_threshold(edge_threshold),.red_threshold(),.target_color(),
 .cal_capture(),.cal_toggle(),.cal_clear(),.wall_enabled(on),.capture_request(),.effect_request(),
 .pen_toggle(),.paint_clear(),.color_request(),.home_request(home));
 always @(posedge home)homes++;
 initial begin
 #100;rst=1;#100;buttons=11;pressed=$time;
 #1490000000;if(on)$fatal(1,"50MHz default timer triggered before 1.49s");
 @(posedge on);elapsed=$time-pressed;
 if(elapsed<1509000000||elapsed>1511000000)$fatal(1,"50MHz timing %0t instead of 1.51s including debounce",elapsed);
 #20000000;if(!on||homes!=1)$fatal(1,"full-clock hold repeated");
 buttons=15;#11000000;
 if(!on||homes!=1||mode!==3'd3||edge_threshold!==8'd96||dut.src_mode!==3'd3||dut.src_edge!==8'd96)$fatal(1,"full-clock release caused extra action");
 completed=1;$display("PASS production 50MHz timing: %0t from press including 10ms debounce; camera held stopped, one toggle, no threshold or mode action",elapsed);$finish;
 end
 initial begin #1600000000;$fatal(1,"50MHz hold watchdog");end
endmodule
