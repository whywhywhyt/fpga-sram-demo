// Independent capture/analysis banks. A busy analysis bank is never overwritten.
// Completed frames may be skipped if the bounded processor has not finished;
// dropped captures are counted instead of tearing a map under the processor.
module shape_detector_96 #(
    parameter integer IMG_WIDTH=1280,IMG_HEIGHT=720,QLOG=12
)(
    input wire clk,rst_n,user,valid,enable,
    input wire [95:0] data,
    input wire [7:0] margin,
    output reg result_valid,result_overflow,
    output reg [255:0] result_boxes,
    output reg [2:0] result_shown,
    output reg [7:0] result_total,result_margin,
    output reg [15:0] result_frame,
    output wire [15:0] capture_frame,
    output reg [15:0] skipped_frames
);
    localparam CELLS=(IMG_WIDTH/4)*(IMG_HEIGHT/4);
    wire cap_we,cap_complete;
    wire [15:0] cap_addr,cap_frame;
    wire [2:0] cap_color;
    wire [7:0] cap_margin;
    shape_color_vote_96 #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT)) vote(
        .clk(clk),.rst_n(rst_n),.user(user),.valid(valid),.enable(enable),.data(data),.margin(margin),
        .tile_valid(cap_we),.frame_complete(cap_complete),.tile_addr(cap_addr),.tile_frame(cap_frame),
        .tile_color(cap_color),.tile_margin(cap_margin),.capture_frame(capture_frame));
    reg cap_bank,process_bank,core_start;
    wire core_busy,core_done,core_overflow,core_we;
    wire [15:0] core_addr;
    wire [2:0] core_wdata;
    reg [2:0] map0[0:CELLS-1],map1[0:CELLS-1];
    reg [2:0] q0,q1;
    wire we0=(cap_we && !cap_bank) || (core_we && !process_bank);
    wire we1=(cap_we && cap_bank) || (core_we && process_bank);
    wire [15:0] wa0=cap_we && !cap_bank?cap_addr:core_addr;
    wire [15:0] wa1=cap_we && cap_bank?cap_addr:core_addr;
    wire [2:0] wd0=cap_we && !cap_bank?cap_color:core_wdata;
    wire [2:0] wd1=cap_we && cap_bank?cap_color:core_wdata;
    always @(posedge clk)begin
        if(we0)map0[wa0]<=wd0;if(we1)map1[wa1]<=wd1;
        q0<=map0[core_addr];q1<=map1[core_addr];
    end
    wire [255:0] core_boxes;
    wire [2:0] core_shown;
    wire [7:0] core_total;
    reg [7:0] core_margin;
    reg [15:0] core_frame;
    reg history_ready,core_session_ok;
    wire [15:0] history_age=core_frame-result_frame;
    wire history_enable=history_ready && result_valid && core_margin==result_margin &&
        history_age<=16'd3;
    shape_ccl #(.GRID_W(IMG_WIDTH/4),.GRID_H(IMG_HEIGHT/4),.QLOG(QLOG),.STABILIZE(1)) ccl(
        .clk(clk),.rst_n(rst_n),.start(core_start),.busy(core_busy),.done(core_done),.overflow(core_overflow),
        .history_enable(history_enable),
        .history_boxes(result_boxes),
        .mem_addr(core_addr),.mem_data(process_bank?q1:q0),.mem_we(core_we),.mem_wdata(core_wdata),
        .boxes(core_boxes),.shown(core_shown),.total(core_total));
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            cap_bank<=0;process_bank<=1;core_start<=0;core_margin<=0;core_frame<=0;
            result_valid<=0;result_overflow<=0;result_boxes<=0;result_shown<=0;result_total<=0;
            result_margin<=0;result_frame<=0;skipped_frames<=0;history_ready<=0;core_session_ok<=0;
        end else begin
            core_start<=0;
            if(core_start)core_session_ok<=enable;
            if(!enable)begin history_ready<=0;core_session_ok<=0;end
            if(cap_complete)begin
                if(!core_busy && !core_start)begin
                    process_bank<=cap_bank;cap_bank<=!cap_bank;core_start<=1;
                    core_margin<=cap_margin;core_frame<=cap_frame;
                end else skipped_frames<=skipped_frames+1'b1;
            end
            if(core_done)begin
                result_valid<=!core_overflow;result_overflow<=core_overflow;
                result_boxes<=core_boxes;result_shown<=core_shown;result_total<=core_total;
                result_margin<=core_margin;result_frame<=core_frame;
                history_ready<=enable && core_session_ok && !core_overflow;
            end
        end
    end
endmodule
