// Preserve the proven camera read/mixer pipeline, then add authored OSD.
module hdmi_mixer #(
    parameter H_OFFSET=0, V_OFFSET=0, IMG_WIDTH=1280, IMG_HEIGHT=720,
    parameter integer DEBUG_MODE=0, ENABLE_LATENCY=0
)(
    input wire I_clk, I_rst_n,
    input wire [23:0] I_latency_ticks,
    input wire I_frame_underflow,
    input wire [2:0] I_wall_status,
    input wire I_led_clk,I_paint_valid,I_paint_down,input wire [2:0] I_brush_color,
    input wire [7:0] I_paint_u,input wire [6:0] I_paint_v,
    input wire I_canvas_write,input wire [8:0] I_canvas_addr,
    input wire [23:0] I_canvas_rgb,input wire I_canvas_done,
    input wire I_video_vsync, I_video_hsync, I_video_de,
    input wire I_video_user, I_video_last,
    input wire [23:0] I_debug_status,
    output wire O_video_rd_en,
    input wire [23:0] I_video_rd_data,
    output wire O_hdmi_vsync, O_hdmi_hsync, O_hdmi_de,
    output wire [23:0] O_hdmi_data,
    output wire O_sample_de,
    output wire [23:0] O_sample_data,
    output wire O_sample_user, O_sample_last,
    output wire O_sample_done, O_sample_valid
);
    wire vs, hs, de;
    wire [23:0] rgb;
    reg [2:0] user_delay, last_delay;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin user_delay<=0; last_delay<=0; end
        else begin
            user_delay <= {user_delay[1:0], I_video_user};
            last_delay <= {last_delay[1:0], I_video_last};
        end
    end
    hdmi_camera_mixer #(.H_OFFSET(H_OFFSET), .V_OFFSET(V_OFFSET),
        .IMG_WIDTH(IMG_WIDTH), .IMG_HEIGHT(IMG_HEIGHT), .DEBUG_MODE(DEBUG_MODE),
        .INPUT_READ_LATENCY(ENABLE_LATENCY?2:0))
    camera_mixer (
        .I_clk(I_clk), .I_rst_n(I_rst_n),
        .I_video_vsync(I_video_vsync), .I_video_hsync(I_video_hsync),
        .I_video_de(I_video_de), .I_video_user(I_video_user), .I_video_last(I_video_last),
        .I_debug_status(I_debug_status), .O_video_rd_en(O_video_rd_en),
        .I_video_rd_data(I_video_rd_data), .O_hdmi_vsync(vs),
        .O_hdmi_hsync(hs), .O_hdmi_de(de), .O_hdmi_data(rgb)
    );
    wire [23:0] panel_rgb;
    generate if(ENABLE_LATENCY)begin:latency_display
        wire [23:0] clean_rgb,age;
        wire done,good,is_repeat;
        wire [15:0] frame_id,repeats;
        latency_reader #(.WIDTH(IMG_WIDTH),.HEIGHT(IMG_HEIGHT)) reader(.clk(I_clk),.rst_n(I_rst_n),.de(de),
            .user(user_delay[2]),.last(last_delay[2]),.pixel(rgb),
            .ticks(I_latency_ticks),.underflow(I_frame_underflow),.clean_pixel(clean_rgb),
            .sample_valid(good),.sample_done(done),.latency_ticks(age),
            .displayed_id(frame_id),.repeated(is_repeat),.repeat_count(repeats));
        assign O_sample_data=clean_rgb;
        assign O_sample_done=done;
        assign O_sample_valid=good;
        latency_panel panel(.clk(I_clk),.rst_n(I_rst_n),.de(de),
            .user(user_delay[2]),.last(last_delay[2]),.pixel(clean_rgb),
            .sample_done(done),.sample_valid(good),.latency_ticks(age),
            .displayed_id(frame_id),.repeat_count(repeats),.repeated(is_repeat),.out_pixel(panel_rgb));
    end else begin:no_latency
        assign panel_rgb=rgb;
        assign O_sample_data=rgb;
        assign O_sample_done=1'b0;
        assign O_sample_valid=1'b0;
    end endgenerate
    assign O_sample_de = de;
    assign O_sample_user=user_delay[2];
    assign O_sample_last=last_delay[2];
    wire [23:0] wall_panel_rgb;
    wall_status_panel wall_panel(.clk(I_clk),.rst_n(I_rst_n),.de(de),
        .user(user_delay[2]),.last(last_delay[2]),.status_async(I_wall_status),
        .pixel(panel_rgb),.out_pixel(wall_panel_rgb));
    wire [23:0] paint_panel_rgb;
    wall_paint_overlay paint_panel(.led_clk(I_led_clk),.hdmi_clk(I_clk),.rst_n(I_rst_n),
        .write_valid(I_canvas_write),.write_addr(I_canvas_addr),.write_rgb(I_canvas_rgb),
        .frame_done(I_canvas_done),.wall_status(I_wall_status),
        .marker_valid(I_paint_valid),.marker_u(I_paint_u),.marker_v(I_paint_v),.pen_down(I_paint_down),
        .de(de),.user(user_delay[2]),.last(last_delay[2]),.pixel(wall_panel_rgb),.out_pixel(paint_panel_rgb),.brush_color(I_brush_color));
    video_osd overlay (
        .clk(I_clk), .rst_n(I_rst_n), .vsync(vs), .hsync(hs), .de(de),
        .user(user_delay[2]), .last(last_delay[2]), .pixel(paint_panel_rgb),
        .out_vsync(O_hdmi_vsync), .out_hsync(O_hdmi_hsync),
        .out_de(O_hdmi_de), .out_pixel(O_hdmi_data)
    );
endmodule
