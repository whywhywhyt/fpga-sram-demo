`timescale 1ns/1ps

module ws2812_stream_tx #(
    parameter integer PIXEL_COUNT = 512,
    parameter integer BIT_CYCLES = 63,
    parameter integer T0H_CYCLES = 20,
    parameter integer T1H_CYCLES = 40,
    parameter integer RESET_CYCLES = 15000
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        frame_start,
    input  wire [23:0] pixel_data,
    input  wire        pixel_valid,
    output wire        pixel_ready,
    output reg         ws_data,
    output reg         frame_done,
    output wire        busy
);

    localparam [1:0] ST_IDLE  = 2'd0;
    localparam [1:0] ST_LOAD  = 2'd1;
    localparam [1:0] ST_BITS  = 2'd2;
    localparam [1:0] ST_RESET = 2'd3;
    localparam integer PIXEL_W = (PIXEL_COUNT <= 1) ? 1 : $clog2(PIXEL_COUNT + 1);
    localparam integer BIT_W = (BIT_CYCLES <= 1) ? 1 : $clog2(BIT_CYCLES);
    localparam integer RESET_W = (RESET_CYCLES <= 1) ? 1 : $clog2(RESET_CYCLES);

    reg [1:0] state;
    reg [23:0] shift_data;
    reg [BIT_W-1:0] bit_cycle;
    reg [4:0] bits_left;
    reg [PIXEL_W-1:0] pixels_left;
    reg [RESET_W-1:0] reset_cycle;

    assign pixel_ready = (state == ST_LOAD);
    assign busy = (state != ST_IDLE);

    always @* begin
        ws_data = 1'b0;
        if ((state == ST_BITS) && shift_data[23])
            ws_data = (bit_cycle < T1H_CYCLES);
        else if (state == ST_BITS)
            ws_data = (bit_cycle < T0H_CYCLES);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= ST_IDLE;
            shift_data  <= 24'd0;
            bit_cycle   <= {BIT_W{1'b0}};
            bits_left   <= 5'd0;
            pixels_left <= {PIXEL_W{1'b0}};
            reset_cycle <= {RESET_W{1'b0}};
            frame_done  <= 1'b0;
        end else begin
            frame_done <= 1'b0;
            case (state)
                ST_IDLE: begin
                    if (frame_start) begin
                        pixels_left <= PIXEL_COUNT;
                        state <= ST_LOAD;
                    end
                end

                ST_LOAD: begin
                    if (pixel_valid) begin
                        shift_data <= pixel_data;
                        bits_left <= 5'd24;
                        bit_cycle <= {BIT_W{1'b0}};
                        state <= ST_BITS;
                    end
                end

                ST_BITS: begin
                    if (bit_cycle == BIT_CYCLES - 1) begin
                        bit_cycle <= {BIT_W{1'b0}};
                        if (bits_left == 1) begin
                            if (pixels_left == 1) begin
                                reset_cycle <= {RESET_W{1'b0}};
                                state <= ST_RESET;
                            end else begin
                                pixels_left <= pixels_left - 1'b1;
                                state <= ST_LOAD;
                            end
                        end else begin
                            bits_left <= bits_left - 1'b1;
                            shift_data <= {shift_data[22:0], 1'b0};
                        end
                    end else begin
                        bit_cycle <= bit_cycle + 1'b1;
                    end
                end

                ST_RESET: begin
                    if (reset_cycle == RESET_CYCLES - 1) begin
                        state <= ST_IDLE;
                        frame_done <= 1'b1;
                    end else begin
                        reset_cycle <= reset_cycle + 1'b1;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
