module motion_frame_diff_96 #(
    parameter integer IMG_WIDTH = 1280,
    parameter integer IMG_HEIGHT = 720,
    parameter integer TILE_WIDTH = 40,
    parameter integer TILE_HEIGHT = 40,
    parameter integer DIFF_THRESHOLD = 24
)(
    input wire clk,
    input wire rst_n,
    input wire I_tuser,
    input wire I_tvalid,
    input wire I_tlast,
    input wire [95:0] I_tdata,
    output reg result_valid,
    output reg [9:0] moving_tiles
);
    localparam integer GRID_W = IMG_WIDTH / TILE_WIDTH;
    localparam integer GRID_H = IMG_HEIGHT / TILE_HEIGHT;
    localparam integer BEATS_PER_TILE = TILE_WIDTH / 4;
    localparam integer SAMPLE_BEAT = BEATS_PER_TILE / 2;
    localparam integer SAMPLE_ROW = TILE_HEIGHT / 2;
    localparam integer CELL_COUNT = GRID_W * GRID_H;

    reg [7:0] col_in_tile;
    reg [7:0] row_in_tile;
    reg [7:0] tile_x;
    reg [7:0] tile_y;
    reg [10:0] row_y;
    reg [10:0] beat_x;
    reg active;
    reg [7:0] reference_luma [0:CELL_COUNT-1];
    reg [7:0] previous_luma_q;
    reg [7:0] sample_luma_q;
    reg sample_compare_q;
    reg baseline_ready;
    reg [9:0] capture_count;
    reg [9:0] frame_motion_count;

    wire [10:0] current_row_y = I_tuser ? 11'd0 : row_y;
    wire [7:0] current_col_in_tile = I_tuser ? 8'd0 : col_in_tile;
    wire [7:0] current_row_in_tile = I_tuser ? 8'd0 : row_in_tile;
    wire [7:0] current_tile_x = I_tuser ? 8'd0 : tile_x;
    wire [7:0] current_tile_y = I_tuser ? 8'd0 : tile_y;
    wire [10:0] current_beat_x = I_tuser ? 11'd0 : beat_x;
    wire stream_bad = I_tvalid && (active || I_tuser) &&
        (I_tlast != (current_beat_x == IMG_WIDTH/4-1));
    wire sample_now = rst_n && I_tvalid && (active || I_tuser) && !stream_bad &&
        current_col_in_tile == SAMPLE_BEAT && current_row_in_tile == SAMPLE_ROW &&
        current_tile_x < GRID_W && current_tile_y < GRID_H;
    wire [15:0] sample_addr = current_tile_y * GRID_W + current_tile_x;
    wire [23:0] sample_rgb = I_tdata[95:72];
    wire [7:0] luma_r = {2'b0,sample_rgb[23:18]};
    wire [7:0] luma_g = {1'b0,sample_rgb[15:9]};
    wire [7:0] luma_b = {2'b0,sample_rgb[7:2]};
    wire [9:0] luma_sum = {2'b0,luma_r} + {2'b0,luma_g} + {2'b0,luma_b};
    wire [7:0] sample_luma = luma_sum[7:0];
    wire [7:0] luma_diff = sample_luma_q >= previous_luma_q ?
        sample_luma_q - previous_luma_q : previous_luma_q - sample_luma_q;
    wire frame_end = I_tvalid && I_tlast && (active || I_tuser) &&
                     current_row_y == IMG_HEIGHT-1;

    // Mid-cell samples leave at least a full row for the RAM/compare pipeline
    // to drain before EOF. Only these bounded geometries are supported.
    // synthesis translate_off
    initial begin
        if (IMG_WIDTH < 8 || IMG_HEIGHT < 4 ||
            TILE_WIDTH < 8 || TILE_WIDTH > 1020 || TILE_WIDTH % 4 != 0 ||
            TILE_HEIGHT < 4 || TILE_HEIGHT > 256 ||
            IMG_WIDTH % TILE_WIDTH != 0 || IMG_HEIGHT % TILE_HEIGHT != 0 ||
            CELL_COUNT > 1023 || GRID_W > 255 || GRID_H > 255 ||
            IMG_WIDTH > 2048 || IMG_HEIGHT > 2048 ||
            DIFF_THRESHOLD < 1 || DIFF_THRESHOLD > 255) begin
            $display("Unsupported motion detector geometry/threshold");
            $finish;
        end
    end
    // synthesis translate_on

    // This memory is updated once per coarse cell; synchronous read-before-write
    // supplies the previous frame's sample without storing a full video frame.
    always @(posedge clk) begin
        if (sample_now) begin
            previous_luma_q <= reference_luma[sample_addr];
            reference_luma[sample_addr] <= sample_luma;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            col_in_tile <= 0;
            row_in_tile <= 0;
            tile_x <= 0;
            tile_y <= 0;
            row_y <= 0;
            beat_x <= 0;
            active <= 0;
            sample_luma_q <= 0;
            sample_compare_q <= 0;
            baseline_ready <= 0;
            capture_count <= 0;
            frame_motion_count <= 0;
            result_valid <= 0;
            moving_tiles <= 0;
        end else begin
            sample_compare_q <= sample_now && baseline_ready && !(I_tuser && active);
            if (sample_now) begin
                sample_luma_q <= sample_luma;
                if (capture_count != 10'h3ff)
                    capture_count <= capture_count + 1'b1;
            end

            if (I_tuser) begin
                active <= 1;
                beat_x <= I_tvalid && !I_tlast ? 11'd1 : 11'd0;
                if (active) begin
                    // The preceding capture was interrupted after partially
                    // updating RAM. Rebuild a complete reference before use.
                    baseline_ready <= 0;
                    result_valid <= 0;
                    moving_tiles <= 0;
                end
                capture_count <= sample_now ? 10'd1 : 10'd0;
                frame_motion_count <= 0;
                col_in_tile <= 0;
                tile_x <= 0;
                row_in_tile <= 0;
                tile_y <= 0;
                if (I_tvalid && !I_tlast) begin
                    if (BEATS_PER_TILE == 1) begin
                        col_in_tile <= 0;
                        tile_x <= 1;
                    end else begin
                        col_in_tile <= 1;
                        tile_x <= 0;
                    end
                end
                row_y <= I_tvalid && I_tlast ? 11'd1 : 11'd0;
                if (I_tvalid && I_tlast) begin
                    if (TILE_HEIGHT == 1) begin
                        row_in_tile <= 0;
                        tile_y <= 1;
                    end else begin
                        row_in_tile <= 1;
                        tile_y <= 0;
                    end
                end
            end else if (I_tvalid && active) begin
                if (I_tlast) begin
                    beat_x <= 0;
                    col_in_tile <= 0;
                    tile_x <= 0;
                    if (row_y != IMG_HEIGHT-1)
                        row_y <= row_y + 1'b1;
                    else
                        row_y <= 0;
                    if (row_in_tile == TILE_HEIGHT-1) begin
                        row_in_tile <= 0;
                        tile_y <= tile_y + 1'b1;
                    end else begin
                        row_in_tile <= row_in_tile + 1'b1;
                    end
                end else begin
                    beat_x <= beat_x + 1'b1;
                    if (col_in_tile == BEATS_PER_TILE-1) begin
                        col_in_tile <= 0;
                        tile_x <= tile_x + 1'b1;
                    end else begin
                        col_in_tile <= col_in_tile + 1'b1;
                    end
                end
            end

            if (!I_tuser && sample_compare_q && luma_diff >= DIFF_THRESHOLD &&
                frame_motion_count != 10'h3ff)
                frame_motion_count <= frame_motion_count + 1'b1;

            if (frame_end) begin
                active <= 0;
                if (capture_count == CELL_COUNT && !stream_bad) begin
                    result_valid <= baseline_ready;
                    moving_tiles <= baseline_ready ? frame_motion_count : 10'd0;
                    baseline_ready <= 1;
                end else begin
                    result_valid <= 0;
                    moving_tiles <= 0;
                    baseline_ready <= 0;
                end
            end
            if (stream_bad) begin
                active <= 0;
                baseline_ready <= 0;
                sample_compare_q <= 0;
                result_valid <= 0;
                moving_tiles <= 0;
            end
        end
    end
endmodule

module motion_status_overlay_96 #(
    parameter integer IMG_WIDTH = 1280,
    parameter integer IMG_HEIGHT = 720,
    parameter integer PANEL_X = 16,
    parameter integer PANEL_Y = 112,
    parameter integer RENDER = 1
)(
    input wire clk,
    input wire rst_n,
    input wire I_tuser,
    input wire I_tvalid,
    input wire I_tlast,
    input wire [95:0] I_tdata,
    input wire motion_valid,
    input wire [9:0] motion_tiles,
    input wire [2:0] I_mode,
    input wire [7:0] I_threshold,
    output reg O_tuser,
    output reg O_tvalid,
    output reg O_tlast,
    output reg [95:0] O_tdata,
    output reg [2:0] O_mode,
    output reg [7:0] O_threshold
);
    reg [10:0] x;
    reg [10:0] y;
    reg [9:0] frame_tiles;
    reg frame_motion_valid;
    reg [9:0] binary;
    reg [11:0] bcd, decimals;
    reg [3:0] remaining;
    reg [11:0] adjusted;
    // Three real pipeline stages: coordinate decode, glyph row decode, blend.
    // Every stage carries the complete stream and its mode metadata.
    reg [95:0] data_q;
    reg valid_q, user_q, last_q;
    reg [2:0] mode_q;
    reg [7:0] threshold_q;
    reg [95:0] data_q2;
    reg user_q2, valid_q2, last_q2;
    reg [2:0] mode_q2;
    reg [7:0] threshold_q2;
    reg [3:0] panel_q, text_q, bar_q, bar_on_q;
    reg [3:0] panel_q2, text_q2, bar_q2, bar_on_q2;
    reg [3:0] char_q [0:3];
    reg [2:0] col_q [0:3];
    reg [2:0] col_q2 [0:3];
    reg [2:0] row_q;
    reg [4:0] glyph_q2 [0:3];
    reg [23:0] ink_q, ink_q2, activity_q, activity_q2;
    integer digit_index;
    always @(*) begin
        adjusted = bcd;
        for (digit_index=0; digit_index<3; digit_index=digit_index+1)
            if (bcd[digit_index*4 +:4] >= 5)
                adjusted[digit_index*4 +:4] = bcd[digit_index*4 +:4] + 4'd3;
    end
    wire [10:0] px = I_tuser ? 11'd0 : x;
    wire [10:0] py = I_tuser ? 11'd0 : y;
    wire [9:0] shown_tiles = I_tuser ? motion_tiles : frame_tiles;
    wire shown_valid = I_tuser ? motion_valid : frame_motion_valid;
    wire [6:0] rounded_level = {1'b0,shown_tiles[9:4]} +
                               {6'b0,(|shown_tiles[3:0])};
    wire [5:0] bar_level = rounded_level > 32 ? 6'd32 : rounded_level[5:0];
    wire [23:0] activity_color = shown_tiles >= 10'd128 ? 24'hff4040 :
                                 shown_tiles >= 10'd32 ? 24'hffd040 : 24'h40e080;
    function [4:0] glyph_row;
        input [7:0] code;
        input [2:0] row;
        reg [34:0] glyph;
        begin
            case (code)
                8'd77: glyph = 35'b10001100011000110101101011101110001;
                8'd79: glyph = 35'b01110100011000110001100011000101110;
                8'd84: glyph = 35'b00100001000010000100001000010011111;
                8'd73: glyph = 35'b11111001000010000100001000010011111;
                8'd78: glyph = 35'b10001100111001110101110011100110001;
                8'd45: glyph = 35'b00000000000000011111000000000000000;
                8'd48: glyph = 35'b01110100011100110101100111000101110;
                8'd49: glyph = 35'b01110001000010000100001000110000100;
                8'd50: glyph = 35'b11111010000010000010000011000101110;
                8'd51: glyph = 35'b11110000010000101110000010000111110;
                8'd52: glyph = 35'b00010000101111110010010100011000010;
                8'd53: glyph = 35'b11110000010000111110100001000011111;
                8'd54: glyph = 35'b01110100011000111110100001000001110;
                8'd55: glyph = 35'b01000010000100000100000100000111111;
                8'd56: glyph = 35'b01110100011000101110100011000101110;
                8'd57: glyph = 35'b01110000010000101111100011000101110;
                default: glyph = 0;
            endcase
            case (row)
                0: glyph_row = glyph[4:0];
                1: glyph_row = glyph[9:5];
                2: glyph_row = glyph[14:10];
                3: glyph_row = glyph[19:15];
                4: glyph_row = glyph[24:20];
                5: glyph_row = glyph[29:25];
                6: glyph_row = glyph[34:30];
                default: glyph_row = 0;
            endcase
        end
    endfunction

    wire [10:0] text_y = py - (PANEL_Y+8);
    reg shown_valid_q;
    genvar lane;
    generate for (lane=0; lane<4; lane=lane+1) begin: pixels
        wire [11:0] lane_x = {1'b0,px} + lane;
        wire [6:0] text_x = lane_x - (PANEL_X+8);
        wire [6:0] bar_x = lane_x - (PANEL_X+8);
        reg [3:0] char_index;
        reg [6:0] within_char;
        reg [7:0] code;
        always @(*) begin
            if (text_x < 7'd12) begin char_index=0; within_char=text_x; end
            else if (text_x < 7'd24) begin char_index=1; within_char=text_x-7'd12; end
            else if (text_x < 7'd36) begin char_index=2; within_char=text_x-7'd24; end
            else if (text_x < 7'd48) begin char_index=3; within_char=text_x-7'd36; end
            else if (text_x < 7'd60) begin char_index=4; within_char=text_x-7'd48; end
            else if (text_x < 7'd72) begin char_index=5; within_char=text_x-7'd60; end
            else if (text_x < 7'd84) begin char_index=6; within_char=text_x-7'd72; end
            else if (text_x < 7'd96) begin char_index=7; within_char=text_x-7'd84; end
            else if (text_x < 7'd108) begin char_index=8; within_char=text_x-7'd96; end
            else begin char_index=9; within_char=text_x-7'd108; end
            case (char_q[lane])
                0: code=8'd77;
                1,4: code=8'd79;
                2: code=8'd84;
                3: code=8'd73;
                5: code=8'd78;
                7: code=shown_valid_q ? {4'h3,decimals[11:8]} : 8'd45;
                8: code=shown_valid_q ? {4'h3,decimals[7:4]} : 8'd45;
                9: code=shown_valid_q ? {4'h3,decimals[3:0]} : 8'd45;
                default: code=8'd32;
            endcase
        end
        wire text_bit = col_q2[lane] < 5 && glyph_q2[lane][3'd4-col_q2[lane]];
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                panel_q[lane]<=0; text_q[lane]<=0; bar_q[lane]<=0; bar_on_q[lane]<=0;
                panel_q2[lane]<=0; text_q2[lane]<=0; bar_q2[lane]<=0; bar_on_q2[lane]<=0;
                char_q[lane]<=0; col_q[lane]<=0; col_q2[lane]<=0; glyph_q2[lane]<=0;
                O_tdata[95-lane*24 -:24]<=0;
            end else begin
                panel_q[lane] <= RENDER && lane_x>=PANEL_X && lane_x<PANEL_X+160 && py>=PANEL_Y && py<PANEL_Y+48;
                text_q[lane] <= RENDER && lane_x>=PANEL_X+8 && lane_x<PANEL_X+128 && py>=PANEL_Y+8 && py<PANEL_Y+24;
                bar_q[lane] <= RENDER && lane_x>=PANEL_X+8 && lane_x<PANEL_X+136 && py>=PANEL_Y+28 && py<PANEL_Y+40;
                bar_on_q[lane] <= shown_valid && {1'b0,bar_x[6:2]}<bar_level;
                char_q[lane] <= char_index;
                col_q[lane] <= within_char[3:1];
                glyph_q2[lane] <= glyph_row(code,row_q);
                col_q2[lane] <= col_q[lane];
                panel_q2[lane]<=panel_q[lane]; text_q2[lane]<=text_q[lane];
                bar_q2[lane]<=bar_q[lane]; bar_on_q2[lane]<=bar_on_q[lane];
                O_tdata[95-lane*24 -:24] <= !valid_q2 ? 24'd0 :
                    bar_q2[lane] ? (bar_on_q2[lane] ? activity_q2 : 24'h303840) :
                    text_q2[lane] && text_bit ? ink_q2 :
                    panel_q2[lane] ? 24'h101820 : data_q2[95-lane*24 -:24];
            end
        end
    end endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x <= 0;
            y <= 0;
            frame_tiles <= 0;
            frame_motion_valid <= 0;
            binary <= 0;
            bcd <= 0;
            decimals <= 0;
            remaining <= 0;
            data_q <= 0;
            valid_q <= 0;
            user_q <= 0;
            last_q <= 0;
            shown_valid_q <= 0;
            row_q <= 0;
            ink_q <= 0; ink_q2 <= 0; activity_q <= 0; activity_q2 <= 0;
            mode_q <= 0;
            threshold_q <= 0;
            data_q2 <= 0;
            user_q2 <= 0;
            valid_q2 <= 0;
            last_q2 <= 0;
            mode_q2 <= 0;
            threshold_q2 <= 0;
            O_tuser <= 0;
            O_tvalid <= 0;
            O_tlast <= 0;
            O_mode <= 0;
            O_threshold <= 0;
        end else begin
            data_q <= I_tdata;
            valid_q <= I_tvalid;
            user_q <= I_tuser;
            last_q <= I_tlast;
            row_q <= text_y[3:1];
            shown_valid_q <= shown_valid;
            ink_q <= shown_valid ? 24'hf0f8ff : 24'h708090;
            ink_q2 <= ink_q;
            activity_q <= activity_color;
            activity_q2 <= activity_q;
            mode_q <= I_mode;
            threshold_q <= I_threshold;
            data_q2 <= data_q;
            user_q2 <= user_q;
            valid_q2 <= valid_q;
            last_q2 <= last_q;
            mode_q2 <= mode_q;
            threshold_q2 <= threshold_q;
            O_tuser <= user_q2;
            O_tvalid <= valid_q2;
            O_tlast <= last_q2;
            O_mode <= mode_q2;
            O_threshold <= threshold_q2;
            if (I_tuser) begin
                frame_tiles <= motion_tiles;
                frame_motion_valid <= motion_valid;
                binary <= motion_tiles > 999 ? 10'd999 : motion_tiles;
                bcd <= 0;
                remaining <= 10;
                x <= I_tvalid && !I_tlast ? 11'd4 : 11'd0;
                y <= I_tvalid && I_tlast ? 11'd1 : 11'd0;
            end else if (I_tvalid) begin
                if (I_tlast) begin
                    x <= 0;
                    y <= y == IMG_HEIGHT-1 ? 0 : y+1'b1;
                end else begin
                    x <= x + 4;
                end
            end
            if (!I_tuser && remaining != 0) begin
                bcd <= {adjusted[10:0],binary[9]};
                binary <= {binary[8:0],1'b0};
                remaining <= remaining - 1'b1;
                if (remaining == 1)
                    decimals <= {adjusted[10:0],binary[9]};
            end
        end
    end

endmodule

`timescale 1ns/1ps
// Coarse motion localization, not semantic object detection or object counting.
// Sixteen spatially distributed pixels per cell, previous complete-frame luma,
// connected support, largest four-connected component, frame-atomic publication.
module motion_region_detect_96 #(
 parameter integer IMG_WIDTH=1280,IMG_HEIGHT=720,TILE_WIDTH=40,TILE_HEIGHT=40,
 parameter integer DIFF_THRESHOLD=12,MIN_CELLS=4,HOLD_FRAMES=6,
 parameter integer GW=IMG_WIDTH/TILE_WIDTH,GH=IMG_HEIGHT/TILE_HEIGHT,
 parameter integer CELLS=GW*GH,AW=$clog2(CELLS)
)(
 input wire clk,rst_n,I_tuser,I_tvalid,I_tlast,input wire [95:0] I_tdata,
 input wire display_sof,input wire [AW-1:0] map_addr,output reg map_bit,
 output wire result_valid,output wire [9:0] moving_tiles,
 output wire box_visible,global_change,
 output wire [5:0] box_x0,box_x1,output wire [4:0] box_y0,box_y1
);
 localparam BP=TILE_WIDTH/4;
 reg [10:0] beat_x,row_y;
 reg [7:0] cb,cl,tx,ty;
 reg active,baseline,write_bank,process_bank,display_bank,pending_result;
 reg [9:0] samples;
 wire [10:0] bx=I_tuser?0:beat_x,ry=I_tuser?0:row_y;
 wire [7:0] cx=I_tuser?0:cb,cy=I_tuser?0:cl;
 wire [7:0] gx=I_tuser?0:tx,gy=I_tuser?0:ty;
 wire bad=I_tvalid && (active||I_tuser) && (I_tlast!=(bx==IMG_WIDTH/4-1));
 wire sample_now=I_tvalid&&(active||I_tuser)&&!bad&&ry<IMG_HEIGHT&&
  (cy==TILE_HEIGHT/4 || cy==3*TILE_HEIGHT/4)&&
  (cx==BP/4 || cx==3*BP/4);
 wire finish_cell=sample_now && cy==3*TILE_HEIGHT/4 && cx==3*BP/4;
 wire [AW-1:0] sample_addr=gy*GW+gx;
 wire eof=I_tvalid&&I_tlast&&(active||I_tuser)&&ry==IMG_HEIGHT-1;
 function [7:0] luma;
  input [23:0] p;
  begin luma={2'b0,p[23:18]}+{1'b0,p[15:9]}+{2'b0,p[7:2]};end
 endfunction
 wire [9:0] group_sum={2'b0,luma(I_tdata[95:72])}+{2'b0,luma(I_tdata[71:48])}+
  {2'b0,luma(I_tdata[47:24])}+{2'b0,luma(I_tdata[23:0])};
 reg [10:0] row_sum,column_sum[0:GW-1];
 wire [10:0] row_total=row_sum+group_sum;
 wire [11:0] cell_total={1'b0,column_sum[gx]}+{1'b0,row_total}+12'd8;
 (* ram_style="bram" *) reg [7:0] previous[0:CELLS-1];
 reg [7:0] previous_q,sample_q;
 reg [AW-1:0] sample_addr_q;
 reg sample_valid_q,sample_baseline_q,sample_bank_q;
 wire [7:0] difference=sample_q>=previous_q?sample_q-previous_q:previous_q-sample_q;
 (* ram_style="bram" *) reg raw0[0:CELLS-1],raw1[0:CELLS-1];
 (* ram_style="bram" *) reg [1:0] work_mask[0:CELLS-1];
 (* ram_style="bram" *) reg mask0[0:CELLS-1],mask1[0:CELLS-1];
 (* ram_style="bram" *) reg [AW-1:0] queue[0:CELLS-1];
 reg [AW-1:0] raw_addr,work_addr,queue_addr;
 reg raw_q;reg [1:0] work_q;reg [AW-1:0] queue_q;
 wire work_bank=!display_bank;
 wire read_bank=(display_sof&&pending_result)?!display_bank:display_bank;
 // All RAMs use synchronous ports. Capture and processing own separate banks.
 always @(posedge clk)begin
  if(finish_cell)begin previous_q<=previous[sample_addr];previous[sample_addr]<=cell_total[11:4];end
  if(sample_valid_q)begin
   if(sample_bank_q)raw1[sample_addr_q]<=sample_baseline_q&&difference>=DIFF_THRESHOLD;
   else raw0[sample_addr_q]<=sample_baseline_q&&difference>=DIFF_THRESHOLD;
  end
  raw_q<=process_bank?raw1[raw_addr]:raw0[raw_addr];
  work_q<=work_mask[work_addr];queue_q<=queue[queue_addr];
  map_bit<=read_bank?mask1[map_addr]:mask0[map_addr];
 end
 reg [4:0] state;
 localparam IDLE=0,FSET=1,FWAIT=2,FUSE=3,FWRITE=4,SCAN=5,SWAIT=6,SUSE=7,
  QSET=8,QWAIT=9,QUSE=10,NSET=11,NWAIT=12,NUSE=13,NEXT=14,COMPLETE=15,PUBLISH=16;
 reg [AW-1:0] idx,scan_idx,node;
 reg [2:0] neighbor;reg self_bit,adjacent;
 reg [9:0] head,tail,component_count,best_count,filtered_count;
 reg [5:0] minx,maxx,bestx0,bestx1,trackx0,trackx1;
 reg [4:0] miny,maxy,besty0,besty1,tracky0,tracky1;
 wire [5:0] ix=idx%GW,nx=node%GW;
 wire [4:0] iy=idx/GW,ny=node/GW;
 wire neighbor_ok=(neighbor==0&&nx!=0)||(neighbor==1&&nx!=GW-1)||
  (neighbor==2&&ny!=0)||(neighbor==3&&ny!=GH-1);
 // A single explicit write port per memory is required for TD BRAM inference.
 wire visit_write=(state==SUSE||state==NUSE)&&work_q==2'b01;
 wire [AW-1:0] work_write_addr=state==FWRITE?idx:state==SUSE?scan_idx:work_addr;
 wire [1:0] work_write_data=state==FWRITE?{1'b0,self_bit&&adjacent}:2'b11;
 wire [AW-1:0] queue_write_addr=state==SUSE?{AW{1'b0}}:tail[AW-1:0];
 wire [AW-1:0] queue_write_data=state==SUSE?scan_idx:work_addr;
 always @(posedge clk)begin
  if(rst_n&&(state==FWRITE||visit_write))work_mask[work_write_addr]<=work_write_data;
  if(rst_n&&visit_write)queue[queue_write_addr]<=queue_write_data;
  if(rst_n&&state==FWRITE)begin
   if(work_bank)mask1[idx]<=self_bit&&adjacent;else mask0[idx]<=self_bit&&adjacent;
  end
 end
 reg [3:0] hold_count;
 reg confirmed,track_visible;
 reg pending_valid,pending_global,pending_visible;
 reg [9:0] pending_count;
 reg [5:0] pending_x0,pending_x1;
 reg [4:0] pending_y0,pending_y1;
 reg published_result_valid,published_box_visible,published_global_change;
 reg [9:0] published_moving_tiles;
 reg [5:0] published_box_x0,published_box_x1;
 reg [4:0] published_box_y0,published_box_y1;
 wire commit=display_sof&&pending_result;
 assign result_valid=commit?pending_valid:published_result_valid;
 assign moving_tiles=commit?(pending_valid?pending_count:10'd0):published_moving_tiles;
 assign global_change=commit?(pending_valid&&pending_global):published_global_change;
 assign box_visible=commit?(pending_valid&&pending_visible):published_box_visible;
 assign box_x0=commit?pending_x0:published_box_x0;
 assign box_x1=commit?pending_x1:published_box_x1;
 assign box_y0=commit?pending_y0:published_box_y0;
 assign box_y1=commit?pending_y1:published_box_y1;
 wire near_track=bestx0<=trackx1+2 && trackx0<=bestx1+2 &&
  besty0<=tracky1+2 && tracky0<=besty1+2;
 // Smooth position as before, but limit width/height changes to one cell
 // per processed frame. A hand joining the object cannot instantly inflate
 // the displayed box. Translation is independent of the extent slew limit.
 function [11:0] smooth_axis;
  input [5:0] oldlo,oldhi,newlo,newhi,limit;
  reg [6:0] oc,nc,mid,left;
  reg [5:0] oldspan,newspan,span;
  begin
   oc={1'b0,oldlo}+oldhi;nc={1'b0,newlo}+newhi;
   oldspan=oldhi-oldlo;newspan=newhi-newlo;
   if(newspan>oldspan)span=oldspan+1'b1;
   else if(newspan<oldspan)span=oldspan-1'b1;
   else span=oldspan;
   mid=(oc>nc?oc-nc:nc-oc)<=2?oc:({1'b0,oc}+{1'b0,nc}+8'd1)>>1;
   left=mid>span?(mid-span)>>1:0;
   if(left+span>limit)left=limit-span;
   smooth_axis={left[5:0],(left[5:0]+span)};
  end
 endfunction
 wire [11:0] next_x=smooth_axis(trackx0,trackx1,bestx0,bestx1,GW-1);
 wire [11:0] next_y=smooth_axis({1'b0,tracky0},{1'b0,tracky1},{1'b0,besty0},{1'b0,besty1},GH-1);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   beat_x<=0;row_y<=0;cb<=0;cl<=0;tx<=0;ty<=0;active<=0;baseline<=0;samples<=0;
   sample_valid_q<=0;sample_baseline_q<=0;sample_bank_q<=0;sample_addr_q<=0;sample_q<=0;row_sum<=0;
   write_bank<=0;process_bank<=0;display_bank<=0;pending_result<=0;
   state<=IDLE;idx<=0;scan_idx<=0;node<=0;neighbor<=0;self_bit<=0;adjacent<=0;
   raw_addr<=0;work_addr<=0;queue_addr<=0;head<=0;tail<=0;component_count<=0;best_count<=0;filtered_count<=0;
   minx<=0;maxx<=0;miny<=0;maxy<=0;bestx0<=0;bestx1<=0;besty0<=0;besty1<=0;
   trackx0<=0;trackx1<=0;tracky0<=0;tracky1<=0;confirmed<=0;track_visible<=0;hold_count<=0;
   pending_valid<=0;pending_global<=0;pending_visible<=0;pending_count<=0;
   pending_x0<=0;pending_x1<=0;pending_y0<=0;pending_y1<=0;
   published_result_valid<=0;published_moving_tiles<=0;published_box_visible<=0;published_global_change<=0;
   published_box_x0<=0;published_box_x1<=0;published_box_y0<=0;published_box_y1<=0;
  end else begin
   sample_valid_q<=finish_cell;
   if(sample_now)begin
    if(cx==BP/4)row_sum<=group_sum;
    else if(cy==TILE_HEIGHT/4)column_sum[gx]<=row_total;
    else begin
     sample_q<=cell_total[11:4];sample_addr_q<=sample_addr;
     sample_baseline_q<=baseline;sample_bank_q<=write_bank;
     if(samples<CELLS)samples<=samples+1'b1;
    end
   end
   if(I_tuser)begin
    active<=1;beat_x<=I_tvalid&&!I_tlast?1:0;row_y<=0;
    cb<=I_tvalid?1:0;cl<=0;tx<=0;ty<=0;samples<=0;
    if(active)begin baseline<=0;published_result_valid<=0;published_box_visible<=0;end
   end else if(I_tvalid&&active)begin
    beat_x<=I_tlast?0:bx+1'b1;row_y<=I_tlast?ry+1'b1:ry;
    cb<=cx==BP-1?0:cx+1'b1;if(cx==BP-1)tx<=gx==GW-1?0:gx+1'b1;
    if(I_tlast)begin cl<=cy==TILE_HEIGHT-1?0:cy+1'b1;if(cy==TILE_HEIGHT-1)ty<=gy+1'b1;end
   end
   if(eof)begin
    active<=0;
    if(samples==CELLS&&!bad)begin
     baseline<=1;
     if(state==IDLE&&!pending_result)begin
      process_bank<=write_bank;write_bank<=!write_bank;
      idx<=0;neighbor<=0;filtered_count<=0;best_count<=0;state<=FSET;
      pending_valid<=baseline;
     end
    end else begin baseline<=0;published_result_valid<=0;published_box_visible<=0;end
   end
   if(bad)begin active<=0;baseline<=0;sample_valid_q<=0;published_result_valid<=0;published_box_visible<=0;end
   if(display_sof&&pending_result)begin
    display_bank<=!display_bank;pending_result<=0;published_result_valid<=pending_valid;
    published_moving_tiles<=pending_valid?pending_count:0;published_global_change<=pending_valid&&pending_global;
    published_box_visible<=pending_valid&&pending_visible;
    published_box_x0<=pending_x0;published_box_x1<=pending_x1;published_box_y0<=pending_y0;published_box_y1<=pending_y1;
   end
   case(state)
    IDLE:;
    FSET:begin raw_addr<=idx;neighbor<=0;self_bit<=0;adjacent<=0;state<=FWAIT;end
    FWAIT:state<=FUSE;
    FUSE:begin
     if(neighbor==0)self_bit<=raw_q;
     else if((neighbor==1&&ix!=0)||(neighbor==2&&ix!=GW-1)||
       (neighbor==3&&iy!=0)||(neighbor==4&&iy!=GH-1))adjacent<=adjacent|raw_q;
     case(neighbor)0:raw_addr<=idx-1'b1;1:raw_addr<=idx+1'b1;2:raw_addr<=idx-GW;3:raw_addr<=idx+GW;default:;endcase
     if(neighbor==4)state<=FWRITE;else begin neighbor<=neighbor+1'b1;state<=FWAIT;end
    end
    FWRITE:begin
     if(self_bit&&adjacent)filtered_count<=filtered_count+1'b1;
     if(idx==CELLS-1)begin scan_idx<=0;state<=SCAN;end else begin idx<=idx+1'b1;state<=FSET;end
    end
    SCAN:begin
     if(filtered_count>CELLS*3/4)state<=PUBLISH;
     else begin work_addr<=scan_idx;state<=SWAIT;end
    end
    SWAIT:state<=SUSE;
    SUSE:if(work_q==2'b01)begin
     head<=0;tail<=1;component_count<=0;
     minx<=GW-1;maxx<=0;miny<=GH-1;maxy<=0;state<=QSET;
    end else if(scan_idx==CELLS-1)state<=PUBLISH;
    else begin scan_idx<=scan_idx+1'b1;state<=SCAN;end
    QSET:begin queue_addr<=head[AW-1:0];state<=QWAIT;end
    QWAIT:state<=QUSE;
    QUSE:begin
     node<=queue_q;head<=head+1'b1;component_count<=component_count+1'b1;
     if(queue_q%GW<minx)minx<=queue_q%GW;if(queue_q%GW>maxx)maxx<=queue_q%GW;
     if(queue_q/GW<miny)miny<=queue_q/GW;if(queue_q/GW>maxy)maxy<=queue_q/GW;
     neighbor<=0;state<=NSET;
    end
    NSET:if(neighbor_ok)begin
     case(neighbor)0:work_addr<=node-1'b1;1:work_addr<=node+1'b1;2:work_addr<=node-GW;3:work_addr<=node+GW;default:;endcase
     state<=NWAIT;
    end else state<=NEXT;
    NWAIT:state<=NUSE;
    NUSE:begin
     if(work_q==2'b01)tail<=tail+1'b1;
     state<=NEXT;
    end
    NEXT:if(neighbor==3)state<=head==tail?COMPLETE:QSET;
     else begin neighbor<=neighbor+1'b1;state<=NSET;end
    COMPLETE:begin
     if(component_count>best_count)begin
      best_count<=component_count;bestx0<=minx;bestx1<=maxx;besty0<=miny;besty1<=maxy;
     end
     if(scan_idx==CELLS-1)state<=PUBLISH;else begin scan_idx<=scan_idx+1'b1;state<=SCAN;end
    end
    PUBLISH:begin
     pending_count<=filtered_count;pending_global<=filtered_count>CELLS*3/4;
     pending_visible<=0;
     if(!pending_valid||filtered_count>CELLS*3/4)begin confirmed<=0;track_visible<=0;hold_count<=0;end
     else if(best_count>=MIN_CELLS)begin
      if(confirmed&&near_track)begin
       track_visible<=1;pending_visible<=1;hold_count<=HOLD_FRAMES;
       trackx0<=track_visible?next_x[11:6]:bestx0;
       trackx1<=track_visible?next_x[5:0]:bestx1;
       tracky0<=track_visible?next_y[10:6]:besty0;
       tracky1<=track_visible?next_y[4:0]:besty1;
       pending_x0<=track_visible?next_x[11:6]:bestx0;
       pending_x1<=track_visible?next_x[5:0]:bestx1;
       pending_y0<=track_visible?next_y[10:6]:besty0;
       pending_y1<=track_visible?next_y[4:0]:besty1;
      end else begin
       confirmed<=1;track_visible<=0;hold_count<=0;
       trackx0<=bestx0;trackx1<=bestx1;tracky0<=besty0;tracky1<=besty1;
      end
     end else if(track_visible&&hold_count!=0)begin
      hold_count<=hold_count-1'b1;pending_visible<=1;
      pending_x0<=trackx0;pending_x1<=trackx1;pending_y0<=tracky0;pending_y1<=tracky1;
     end else begin confirmed<=0;track_visible<=0;hold_count<=0;end
     pending_result<=1;state<=IDLE;
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule

// Three clocks, matching the pre-existing disabled motion-status overlay.
// RAM map, rectangle and video metadata are latched from the SAME SOF snapshot.
module motion_region_overlay_96 #(
 parameter integer RENDER_GRID=0,IMG_WIDTH=1280,IMG_HEIGHT=720,TILE_WIDTH=40,TILE_HEIGHT=40,
 parameter integer GW=IMG_WIDTH/TILE_WIDTH,GH=IMG_HEIGHT/TILE_HEIGHT,AW=$clog2(GW*GH)
)(
 input wire clk,rst_n,I_tuser,I_tvalid,I_tlast,input wire [95:0] I_tdata,
 input wire [2:0] I_mode,input wire [7:0] I_threshold,
 input wire result_valid,box_visible,global_change,map_bit,
 input wire [5:0] box_x0,box_x1,input wire [4:0] box_y0,box_y1,
 output wire [AW-1:0] map_addr,
 output reg O_tuser,O_tvalid,O_tlast,output reg [95:0] O_tdata,
 output reg [2:0] O_mode,output reg [7:0] O_threshold
);
 reg [10:0] x,y;reg [7:0] cellx,celly,within_x,within_y;
 wire [10:0] px=I_tuser?0:x,py=I_tuser?0:y;
 wire [7:0] cx=I_tuser?0:cellx,cy=I_tuser?0:celly;
 wire [7:0] wx=I_tuser?0:within_x,wy=I_tuser?0:within_y;
 assign map_addr=RENDER_GRID?cy*GW+cx:{AW{1'b0}};
 function [10:0] scale_x;
  input [6:0] a;
  begin scale_x=TILE_WIDTH==40?({a,5'b0}+{a,3'b0}):a*TILE_WIDTH;end
 endfunction
 function [10:0] scale_y;
  input [5:0] a;
  begin scale_y=TILE_HEIGHT==40?({a,5'b0}+{a,3'b0}):a*TILE_HEIGHT;end
 endfunction
 reg visible_f,global_f,valid_f;reg [10:0] x0,x1,y0,y1;
 wire visible=I_tuser?(result_valid&&box_visible&&!global_change):visible_f;
 wire valid=I_tuser?result_valid:valid_f,global_view=I_tuser?global_change:global_f;
 wire [10:0] left=I_tuser?scale_x({1'b0,box_x0}):x0,right=I_tuser?scale_x({1'b0,box_x1}+7'd1)-1'b1:x1;
 wire [10:0] top=I_tuser?scale_y({1'b0,box_y0}):y0,bottom=I_tuser?scale_y({1'b0,box_y1}+6'd1)-1'b1:y1;
 reg [95:0] rgb1,rgb2;reg [2:0] modes1,modes2;reg [7:0] th1,th2;
 reg [2:0] uq,vq,lq;reg [3:0] border1;reg grid1,enabled1;
 integer lane;
 wire grid_line=wx<4 || wy<2;
 function [23:0] tint;
  input [23:0] p;
  begin tint={1'b0,p[23:17],({1'b0,p[15:9]}+8'd64),1'b0,p[7:1]};end
 endfunction
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   x<=0;y<=0;cellx<=0;celly<=0;within_x<=0;within_y<=0;
   visible_f<=0;global_f<=0;valid_f<=0;x0<=0;x1<=0;y0<=0;y1<=0;
   rgb1<=0;rgb2<=0;modes1<=0;modes2<=0;th1<=0;th2<=0;uq<=0;vq<=0;lq<=0;
   border1<=0;grid1<=0;enabled1<=0;O_tuser<=0;O_tvalid<=0;O_tlast<=0;O_tdata<=0;O_mode<=0;O_threshold<=0;
  end else begin
   if(I_tuser)begin
    visible_f<=result_valid&&box_visible&&!global_change;valid_f<=result_valid;global_f<=global_change;
    x0<=scale_x({1'b0,box_x0});x1<=scale_x({1'b0,box_x1}+7'd1)-1'b1;
    y0<=scale_y({1'b0,box_y0});y1<=scale_y({1'b0,box_y1}+6'd1)-1'b1;
    x<=0;y<=0;cellx<=0;celly<=0;within_x<=0;within_y<=0;
   end
   if(I_tvalid)begin
    x<=I_tlast?0:px+4;y<=I_tlast?(py==IMG_HEIGHT-1?0:py+1'b1):py;
    within_x<=I_tlast?0:(wx==TILE_WIDTH-4?0:wx+4);
    cellx<=I_tlast?0:(wx==TILE_WIDTH-4?cx+1'b1:cx);
    if(I_tlast)begin within_y<=wy==TILE_HEIGHT-1?0:wy+1'b1;celly<=wy==TILE_HEIGHT-1?cy+1'b1:cy;end
   end
   uq<={uq[1:0],I_tuser};vq<={vq[1:0],I_tvalid};lq<={lq[1:0],I_tlast};
   rgb1<=I_tdata;modes1<=I_mode;th1<=I_threshold;
   grid1<=RENDER_GRID&&valid&&!global_view&&grid_line;enabled1<=I_mode==6;
   for(lane=0;lane<4;lane=lane+1)begin
    border1[3-lane]<=I_mode==6&&visible&&px+lane>=left&&px+lane<=right&&py>=top&&py<=bottom&&
      (px+lane-left<2 || right-(px+lane)<2 || py-top<2 || bottom-py<2);
    rgb2[95-lane*24-:24]<=!enabled1?rgb1[95-lane*24-:24]:border1[3-lane]?24'hffd040:
      (grid1&&map_bit)?tint(rgb1[95-lane*24-:24]):rgb1[95-lane*24-:24];
   end
   modes2<=modes1;th2<=th1;
   O_tuser<=uq[1];O_tvalid<=vq[1];O_tlast<=lq[1];O_tdata<=rgb2;O_mode<=modes2;O_threshold<=th2;
  end
 end
endmodule
