`timescale 1ns/1ps
// Area-average every source pixel, then atomically publish a validated frame.
// Each bank is owned using a request/acknowledgement toggle handshake. RAM is
// never cleared on reset and cannot be read until all locations are written.
module ws2812_video_wall #(
    parameter integer PANEL_COUNT=1,
    parameter integer BIT_CYCLES=63, T0H_CYCLES=20, T1H_CYCLES=40,
    parameter integer RESET_CYCLES=15000
)(
    input wire video_clk, led_clk, rst_n,
    input wire video_de, video_user, video_last,
    input wire [23:0] video_rgb,
    input wire frame_done, frame_valid,
    input wire [3:0] buttons,
    input wire [2:0] source_mode,
    output wire [2:0] wall_status,
    output wire ws_data,
    output reg [15:0] published_frames, dropped_frames
);
    localparam integer GRID_W=PANEL_COUNT*16, PIXELS=PANEL_COUNT*256;
    localparam integer AW=$clog2(PIXELS), CW=1280/GRID_W, CXW=$clog2(CW);
    // 73/2^18 ~= 1/3600; for 40x45 cells the shift is 17 instead of 18.
    localparam integer AVG_SHIFT=(PANEL_COUNT==1)?18:17;
    reg [23:0] bank0[0:PIXELS-1], bank1[0:PIXELS-1];
    reg [19:0] acc_r[0:GRID_W-1], acc_g[0:GRID_W-1], acc_b[0:GRID_W-1];
    reg [14:0] line_r,line_g,line_b;
    reg [CXW-1:0] cx;
    reg [5:0] cy;
    reg [4:0] gx;
    reg [3:0] gy;
    reg [10:0] x;
    reg [9:0] y;
    reg capture, capture_bank, pending, validated, prefer_bank;
    reg [1:0] request, acknowledge;
    (* ASYNC_REG="TRUE" *) reg [1:0] ack_v1,ack_v2,req_l1,req_l2;
    wire [1:0] free_bank=~(request^ack_v2);
    wire selected=free_bank[prefer_bank]?prefer_bank:!prefer_bank;
    wire capturing=video_user ? (|free_bank) : capture;
    wire [CXW-1:0] pcx=video_user?0:cx;
    wire [5:0] pcy=video_user?0:cy;
    wire [4:0] pgx=video_user?0:gx;
    wire [3:0] pgy=video_user?0:gy;
    wire [10:0] px=video_user?0:x;
    wire [9:0] py=video_user?0:y;
    wire [14:0] lr=video_user?0:line_r, lg=video_user?0:line_g, lb=video_user?0:line_b;
    wire [14:0] sr=lr+{7'd0,video_rgb[23:16]};
    wire [14:0] sg=lg+{7'd0,video_rgb[15:8]};
    wire [14:0] sb=lb+{7'd0,video_rgb[7:0]};

    reg [2:0] avg_state;
    reg [19:0] sum_r,sum_g,sum_b,avg_operand;
    reg [26:0] product;
    reg [7:0] out_r,out_g,out_b;
    reg [AW-1:0] store_addr;
    reg store_bank;
    wire store_en=(avg_state==5);
    wire [23:0] store_rgb={out_r,out_g,out_b};
    // Full-range RGB is retained in RAM. Serial output is explicitly capped
    // at 63/255 per channel (one quarter), and reordered RGB -> GRB.
    wire [8:0] rounded_average=product>>AVG_SHIFT;
    wire [7:0] average=(rounded_average>255)?8'd255:rounded_average[7:0];
    always @* begin
        case(avg_state)
            1: avg_operand=sum_r;
            2: avg_operand=sum_g;
            default: avg_operand=sum_b;
        endcase
    end
    integer n;
    always @(posedge video_clk or negedge rst_n) begin
        if(!rst_n)begin
            request<=0;ack_v1<=0;ack_v2<=0;
            capture<=0;capture_bank<=0;pending<=0;validated<=0;prefer_bank<=0;
            cx<=0;cy<=0;gx<=0;gy<=0;x<=0;y<=0;
            line_r<=0;line_g<=0;line_b<=0;
            avg_state<=0;sum_r<=0;sum_g<=0;sum_b<=0;product<=0;
            out_r<=0;out_g<=0;out_b<=0;store_addr<=0;store_bank<=0;
            published_frames<=0;dropped_frames<=0;
            for(n=0;n<GRID_W;n=n+1)begin acc_r[n]<=0;acc_g[n]<=0;acc_b[n]<=0;end
        end else begin
            ack_v1<=acknowledge;ack_v2<=ack_v1;
            if(video_user)begin
                capture<=(|free_bank) && video_de;
                capture_bank<=selected;
                pending<=0;validated<=0;
                cx<=0;cy<=0;gx<=0;gy<=0;x<=0;y<=0;
                line_r<=0;line_g<=0;line_b<=0;
                for(n=0;n<GRID_W;n=n+1)begin acc_r[n]<=0;acc_g[n]<=0;acc_b[n]<=0;end
                if(!(|free_bank))dropped_frames<=dropped_frames+1'b1;
            end else if(frame_done)begin
                if(pending && frame_valid)validated<=1;
                else begin capture<=0;pending<=0;validated<=0;end
            end
            if(pending && validated && avg_state==0 && !video_user)begin
                request[capture_bank]<=~request[capture_bank];
                prefer_bank<=~capture_bank;
                pending<=0;validated<=0;capture<=0;
                published_frames<=published_frames+1'b1;
            end
            if(video_de && capturing)begin
                // Reject malformed/partial frames; next user marker restarts.
                if(video_last!=(px==1279) || py>=720)begin
                    capture<=0;pending<=0;validated<=0;
                end else begin
                    x<=(px==1279)?0:px+1'b1;
                    if(px==1279)y<=py+1'b1;
                    cx<=(pcx==CW-1)?0:pcx+1'b1;
                    if(pcx==CW-1)gx<=(pgx==GRID_W-1)?0:pgx+1'b1;
                    if(video_last)begin
                        cy<=(pcy==44)?0:pcy+1'b1;
                        if(pcy==44)gy<=pgy+1'b1;
                    end
                    if(pcx==CW-1)begin
                        line_r<=0;line_g<=0;line_b<=0;
                        if(pcy==44)begin
                            acc_r[pgx]<=0;acc_g[pgx]<=0;acc_b[pgx]<=0;
                            if(avg_state==0)begin
                                sum_r<=acc_r[pgx]+sr;sum_g<=acc_g[pgx]+sg;sum_b<=acc_b[pgx]+sb;
                                store_addr<=pgy*GRID_W+pgx;
                                store_bank<=video_user?selected:capture_bank;
                                avg_state<=1;
                            end else begin capture<=0;pending<=0;validated<=0;end
                        end else begin
                            acc_r[pgx]<=acc_r[pgx]+sr;
                            acc_g[pgx]<=acc_g[pgx]+sg;
                            acc_b[pgx]<=acc_b[pgx]+sb;
                        end
                    end else begin line_r<=sr;line_g<=sg;line_b<=sb;end
                    if(px==1279 && py==719)begin pending<=1;capture<=0;end
                end
            end
            case(avg_state)
                1:begin product<=avg_operand*7'd73+(1<<(AVG_SHIFT-1));avg_state<=2;end
                2:begin out_r<=average;product<=avg_operand*7'd73+(1<<(AVG_SHIFT-1));avg_state<=3;end
                3:begin out_g<=average;product<=avg_operand*7'd73+(1<<(AVG_SHIFT-1));avg_state<=4;end
                4:begin out_b<=average;avg_state<=5;end
                5:avg_state<=0;
                default:;
            endcase
        end
    end
    // Simple dual-port RAM inference: each RAM output has its own read reg,
    // no memory/output reset, and no combinational mux in the read process.
    always @(posedge video_clk)begin
        if(store_en && !store_bank)bank0[store_addr]<=store_rgb;
        if(store_en && store_bank)bank1[store_addr]<=store_rgb;
    end
    // Preserve the video-side area averaging and proven bank handshake.
    // Load one complete, validated frame into the 50 MHz light painter.
    reg [23:0] read0,read1;
    reg [AW-1:0] seq;
    wire [3:0] row=seq[7:4];
    wire [3:0] col=row[0]?~seq[3:0]:seq[3:0];
    wire [AW-1:0] serial_address;
    generate if(PANEL_COUNT==1)begin:single
        assign serial_address={row,col};
    end else begin:dual
        assign serial_address={row,seq[8],col};
    end endgenerate
    reg [AW-1:0] load_addr;
    always @(posedge led_clk)begin read0<=bank0[load_addr];read1<=bank1[load_addr];end
    reg active_bank,active_request,next_bank,frame_start;
    reg [2:0] led_state;
    localparam L_IDLE=0,L_LOAD=1,L_PROCESS=2,L_SEND=3;
    reg [1:0] read_wait;
    wire [1:0] ready_bank=req_l2^acknowledge;
    wire choose=ready_bank[next_bank]?next_bank:!next_bank;
    wire tile_valid=(led_state==L_LOAD && read_wait==0);
    reg painter_start;
    wire painter_busy,painter_done;
    wire [23:0] painted_rgb;
    wire [9:0] foreground_count;
    wire capture_request,effect_request;
    wall_effect_buttons controls(.clk(led_clk),.rst_n(rst_n),.buttons(buttons),
        .source_mode(source_mode),.capture_request(capture_request),.effect_request(effect_request));
    wall_light_painter #(.GRID_W(GRID_W)) painter(
        .clk(led_clk),.rst_n(rst_n),.tile_valid(tile_valid),.tile_addr(load_addr),
        .tile_rgb(active_bank?read1:read0),.frame_start(painter_start),
        .capture_request(capture_request),.effect_request(effect_request),
        .read_addr(serial_address),.read_rgb(painted_rgb),.busy(painter_busy),
        .frame_done(painter_done),.status(wall_status),.foreground_count(foreground_count));
    wire [23:0] grb={painted_rgb[15:8],painted_rgb[23:16],painted_rgb[7:0]};
    wire pixel_ready,tx_done,tx_busy;
    wire pixel_valid=led_state==L_SEND && read_wait==0;
    always @(posedge led_clk or negedge rst_n)begin
        if(!rst_n)begin
            req_l1<=0;req_l2<=0;acknowledge<=0;
            led_state<=L_IDLE;active_bank<=0;active_request<=0;next_bank<=0;
            frame_start<=0;painter_start<=0;seq<=0;load_addr<=0;read_wait<=0;
        end else begin
            req_l1<=request;req_l2<=req_l1;frame_start<=0;painter_start<=0;
            if(read_wait!=0)read_wait<=read_wait-1'b1;
            case(led_state)
                L_IDLE:if(!painter_busy && !tx_busy && |ready_bank)begin
                    led_state<=L_LOAD;active_bank<=choose;active_request<=req_l2[choose];
                    load_addr<=0;read_wait<=2;
                end
                L_LOAD:if(tile_valid)begin
                    if(load_addr==PIXELS-1)begin
                        // Last RAM write and the start strobe land on adjacent
                        // clocks, before the painter reads the last tile.
                        led_state<=L_PROCESS;painter_start<=1;
                    end else begin load_addr<=load_addr+1'b1;read_wait<=2;end
                end
                L_PROCESS:if(painter_done)begin
                    led_state<=L_SEND;frame_start<=1;seq<=0;read_wait<=2;
                end
                L_SEND:begin
                    if(pixel_ready && pixel_valid)begin seq<=seq+1'b1;read_wait<=2;end
                    if(tx_done)begin
                        acknowledge[active_bank]<=active_request;
                        led_state<=L_IDLE;next_bank<=~active_bank;
                    end
                end
                default:led_state<=L_IDLE;
            endcase
        end
    end
    ws2812_stream_tx #(.PIXEL_COUNT(PIXELS),.BIT_CYCLES(BIT_CYCLES),
        .T0H_CYCLES(T0H_CYCLES),.T1H_CYCLES(T1H_CYCLES),.RESET_CYCLES(RESET_CYCLES)) transmitter(
        .clk(led_clk),.rst_n(rst_n),.frame_start(frame_start),.pixel_data(grb),
        .pixel_valid(pixel_valid),.pixel_ready(pixel_ready),.ws_data(ws_data),
        .frame_done(tx_done),.busy(tx_busy));
endmodule
