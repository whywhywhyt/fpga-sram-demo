`timescale 1ns/1ps
`include "vector_count.vh"
module tb_light_painter;
    localparam N=512,F=`TEST_FRAMES;
    reg clk=0,rst_n=0;
    always #10 clk=~clk;
    reg tv=0,start=0,cap=0,eff=0;
    reg [8:0] addr=0,rd=0;
    reg [23:0] rgb=0;
    wire [23:0] out;
    wire busy,done;
    wire [2:0] status;
    wire [9:0] count;
    wall_light_painter #(.WARMUP_FRAMES(2),.CAL_FRAMES(4)) dut(
        .clk(clk),.rst_n(rst_n),.tile_valid(tv),.tile_addr(addr),.tile_rgb(rgb),
        .marker_valid(1'b0),.marker_x(5'd0),.marker_y(4'd0),.color_request(1'b0),.brush_color(),.pen_toggle(1'b0),.paint_clear(1'b0),
        .frame_start(start),.home_request(1'b0),.capture_request(cap),.effect_request(eff),.read_addr(rd),
        .read_rgb(out),.busy(busy),.frame_done(done),.status(status),.foreground_count(count));
    reg [23:0] inputs[0:N*F-1],expected[0:N*F-1];
    reg [1:0] commands[0:F-1];
    reg [2:0] states[0:F-1];
    reg [9:0] counts[0:F-1];
    integer f,i,checks=0;
    initial begin
        $readmemh("input_rgb.hex",inputs);$readmemh("expected_rgb.hex",expected);
        $readmemh("commands.hex",commands);$readmemh("status.hex",states);$readmemh("counts.hex",counts);
        #70;rst_n=1;wait(!busy);
        for(f=0;f<F;f=f+1)begin
            @(negedge clk);cap=commands[f][0];eff=commands[f][1];
            @(negedge clk);cap=0;eff=0;
            for(i=0;i<N;i=i+1)begin @(negedge clk);tv=1;addr=i;rgb=inputs[f*N+i];end
            @(negedge clk);tv=0;start=1;
            @(negedge clk);start=0;
            wait(done);@(negedge clk);
            if(status!==states[f] || count!==counts[f])$fatal(1,"frame%0d status=%0d/%0d count=%0d/%0d",f,status,states[f],count,counts[f]);
            for(i=0;i<N;i=i+1)begin
                rd=i;@(posedge clk);#1;
                if(out!==expected[f*N+i])$fatal(1,"frame%0d pixel%0d actual=%h expected=%h effect=%0d phase=%0d center=(%0d,%0d) old=(%0d,%0d) trail=%h target=%0d ripple_dist=%0d ripple_error=%0d hue=%0d fast=%0d",f,i,out,expected[f*N+i],dut.frame_effect,dut.ripple_phase,dut.center_x,dut.center_y,dut.old_center_x,dut.old_center_y,dut.trail[i],dut.target,dut.ripple_dist,dut.ripple_error,dut.hue,dut.fast_hue);
                checks=checks+1;@(negedge clk);
            end
            if(f%20==0)$display("CHECKED frame %0d status %0d foreground %0d",f,status,count);
        end
        // Explicit reset guarantees a held artwork cannot survive restart.
        rst_n=0;#70;rst_n=1;wait(!busy);
        for(i=0;i<N;i=i+1)begin rd=i;@(posedge clk);#1;if(out!==0)$fatal(1,"reset left stale light");@(negedge clk);end
        $display("PASS painter: %0d frames / %0d independent pixel comparisons; fixed background, noise rejection, stationary retention, velocity hue, contour, halo, fade-to-zero, centered paint strokes, freeze, octagonal ripple expansion, resume, recapture, reset",F,checks);
        $finish;
    end
    initial begin #150000000;$fatal(1,"painter watchdog");end
endmodule
