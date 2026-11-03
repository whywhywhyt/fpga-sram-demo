`timescale 1ns/1ps
// New light-wall acquisition path: RGB888 x4 after white balance, BEFORE all
// selectable image algorithms, DDR metadata, HDMI overlays and diagnostics.
// 32x16 cells, exactly 40x45 camera pixels per cell. No full-frame image RAM.
module wall_rgb96_capture(
    input wire cam_clk,led_clk,rst_n,
    input wire valid,user,last,input wire [95:0] rgb,
    input wire [8:0] read_addr,output reg [23:0] read0,read1,
    output reg [1:0] request,input wire [1:0] acknowledge,
    output reg [15:0] published,dropped
);
    reg [23:0] frame0[0:511],frame1[0:511];
    (* ASYNC_REG="TRUE" *) reg [1:0] ack_s1,ack_s2;
    wire [1:0] free=~(request^ack_s2);
    reg preferred,capture,write_bank;
    wire select_bank=free[preferred]?preferred:!preferred;
    reg [8:0] beat_x;
    reg [9:0] row_y;
    reg [3:0] cell_beat;
    reg [5:0] cell_line;
    reg [4:0] tile_x;
    reg [3:0] tile_y;
    wire [8:0] bx=user?0:beat_x;
    wire [9:0] ry=user?0:row_y;
    wire [3:0] cb=user?0:cell_beat;
    wire [5:0] cl=user?0:cell_line;
    wire [4:0] tx=user?0:tile_x;
    wire [3:0] ty=user?0:tile_y;
    // Four RGB pixels form one beat, in the same channel order as the ISP.
    reg [9:0] group_r,group_g,group_b;
    reg group_valid,group_bank,group_end_cell,group_end_line,group_end_frame;
    reg [4:0] group_x;
    reg [3:0] group_y;
    reg [5:0] group_line;
    reg group_first_beat;
    reg [2:0] avg_state;
    reg avg_bank,avg_final,publish_pulse;
    wire start_ready=(|free) && avg_state==0 && !publish_pulse && !(group_valid && group_end_frame);
    wire taking=user?start_ready:capture;
    wire protocol_ok=(last==(bx==319)) && ry<720;
    always @(posedge cam_clk or negedge rst_n)begin
        if(!rst_n)begin
            request<=0;ack_s1<=0;ack_s2<=0;preferred<=0;
            capture<=0;write_bank<=0;published<=0;dropped<=0;
            beat_x<=0;row_y<=0;cell_beat<=0;cell_line<=0;tile_x<=0;tile_y<=0;
            group_valid<=0;group_r<=0;group_g<=0;group_b<=0;
            group_bank<=0;group_end_cell<=0;group_end_line<=0;group_end_frame<=0;
            group_x<=0;group_y<=0;group_line<=0;group_first_beat<=0;
        end else begin
            ack_s1<=acknowledge;ack_s2<=ack_s1;group_valid<=0;
            if(user)begin
                // AWB intentionally emits SOF before valid pixels (64+ clocks).
                // Arm on SOF even with valid=0, then accept the first later beat.
                // A rejected SOF rejects the entire frame until the next SOF.
                capture<=start_ready;write_bank<=select_bank;
                beat_x<=0;row_y<=0;cell_beat<=0;cell_line<=0;tile_x<=0;tile_y<=0;
                if(!start_ready)dropped<=dropped+1'b1;
            end
            if(valid && taking)begin
                if(!protocol_ok)capture<=0;
                else begin
                    group_valid<=1;group_bank<=user?select_bank:write_bank;
                    group_r<={2'b0,rgb[95:88]}+{2'b0,rgb[71:64]}+{2'b0,rgb[47:40]}+{2'b0,rgb[23:16]};
                    group_g<={2'b0,rgb[87:80]}+{2'b0,rgb[63:56]}+{2'b0,rgb[39:32]}+{2'b0,rgb[15:8]};
                    group_b<={2'b0,rgb[79:72]}+{2'b0,rgb[55:48]}+{2'b0,rgb[31:24]}+{2'b0,rgb[7:0]};
                    group_first_beat<=(cb==0);group_end_cell<=(cb==9);
                    group_end_line<=last;group_end_frame<=last && ry==719;
                    group_x<=tx;group_y<=ty;group_line<=cl;
                    beat_x<=last?0:bx+1'b1;row_y<=last?ry+1'b1:ry;
                    cell_beat<=(cb==9)?0:cb+1'b1;
                    tile_x<=(cb==9)?tx+1'b1:tx;
                    if(last)begin
                        cell_line<=(cl==44)?0:cl+1'b1;
                        if(cl==44)tile_y<=ty+1'b1;
                    end
                    if(last && ry==719)capture<=0;
                end
            end
            if(publish_pulse)begin
                request[avg_bank]<=~request[avg_bank];preferred<=~avg_bank;
                published<=published+1'b1;
            end
        end
    end
    reg [13:0] line_r,line_g,line_b;
    reg [19:0] column_r[0:31],column_g[0:31],column_b[0:31];
    wire [13:0] lr=(group_first_beat?14'd0:line_r)+group_r;
    wire [13:0] lg=(group_first_beat?14'd0:line_g)+group_g;
    wire [13:0] lb=(group_first_beat?14'd0:line_b)+group_b;
    reg [19:0] sum_r,sum_g,sum_b;
    reg [32:0] product;
    reg [7:0] avg_r,avg_g,avg_b;
    reg [8:0] avg_addr;
    wire [9:0] scaled=product>>23;
    wire [7:0] mean=(scaled>255)?8'd255:scaled[7:0];
    integer k;
    always @(posedge cam_clk or negedge rst_n)begin
        if(!rst_n)begin
            line_r<=0;line_g<=0;line_b<=0;avg_state<=0;
            sum_r<=0;sum_g<=0;sum_b<=0;product<=0;
            avg_r<=0;avg_g<=0;avg_b<=0;avg_addr<=0;avg_bank<=0;avg_final<=0;publish_pulse<=0;
            for(k=0;k<32;k=k+1)begin column_r[k]<=0;column_g[k]<=0;column_b[k]<=0;end
        end else begin
            publish_pulse<=0;
            if(group_valid)begin
                line_r<=lr;line_g<=lg;line_b<=lb;
                if(group_end_cell)begin
                    if(group_line==44)begin
                        column_r[group_x]<=0;column_g[group_x]<=0;column_b[group_x]<=0;
                        sum_r<=column_r[group_x]+lr;sum_g<=column_g[group_x]+lg;sum_b<=column_b[group_x]+lb;
                        avg_addr<={group_y,group_x};avg_bank<=group_bank;avg_final<=group_end_frame;avg_state<=1;
                    end else begin
                        column_r[group_x]<=(group_line==0)?lr:column_r[group_x]+lr;
                        column_g[group_x]<=(group_line==0)?lg:column_g[group_x]+lg;
                        column_b[group_x]<=(group_line==0)?lb:column_b[group_x]+lb;
                    end
                end
            end
            case(avg_state)
                // round(sum/1800), via 4660/2^23, relative error <0.01%.
                1:begin product<=sum_r*13'd4660+33'd4194304;avg_state<=2;end
                2:begin avg_r<=mean;product<=sum_g*13'd4660+33'd4194304;avg_state<=3;end
                3:begin avg_g<=mean;product<=sum_b*13'd4660+33'd4194304;avg_state<=4;end
                4:begin avg_b<=mean;avg_state<=5;end
                5:begin avg_state<=0;if(avg_final)publish_pulse<=1;end
                default:;
            endcase
        end
    end
    always @(posedge cam_clk)begin
        if(avg_state==5 && !avg_bank)frame0[avg_addr]<={avg_r,avg_g,avg_b};
        if(avg_state==5 && avg_bank)frame1[avg_addr]<={avg_r,avg_g,avg_b};
    end
    always @(posedge led_clk)begin read0<=frame0[read_addr];read1<=frame1[read_addr];end
endmodule

// New serializer: MSB first, GRB, 1.26us bit at 50MHz and 300us latch.
// The initial latch delay also prevents a short reset interval after power-up.
module wall_ws2812_tx #(
    parameter integer PIXELS=512,BIT_TICKS=63,ZERO_HIGH=20,ONE_HIGH=40,LATCH_TICKS=15000
)(
    input wire clk,rst_n,start,input wire [23:0] word_data,input wire word_valid,
    output wire word_ready,output wire data,output wire busy,output reg done
);
    localparam IDLE=0,FETCH=1,SEND=2,LATCH=3;
    reg [1:0] state;
    reg [23:0] shift;
    reg [4:0] bit_index;
    reg [9:0] pixel_index;
    reg [5:0] phase;
    reg [13:0] latch_count;
    assign word_ready=state==FETCH;
    assign busy=state!=IDLE;
    assign data=state==SEND && phase<(shift[23]?ONE_HIGH:ZERO_HIGH);
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin state<=LATCH;shift<=0;bit_index<=0;pixel_index<=0;phase<=0;latch_count<=0;done<=0;end
        else begin
            done<=0;
            case(state)
                IDLE:if(start)begin pixel_index<=0;state<=FETCH;end
                FETCH:if(word_valid)begin shift<=word_data;bit_index<=0;phase<=0;state<=SEND;end
                SEND:if(phase==BIT_TICKS-1)begin
                    phase<=0;shift<={shift[22:0],1'b0};
                    if(bit_index==23)begin
                        if(pixel_index==PIXELS-1)begin state<=LATCH;latch_count<=0;end
                        else begin pixel_index<=pixel_index+1'b1;state<=FETCH;end
                    end else bit_index<=bit_index+1'b1;
                end else phase<=phase+1'b1;
                LATCH:if(latch_count==LATCH_TICKS-1)begin state<=IDLE;done<=1;end
                      else latch_count<=latch_count+1'b1;
                default:state<=LATCH;
            endcase
        end
    end
endmodule

module interactive_lightwall #(parameter integer POWER_SWITCH=0)(
    input wire cam_clk,led_clk,rst_n,
    input wire video_valid,video_user,video_last,input wire [95:0] video_rgb,
    input wire capture_request,effect_request,pen_toggle,paint_clear,color_request,home_request,
    output wire ws_data,output wire [2:0] wall_status,
    output wire marker_valid,output wire [7:0] marker_u,output wire [6:0] marker_v,
    output wire pen_down,canvas_write,output wire [8:0] canvas_addr,
    output wire [23:0] canvas_rgb,output wire canvas_done,output wire [2:0] brush_color,
    input wire wall_enable
);
    wire [23:0] read0,read1;
    wire [1:0] request;
    reg [1:0] acknowledge;
    (* ASYNC_REG="TRUE" *) reg [1:0] req_s1,req_s2;
    reg [8:0] load_addr,seq;
    wire [15:0] published,dropped;
    wall_rgb96_capture capture(.cam_clk(cam_clk),.led_clk(led_clk),.rst_n(rst_n),
        .valid(video_valid),.user(video_user),.last(video_last),.rgb(video_rgb),
        .read_addr(load_addr),.read0(read0),.read1(read1),
        .request(request),.acknowledge(acknowledge),.published(published),.dropped(dropped));
    reg active_bank,active_request,next_bank,tx_start,painter_start;
    reg [2:0] led_state;
    localparam IDLE=0,LOAD=1,PROCESS=2,TRANSMIT=3;
    reg [1:0] wait_read;
    wire [1:0] ready=req_s2^acknowledge;
    wire selected=ready[next_bank]?next_bank:!next_bank;
    wire tile_valid=led_state==LOAD && wait_read==0;
    wire [3:0] row=seq[7:4];
    wire [3:0] col=row[0]?~seq[3:0]:seq[3:0];
    wire [8:0] serial_addr={row,seq[8],col};
    wire painter_busy,painter_done;
    wire [4:0] marker_x;wire [3:0] marker_y;
    wall_red_marker marker(.cam_clk(cam_clk),.led_clk(led_clk),.rst_n(rst_n),
        .valid(video_valid),.user(video_user),.last(video_last),.rgb(video_rgb),
        .marker_valid(marker_valid),.marker_u(marker_u),.marker_v(marker_v),
        .marker_x(marker_x),.marker_y(marker_y));
    assign canvas_done=painter_done;
    wire [23:0] painted_rgb;
    wire [2:0] painter_status;
    wire wall_on;
    assign wall_status=wall_on?painter_status:3'd7;
    wire [9:0] foreground_count;
    wall_light_painter painter(.clk(led_clk),.rst_n(rst_n),.tile_valid(tile_valid),.tile_addr(load_addr),
        .tile_rgb(active_bank?read1:read0),.frame_start(painter_start),
        .capture_request(capture_request),.effect_request(effect_request),.home_request(home_request),
        .marker_valid(marker_valid),.marker_x(marker_x),.marker_y(marker_y),
        .pen_toggle(pen_toggle),.paint_clear(paint_clear),.color_request(color_request),
        .brush_color(brush_color),.pen_down(pen_down),
        .canvas_write(canvas_write),.canvas_addr(canvas_addr),.canvas_rgb(canvas_rgb),
        .read_addr(serial_addr),.read_rgb(painted_rgb),.busy(painter_busy),
        .frame_done(painter_done),.status(painter_status),.foreground_count(foreground_count));
    wire word_ready,tx_done,tx_busy;
    wire word_valid=led_state==TRANSMIT && wait_read==0;
    wall_output_switch #(.CONTROL_ENABLED(POWER_SWITCH)) transmitter(
        .clk(led_clk),.rst_n(rst_n),.enable_async(wall_enable),
        .start(tx_start),.word_data({painted_rgb[15:8],painted_rgb[23:16],painted_rgb[7:0]}),
        .word_valid(word_valid),.word_ready(word_ready),.data(ws_data),
        .busy(tx_busy),.done(tx_done),.enabled(wall_on));
    always @(posedge led_clk or negedge rst_n)begin
        if(!rst_n)begin
            acknowledge<=0;req_s1<=0;req_s2<=0;load_addr<=0;seq<=0;
            active_bank<=0;active_request<=0;next_bank<=0;tx_start<=0;painter_start<=0;
            led_state<=IDLE;wait_read<=0;
        end else begin
            req_s1<=request;req_s2<=req_s1;tx_start<=0;painter_start<=0;
            if(wait_read!=0)wait_read<=wait_read-1'b1;
            case(led_state)
                IDLE:if(!painter_busy && !tx_busy && |ready)begin
                    active_bank<=selected;active_request<=req_s2[selected];
                    load_addr<=0;wait_read<=2;led_state<=LOAD;
                end
                LOAD:if(tile_valid)begin
                    if(load_addr==511)begin painter_start<=1;led_state<=PROCESS;end
                    else begin load_addr<=load_addr+1'b1;wait_read<=2;end
                end
                PROCESS:if(painter_done)begin tx_start<=1;seq<=0;wait_read<=2;led_state<=TRANSMIT;end
                TRANSMIT:begin
                    if(word_valid && word_ready)begin seq<=seq+1'b1;wait_read<=2;end
                    if(tx_done)begin acknowledge[active_bank]<=active_request;next_bank<=~active_bank;led_state<=IDLE;end
                end
                default:led_state<=IDLE;
            endcase
        end
    end
endmodule

// Output-only mute, independent of camera activity. Send complete all-zero
// frames while disabled, since WS2812 retains its previously latched color.
// Enable is sampled per frame: switching cannot truncate a bit or a frame.
module wall_output_switch #(
    parameter integer CONTROL_ENABLED=1,
    parameter integer PIXELS=512,BIT_TICKS=63,ZERO_HIGH=20,ONE_HIGH=40,LATCH_TICKS=15000
)(
    input wire clk,rst_n,enable_async,start,
    input wire [23:0] word_data,input wire word_valid,
    output wire word_ready,data,busy,done,enabled
);
    (* ASYNC_REG="TRUE" *) reg enable_s1,enable_s2;
    reg core_start,pending,engine_owner,frame_enabled,boot_clear;
    wire core_ready,core_busy,core_done;
    assign enabled=CONTROL_ENABLED?enable_s2:1'b1;
    assign word_ready=CONTROL_ENABLED?(engine_owner && core_ready):core_ready;
    assign done=CONTROL_ENABLED?(engine_owner && core_done):core_done;
    // The engine can enqueue one start while an autonomous black frame runs.
    assign busy=CONTROL_ENABLED?(core_busy || core_start || pending):core_busy;
    wall_ws2812_tx #(.PIXELS(PIXELS),.BIT_TICKS(BIT_TICKS),.ZERO_HIGH(ZERO_HIGH),
        .ONE_HIGH(ONE_HIGH),.LATCH_TICKS(LATCH_TICKS)) core(
        .clk(clk),.rst_n(rst_n),.start(CONTROL_ENABLED?core_start:start),
        .word_data(CONTROL_ENABLED?(engine_owner && frame_enabled?word_data:24'd0):word_data),
        .word_valid(CONTROL_ENABLED?(engine_owner?word_valid:1'b1):word_valid),.word_ready(core_ready),
        .data(data),.busy(core_busy),.done(core_done));
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            enable_s1<=0;enable_s2<=0;core_start<=0;pending<=0;
            engine_owner<=0;frame_enabled<=0;boot_clear<=1;
        end else begin
            enable_s1<=enable_async;enable_s2<=enable_s1;core_start<=0;
            if(start)pending<=1;
            if(!core_busy && !core_start)begin
                if(boot_clear)begin
                    core_start<=1;engine_owner<=0;frame_enabled<=0;boot_clear<=0;
                end else if(pending || start)begin
                    core_start<=1;engine_owner<=1;frame_enabled<=enable_s2;pending<=0;
                end else if(!enable_s2)begin
                    core_start<=1;engine_owner<=0;frame_enabled<=0;
                end
            end
        end
    end
endmodule
