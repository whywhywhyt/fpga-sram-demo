`timescale 1ns/1ps
module tb_wall_home;
 reg clk=0,rst=0,tv=0,start=0,eff=0,home=0,pen=0;always #10 clk=~clk;
 reg[8:0]addr=0,rd=0;wire[23:0]out;wire busy,done,down;wire[2:0]status;
 wall_light_painter #(.WARMUP_FRAMES(0),.CAL_FRAMES(1))dut(
 .clk(clk),.rst_n(rst),.tile_valid(tv),.tile_addr(addr),.tile_rgb(24'h304050),
 .frame_start(start),.capture_request(1'b0),.effect_request(eff),.home_request(home),
 .marker_valid(1'b1),.marker_x(5'd4),.marker_y(4'd4),.pen_toggle(pen),.paint_clear(1'b0),.color_request(1'b0),
 .brush_color(),.pen_down(down),.canvas_write(),.canvas_addr(),.canvas_rgb(),.read_addr(rd),.read_rgb(out),
 .busy(busy),.frame_done(done),.status(status),.foreground_count());
 integer i,checks=0;
 task pulse_effect;begin @(negedge clk);eff=1;@(negedge clk);eff=0;end endtask
 task frame(input bit home_mid,input bit home_start);
 begin
 wait(!busy);
 for(i=0;i<512;i++)begin @(negedge clk);tv=1;addr=i;end
 @(negedge clk);tv=0;start=1;home=home_start;
 @(negedge clk);start=0;home=0;
 if(home_mid)begin repeat(100)@(negedge clk);home=1;@(negedge clk);home=0;end
 wait(done);@(negedge clk);
 end endtask
 task verify_live;
 begin
 if(dut.effect!=0||status!=2||down||!dut.bg_valid)$fatal(1,"HOME failed or background erased");
 for(i=0;i<512;i++)begin rd=i;@(posedge clk);#1;if(out!==0)$fatal(1,"HOME left stale pixel %0d",i);checks++;@(negedge clk);end
 end endtask
 initial begin
 #73;rst=1;wait(!busy);frame(0,0);frame(0,0);
 pulse_effect();@(negedge clk);pen=1;@(negedge clk);pen=0;frame(0,0);
 if(status!=3||!down)$fatal(1,"DRAW setup");pulse_effect();frame(0,0);if(status!=4)$fatal(1,"HOLD setup");
 frame(0,1);verify_live();
 pulse_effect();frame(0,0);frame(1,0);frame(0,0);verify_live();
 pulse_effect();pulse_effect();pulse_effect();frame(0,0);if(status!=6)$fatal(1,"RIPPLE setup");
 @(negedge clk);home=1;@(negedge clk);home=0;repeat(4)@(negedge clk);frame(0,0);verify_live();
 $display("PASS wall HOME: %0d pixels; HOLD/DRAW/RIPPLE reopen LIVE, pending mid-frame command, coincident SOF, background preserved, pen up and stale trails cleared",checks);$finish;
 end
 initial begin #10000000;$fatal(1,"HOME watchdog");end
endmodule
