// Authored single-color tracker; no identity recognition. Two hits acquire.
// Keep the last box for HOLD_FRAMES misses, clear on the following miss.
// Sixteen centers, newest in [21:0], sampled every four successful tracking
// frames. History freezes on misses and clears on full loss/mode exit.
module box_tracker #(parameter integer HOLD_FRAMES=30)(
    input wire clk,rst_n,clear,sample,detected,
    input wire [10:0] xmin,xmax,ymin,ymax,
    output reg [1:0] state,
    output wire visible,
    output reg [10:0] txmin,txmax,tymin,tymax,
    output reg [351:0] trail_points,
    output reg [4:0] trail_count
);
    localparam LOST=2'd0,ACQUIRE=2'd1,TRACK=2'd2,HOLD=2'd3;
    localparam MISS_BITS=$clog2(HOLD_FRAMES+1);
    reg [MISS_BITS-1:0] misses;
    reg [1:0] trail_phase;
    // Suppress <=2px edge noise; follow large moves directly to limit lag.
    function [10:0] stable_edge;
        input [10:0] old_edge,new_edge;
        reg [10:0] distance;
        reg [11:0] sum;
        begin
            distance=new_edge>=old_edge?new_edge-old_edge:old_edge-new_edge;
            sum={1'b0,old_edge}+{1'b0,new_edge}+12'd1;
            stable_edge=distance<=2?old_edge:distance>=16?new_edge:sum[11:1];
        end
    endfunction
    wire [10:0] nx0=state==ACQUIRE?xmin:stable_edge(txmin,xmin),nx1=state==ACQUIRE?xmax:stable_edge(txmax,xmax);
    wire [10:0] ny0=state==ACQUIRE?ymin:stable_edge(tymin,ymin),ny1=state==ACQUIRE?ymax:stable_edge(tymax,ymax);
    wire [11:0] center_x_sum={1'b0,nx0}+{1'b0,nx1},center_y_sum={1'b0,ny0}+{1'b0,ny1};
    assign visible=state==TRACK || state==HOLD;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=LOST;misses<=0;txmin<=0;txmax<=0;tymin<=0;tymax<=0;
            trail_points<=0;trail_count<=0;trail_phase<=0;
        end else if(clear)begin
            state<=LOST;misses<=0;txmin<=0;txmax<=0;tymin<=0;tymax<=0;
            trail_points<=0;trail_count<=0;trail_phase<=0;
        end else if(sample)begin
            if(detected)begin
                misses<=0;
                if(state==LOST)state<=ACQUIRE;
                else begin
                    state<=TRACK;txmin<=nx0;txmax<=nx1;tymin<=ny0;tymax<=ny1;
                    if(state==ACQUIRE || trail_phase==3)begin
                        trail_points<={trail_points[329:0],center_x_sum[11:1],center_y_sum[11:1]};
                        if(trail_count<16)trail_count<=trail_count+1'b1;
                        trail_phase<=0;
                    end else trail_phase<=trail_phase+1'b1;
                end
            end else if(state==TRACK || state==HOLD)begin
                if(misses==HOLD_FRAMES)begin
                    state<=LOST;misses<=0;txmin<=0;txmax<=0;tymin<=0;tymax<=0;
                    trail_points<=0;trail_count<=0;trail_phase<=0;
                end else begin state<=HOLD;misses<=misses+1'b1;end
            end else begin state<=LOST;misses<=0;end
        end
    end
endmodule
