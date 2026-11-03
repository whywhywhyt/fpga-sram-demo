`timescale 1ns/1ps
module tb_wall_switch_output;
 reg completed=0;
 reg clk=0,rst=0,en=0,start=0,valid=1;always #10 clk=~clk;
 reg[23:0]word=24'h1935a7;wire ready,data,busy,done,enabled;
 wall_output_switch dut(.clk(clk),.rst_n(rst),.enable_async(en),.start(start),
  .word_data(word),.word_valid(valid),.word_ready(ready),.data(data),.busy(busy),.done(done),.enabled(enabled));
 integer words=0,bits=0,frames=0,dones=0,accepted=0,frame_progress=0;
 always @(posedge clk)begin if(done)dones++;if(ready&&valid)accepted++;end
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task request_frame;begin @(negedge clk);start=1;@(negedge clk);start=0;end endtask
 // Decode actual output pulse widths, independent of the serializer shift reg.
 task read_frame(input[23:0]expected);
  time rise_time,high_time;reg[23:0]received;integer p,b;
  begin
   frame_progress=0;
   for(p=0;p<512;p++)begin
    received=0;
    for(b=0;b<24;b++)begin
     @(posedge data);rise_time=$time;@(negedge data);high_time=$time-rise_time;
     if(high_time!=400 && high_time!=800)$fatal(1,"truncated/invalid pulse %0t",high_time);
     received={received[22:0],high_time==800};bits++;
    end
    if(received!==expected)$fatal(1,"frame%0d word%0d got%h expected%h",frames,p,received,expected);
    words++;frame_progress=p+1;
   end
   frames++;
  end
 endtask
 initial begin
  #73;rst=1;
  // No camera/start traffic at all: both panels must repeatedly receive black.
  read_frame(0);read_frame(0);
  if(enabled||dones||accepted)$fatal(1,"autonomous black falsely acknowledged camera");
  en=1;word=24'h1935a7;request_frame();
  // Disable well inside an active colored frame: it must finish unmodified.
  fork
   read_frame(24'h1935a7);
   begin wait(frame_progress>=32);@(negedge clk);en=0;end
  join
  read_frame(0);
  if(dones!=1||accepted!=512)$fatal(1,"colored engine frame count %0d/%0d",dones,accepted);
  // Start arrives while a black frame owns the wire: preserve it until idle.
  fork
   read_frame(0);
   begin wait(frame_progress>=32);@(negedge clk);en=1;word=24'hbc8721;request_frame();end
  join
  read_frame(24'hbc8721);cycles(15100);
  if(dones!=2||accepted!=1024)$fatal(1,"queued engine frame lost/duplicated");
  // A camera request while disabled still gets consumed/acknowledged as black.
  en=0;
  fork
   read_frame(0);
   begin wait(frame_progress>=32);request_frame();end
  join
  read_frame(0);cycles(15100);
  if(dones!=3||accepted!=1536)$fatal(1,"muted camera acknowledgement");
  // Reset clears enable synchronizers, irrespective of previous enabled state.
  @(negedge clk);rst=0;en=0;cycles(5);rst=1;
  read_frame(0);if(enabled)$fatal(1,"reset not muted");
  completed=1;
  $display("PASS wall switch output: %0d full 512-pixel frames, %0d decoded GRB words, %0d exact pulses; camera-free black, frame-atomic mute, queued restart, muted acknowledgements, reset",frames,words,bits);$finish;
 end
 initial begin #250000000;$fatal(1,"output watchdog");end
endmodule
