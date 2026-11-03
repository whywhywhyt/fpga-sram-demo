module isp_top #(parameter integer PROCESS_MODE = 1, parameter integer ENABLE_LATENCY=0) (
    input [95:0] I_frame_tag,
    input cal_capture,cal_toggle,cal_clear,
    input [2:0] requested_mode,
    input [1:0] requested_color,
    input [7:0] requested_binary_threshold,requested_edge_threshold,requested_red_threshold,
    input 			axi4s_video_aclk,
    input 			I_rst_n			,
    input 			I_tlast			,
    input 			I_tuser			,
    input [39:0] 	I_tdata			,
    input 			I_tvalid		,
    input [9:0] 	I_tdest			,
    input 			O_tready		,
    output [127:0] 	O_tdata			,
    output 			O_tlast			,
    output 			O_tuser			,
    output 			O_tvalid		,
    output 			I_tready,
    output reg [95:0] wall_rgb,
    output reg wall_valid,wall_user,wall_last
);
 
wire         m_aixs_tvalid;  //synthesis keep 
  wire [127:0] m_aixs_tdata;  //synthesis keep 
  wire         m_aixs_tuser;  //synthesis keep 
  wire         m_aixs_tlast;  //synthesis keep 
  wire         m_aixs_tready;  //synthesis keep 
  
  wire [ 95:0] m_aixs_tdata_96;  //synthesis keep 


  wire         awb_O_tlast;  //synthesis keep 
  wire         awb_O_tuser;  //synthesis keep 
  wire [ 95:0] awb_O_tdata;  //synthesis keep 
  wire         awb_O_tvalid;  //synthesis keep 
  wire         awb_O_tready;  //synthesis keep 
  wire [172:0] awb_diagnostics;
  wire [159:0] spatial_diagnostics;

  // Independent registered tap. It never stalls or changes the ISP path.
  always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
      if(!I_rst_n)begin wall_rgb<=0;wall_valid<=0;wall_user<=0;wall_last<=0;end
      else begin
          wall_rgb<=awb_O_tdata;wall_valid<=awb_O_tvalid;
          wall_user<=awb_O_tuser;wall_last<=awb_O_tlast;
      end
  end

  wire         awb_O_tuser_128;  //synthesis keep 
  wire         awb_O_tvalid_128;  //synthesis keep 
  wire [127:0] awb_O_tdata_128;  //synthesis keep 


  // The physical camera cannot be stalled; this design always consumes RGB.
  assign awb_O_tready = 1'b1;
  wire process_last, process_user, process_valid;
  wire [95:0] process_data, status_data;
  wire status_last,status_user,status_valid;
  wire [2:0] active_mode;
  wire [1:0] active_color;
  wire [7:0] active_threshold;
  wire target_last,target_user,target_valid;
  // Motion localization is a separate pre-overlay analysis path.
  wire motion_result_valid,motion_box_visible,motion_global,motion_map_bit;
  wire [9:0] motion_tiles;wire [9:0] motion_map_addr;
  wire [5:0] motion_x0,motion_x1;wire [4:0] motion_y0,motion_y1;
  motion_region_detect_96 u_motion_frame_diff(
      .clk(axi4s_video_aclk),.rst_n(I_rst_n),
      .I_tuser(m_aixs_tuser),.I_tvalid(m_aixs_tvalid),.I_tlast(m_aixs_tlast),
      .I_tdata(m_aixs_tdata_96),.display_sof(target_user),
      .map_addr(motion_map_addr),.map_bit(motion_map_bit),
      .result_valid(motion_result_valid),.moving_tiles(motion_tiles),
      .box_visible(motion_box_visible),.global_change(motion_global),
      .box_x0(motion_x0),.box_x1(motion_x1),.box_y0(motion_y0),.box_y1(motion_y1));
  image_modes_96 u_image_modes(
      .clk(axi4s_video_aclk), .rst_n(I_rst_n),
      .I_tlast(awb_O_tlast), .I_tuser(awb_O_tuser),
      .I_tdata(awb_O_tdata), .I_tvalid(awb_O_tvalid),
      .requested_mode(requested_mode),.requested_color(requested_color),
      .requested_binary_threshold(requested_binary_threshold),
      .requested_edge_threshold(requested_edge_threshold),
      .requested_red_threshold(requested_red_threshold),
      .O_tlast(process_last), .O_tuser(process_user), .O_tdata(process_data),
      .O_tvalid(process_valid), .active_mode(active_mode),.active_color(active_color), .active_threshold(active_threshold)
  );
  wire [95:0] target_data;
  wire [2:0] target_mode;
  wire [7:0] target_threshold;
  // Image algorithms consume calibrated camera RGB. Display-only tone is
  // applied after mode selection; an equally delayed unmodified RGB stream
  // feeds detection. SOF/valid/EOL and all frame metadata stay aligned.
  wire [95:0] display_tone_data;
  wire display_tone_valid,display_tone_user,display_tone_last;
  axis_tone_rgb96 display_tone(.clk(axi4s_video_aclk),.rst_n(I_rst_n),
      .I_tvalid(process_valid),.I_tuser(process_user),.I_tlast(process_last),.I_tdata(process_data),
      .O_tvalid(display_tone_valid),.O_tuser(display_tone_user),.O_tlast(display_tone_last),.O_tdata(display_tone_data));
  reg [95:0] analysis_rgb[0:3];
  reg [2:0] display_mode[0:3];reg [1:0] display_color[0:3];reg [7:0] display_threshold[0:3];
  integer dc;
  always @(posedge axi4s_video_aclk or negedge I_rst_n)begin
      if(!I_rst_n)begin
          for(dc=0;dc<4;dc=dc+1)begin analysis_rgb[dc]<=0;display_mode[dc]<=0;display_color[dc]<=0;display_threshold[dc]<=0;end
      end else begin
          analysis_rgb[0]<=process_data;display_mode[0]<=active_mode;
          display_color[0]<=active_color;display_threshold[0]<=active_threshold;
          for(dc=1;dc<4;dc=dc+1)begin
              analysis_rgb[dc]<=analysis_rgb[dc-1];display_mode[dc]<=display_mode[dc-1];
              display_color[dc]<=display_color[dc-1];display_threshold[dc]<=display_threshold[dc-1];
          end
      end
  end
  // Gray, binary and Prewitt remain the original algorithm outputs.
  // Mode 7 already contains a deliberate palette; preserve it via the equal-delay raw path.
    wire display_color_mode=display_mode[3]==0 || display_mode[3]==4 || display_mode[3]==5 || display_mode[3]==6;
  wire [95:0] display_rgb=display_color_mode?display_tone_data:analysis_rgb[3];
  target_overlay_96 #(.SEPARATE_DETECTION(1),.PRESENTATION(1)) u_target_overlay(
      .clk(axi4s_video_aclk),.rst_n(I_rst_n),
      .I_tlast(display_tone_last),.I_tuser(display_tone_user),.I_tvalid(display_tone_valid),.I_tdata(display_rgb),
      .I_mode(display_mode[3]),.I_color(display_color[3]),.I_threshold(display_threshold[3]),
      .I_detection_data(analysis_rgb[3]),
      .O_tlast(target_last),.O_tuser(target_user),.O_tvalid(target_valid),.O_tdata(target_data),
      .O_mode(target_mode),.O_threshold(target_threshold)
  );
  wire motion_last,motion_user,motion_valid;
  wire [95:0] motion_data;
  wire [2:0] motion_mode;
  wire [7:0] motion_threshold;
  motion_region_overlay_96 u_motion_status(
      .clk(axi4s_video_aclk),.rst_n(I_rst_n),
      .I_tlast(target_last),.I_tuser(target_user),.I_tvalid(target_valid),
      .I_tdata(target_data),
      .result_valid(motion_result_valid),.box_visible(motion_box_visible),.global_change(motion_global),
      .box_x0(motion_x0),.box_x1(motion_x1),.box_y0(motion_y0),.box_y1(motion_y1),
      .map_addr(motion_map_addr),.map_bit(motion_map_bit),
      .I_mode(target_mode),.I_threshold(target_threshold),
      .O_tlast(motion_last),.O_tuser(motion_user),.O_tvalid(motion_valid),
      .O_tdata(motion_data),.O_mode(motion_mode),.O_threshold(motion_threshold)
  );
  presentation_status_96 u_frame_status(
      .clk(axi4s_video_aclk),.rst_n(I_rst_n),
      .I_tlast(motion_last),.I_tuser(motion_user),.I_tvalid(motion_valid),.I_tdata(motion_data),
      .I_mode(motion_mode),.I_threshold(motion_threshold),
      .I_spatial_diag(spatial_diagnostics),.I_motion_valid(motion_result_valid),.I_motion_tiles(motion_tiles),.I_motion_global(motion_global),
      .O_tlast(status_last),.O_tuser(status_user),.O_tvalid(status_valid),.O_tdata(status_data)
  );
  assign O_tdata  = awb_O_tdata_128;

  reg packed_last;
  always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
      if (!I_rst_n) packed_last <= 0;
      else packed_last <= status_valid && status_last;
  end
  assign O_tlast = packed_last;
  assign O_tuser  = awb_O_tuser_128    ;
  assign O_tvalid = awb_O_tvalid_128   ;
  
  //assign m_aixs_tready = O_tready;
  //assign O_tdata  = m_aixs_tdata;
  //assign O_tlast  = m_aixs_tlast    ;
  //assign O_tuser  = m_aixs_tuser    ;
  //assign O_tvalid = m_aixs_tvalid   ;
 
 
demosaic #(
    .IMG_HEIGHT          (720 ),  // 图像高度
    .IMG_WIDTH           (1280),  // 图像宽度
    .data_complete_delay (50  ),
    .BAYER_MODE          ("BGGR")
)
u_demosaic
(
    .I_clk   			(axi4s_video_aclk)	,   // 时钟信号
    .I_rst_n 			(I_rst_n)	,   // 复位信号，低有效
    .axi4s_video_tdata 	(I_tdata)	,  // AXI4-Stream视频数据
    .axi4s_video_tdest 	(I_tdest)	,
    .axi4s_video_tlast 	(I_tlast)	,  // 行结束信号
    .axi4s_video_tvalid	(I_tvalid)	,  // 数据有效信号
    .axi4s_video_tuser 	(I_tuser)	,  // 帧开始信号
    .axi4s_video_tready	(I_tready)	,  // 从模块准备好接受数据
    .O_tlast  			(m_aixs_tlast)	,  // 输出行结束信号
    .O_tuser  			(m_aixs_tuser)	,  // 输出帧开始信号
    .O_tdata  			(m_aixs_tdata)	,  // 输出数据
    .O_tvalid 			(m_aixs_tvalid)	,  // 输出数据有效信号
    .O_tready   		(m_aixs_tready)	   // 输出数据准备好信号
);
 
data128_96 u_data128_96 (
    .I_tdata(m_aixs_tdata),
    .O_tdata(m_aixs_tdata_96)
);

awb #(
    .IMG_HEIGHT(720 ),
    .IMG_WIDTH (1280)
) u_awb (
    .I_clk   (axi4s_video_aclk),
    .I_rst_n (I_rst_n),
    .I_tlast (m_aixs_tlast),
    .I_tuser (m_aixs_tuser),
    .I_tdata (m_aixs_tdata_96),
    .I_tvalid(m_aixs_tvalid),
    .I_tready(m_aixs_tready),
    .O_tlast (awb_O_tlast ),
    .O_tuser (awb_O_tuser ),
    .O_tdata (awb_O_tdata ),
    .O_tvalid(awb_O_tvalid),
    .O_tready(awb_O_tready)
    ,.O_diagnostics(awb_diagnostics),
    .I_calibrate(cal_capture),.I_cal_toggle(cal_toggle),.I_cal_clear(cal_clear),.O_spatial_diag(spatial_diagnostics)
);

    wire [95:0] tagged_status_data;
    generate if(ENABLE_LATENCY)begin:timestamp_payload
        latency_tag_96 tagger(.clk(axi4s_video_aclk),.rst_n(I_rst_n),
            .user(status_user),.valid(status_valid),.pixel(status_data),
            .tag(I_frame_tag),.tagged_pixel(tagged_status_data));
    end else begin:no_timestamp
        assign tagged_status_data=status_data;
    end endgenerate
    data_96bit_to_128bit u_data_96bit_to_128bit(
        .I_clk              ( axi4s_video_aclk  ),
        .I_rst_n            ( I_rst_n           ),
	
        .I_96b_frame_start  ( status_user       ),
        .I_96b_valid        ( status_valid      ),
        .I_96b_data         ( tagged_status_data       ),
	
        .O_128b_frame_start ( awb_O_tuser_128  	),
        .O_128b_valid       ( awb_O_tvalid_128 	),
        .O_128b_data        ( awb_O_tdata_128  	)
    );



//data96_128 u_data96_128 (
//    .I_tdata(awb_O_tdata),
//    .O_tdata(awb_O_tdata_128)
//);
	
endmodule


// Four-pixel RGB888 gamma stage.  The 16-segment curve approximates
// y = 255 * (x / 255)^0.7.  It lifts shadows and mid-tones while preserving
// black and white and adds one registered pipeline cycle.
module axis_gamma_rgb96 (
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_tlast,
    input  wire        I_tuser,
    input  wire [95:0] I_tdata,
    input  wire        I_tvalid,
    output reg         O_tlast,
    output reg         O_tuser,
    output reg  [95:0] O_tdata,
    output reg         O_tvalid
);

    function [7:0] gamma07;
        input [7:0] value;
        reg [7:0] base;
        reg [7:0] delta;
        reg [11:0] interpolation;
        begin
            case (value[7:4])
                4'h0: begin base = 8'd0;   delta = 8'd37; end
                4'h1: begin base = 8'd37;  delta = 8'd23; end
                4'h2: begin base = 8'd60;  delta = 8'd19; end
                4'h3: begin base = 8'd79;  delta = 8'd18; end
                4'h4: begin base = 8'd97;  delta = 8'd16; end
                4'h5: begin base = 8'd113; delta = 8'd16; end
                4'h6: begin base = 8'd129; delta = 8'd14; end
                4'h7: begin base = 8'd143; delta = 8'd14; end
                4'h8: begin base = 8'd157; delta = 8'd14; end
                4'h9: begin base = 8'd171; delta = 8'd13; end
                4'ha: begin base = 8'd184; delta = 8'd13; end
                4'hb: begin base = 8'd197; delta = 8'd12; end
                4'hc: begin base = 8'd209; delta = 8'd12; end
                4'hd: begin base = 8'd221; delta = 8'd12; end
                4'he: begin base = 8'd233; delta = 8'd11; end
                default: begin base = 8'd244; delta = 8'd11; end
            endcase

            interpolation = delta * value[3:0] + 8;
            if (value == 8'hff)
                gamma07 = 8'hff;
            else
                gamma07 = base + (interpolation >> 4);
        end
    endfunction

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_tlast  <= 1'b0;
            O_tuser  <= 1'b0;
            O_tdata  <= 96'd0;
            O_tvalid <= 1'b0;
        end else begin
            O_tlast  <= I_tlast;
            O_tuser  <= I_tuser;
            O_tvalid <= I_tvalid;
            if (I_tvalid) begin
                O_tdata <= {
                    gamma07(I_tdata[95:88]), gamma07(I_tdata[87:80]), gamma07(I_tdata[79:72]),
                    gamma07(I_tdata[71:64]), gamma07(I_tdata[63:56]), gamma07(I_tdata[55:48]),
                    gamma07(I_tdata[47:40]), gamma07(I_tdata[39:32]), gamma07(I_tdata[31:24]),
                    gamma07(I_tdata[23:16]), gamma07(I_tdata[15:8]),  gamma07(I_tdata[7:0])
                };
            end else begin
                O_tdata <= 96'd0;
            end
        end
    end

endmodule


// Centre crop for the ISP's four-pixel-wide RGB888 stream.  Frame start is
// intentionally forwarded at the original frame boundary so video_in can
// reset its asynchronous FIFO before the first selected row arrives.
module axis_crop_rgb96 #(
    parameter integer IN_WIDTH   = 1792,
    parameter integer IN_HEIGHT  = 1080,
    parameter integer OUT_WIDTH  = 1600,
    parameter integer OUT_HEIGHT = 900,
    parameter integer X_START    = 96,
    parameter integer Y_START    = 90
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_tlast,
    input  wire        I_tuser,
    input  wire [95:0] I_tdata,
    input  wire        I_tvalid,
    output wire        O_tlast,
    output wire        O_tuser,
    output wire [95:0] O_tdata,
    output wire        O_tvalid
);

    localparam integer X_START_BEAT = X_START / 4;
    localparam integer OUT_BEATS    = OUT_WIDTH / 4;
    localparam integer X_END_BEAT   = X_START_BEAT + OUT_BEATS;

    reg [9:0]  S_hcnt;
    reg [10:0] S_vcnt;

    wire [9:0]  S_current_h = I_tuser ? 10'd0 : S_hcnt;
    wire [10:0] S_current_v = I_tuser ? 11'd0 : S_vcnt;
    wire S_inside = (S_current_h >= X_START_BEAT) &&
                    (S_current_h < X_END_BEAT) &&
                    (S_current_v >= Y_START) &&
                    (S_current_v < (Y_START + OUT_HEIGHT));

    assign O_tdata  = I_tdata;
    assign O_tvalid = I_tvalid && S_inside;
    assign O_tlast  = O_tvalid && (S_current_h == (X_END_BEAT - 1));
    assign O_tuser  = I_tuser;

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_hcnt <= 10'd0;
            S_vcnt <= 11'd0;
        end
        else if(I_tuser) begin
            S_hcnt <= (I_tvalid && !I_tlast) ? 10'd1 : 10'd0;
            S_vcnt <= (I_tvalid && I_tlast) ? 11'd1 : 11'd0;
        end
        else if(I_tvalid) begin
            if(I_tlast) begin
                S_hcnt <= 10'd0;
                S_vcnt <= (S_vcnt == IN_HEIGHT - 1) ? 11'd0 : S_vcnt + 1'b1;
            end
            else begin
                S_hcnt <= S_hcnt + 1'b1;
            end
        end
    end

endmodule

// Display-only middle-tone lift; detector, marker and lamp pixels retain the calibration path.
module axis_tone_rgb96 #(parameter integer ENABLE=1,DENOISE=1)(
    input wire clk,rst_n,
    input wire I_tlast,I_tuser,I_tvalid,
    input wire [95:0] I_tdata,
    output reg O_tlast,O_tuser,O_tvalid,
    output reg [95:0] O_tdata
);
    // A raw left neighbor, never a filtered feedback value. No line/frame RAM.
    // All RGB channels share one edge decision to protect chromatic edges.
    reg [23:0] raw_left;
    reg have_left;
    wire [95:0] filtered;
    function [23:0] soften;
        input [23:0] center,left;
        input left_valid;
        reg signed [8:0] dr,dg,db,diff,value;
        reg signed [5:0] rounded_delta;
        reg small_change;
        integer n;
        begin
            dr=$signed({1'b0,left[23:16]})-$signed({1'b0,center[23:16]});
            dg=$signed({1'b0,left[15:8]})-$signed({1'b0,center[15:8]});
            db=$signed({1'b0,left[7:0]})-$signed({1'b0,center[7:0]});
            small_change=left_valid && (center[23:16]>8 || center[15:8]>8 || center[7:0]>8) &&
                dr>= -9'sd12 && dr<=9'sd12 && dg>= -9'sd12 && dg<=9'sd12 && db>= -9'sd12 && db<=9'sd12;
            soften=center;
            for(n=0;n<3;n=n+1)begin
                diff=n==0?db:n==1?dg:dr;
                // Accepted deltas are -12..12, exactly representable in five bits.
                rounded_delta=$signed(diff[4:0])+6'sd2;
                value=$signed({1'b0,center[n*8+:8]})+(rounded_delta>>>2);
                if(small_change)soften[n*8+:8]=value[7:0];
            end
        end
    endfunction
    genvar p;
    generate for(p=0;p<4;p=p+1)begin:spatial
        if(p==0)assign filtered[95-p*24-:24]=DENOISE?soften(I_tdata[95-p*24-:24],raw_left,have_left && !I_tuser):I_tdata[95-p*24-:24];
        else assign filtered[95-p*24-:24]=DENOISE?soften(I_tdata[95-p*24-:24],I_tdata[119-p*24-:24],1'b1):I_tdata[95-p*24-:24];
    end endgenerate
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin raw_left<=0;have_left<=0;end
        else begin
            if(I_tuser)have_left<=0;
            if(I_tvalid)begin raw_left<=I_tdata[23:0];have_left<=!I_tlast;end
        end
    end
    // Register the edge-gated blend before the gain calculation. This cuts
    // the smoothing -> peak -> gain -> multiplier input timing path.
    reg [95:0] smoothed;
    reg smooth_valid,smooth_user,smooth_last;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin smoothed<=0;smooth_valid<=0;smooth_user<=0;smooth_last<=0;end
        else begin
            smoothed<=filtered;
            smooth_valid<=I_tvalid;smooth_user<=I_tuser;smooth_last<=I_tlast;
        end
    end
    reg [95:0] data1,data2;
    reg [7:0] strength1[0:3];
    reg [15:0] product2[0:11];
    reg [1:0] vpipe,upipe,lpipe;
    function [7:0] strength;
        input [23:0] p;
        reg [7:0] peak,remaining;
        begin
            peak=p[23:16]>p[15:8]?p[23:16]:p[15:8];
            if(p[7:0]>peak)peak=p[7:0];
            remaining=8'd255-peak;
            if(!ENABLE || peak<=8)strength=0;
            // Extra midtone lift with a 1.625x cap. Preserve all channels'
            // common ratio; near-black and pre-gain edge-gated denoise remain.
            // Seven-eighths headroom tapers gently before the highlights.
            else if(peak<48)strength=(peak-8'd8)<<2;
            else if(peak<74)strength=8'd160;
            else strength=remaining-(remaining>>3);
        end
    endfunction
    function [7:0] lift;
        input [7:0] channel;
        input [15:0] product;
        reg [16:0] rounded;
        reg [8:0] result;
        begin
            rounded={1'b0,product}+17'd128;
            result={1'b0,channel}+rounded[16:8];
            lift=result>255?8'd255:result[7:0];
        end
    endfunction
    genvar c;
    generate for(c=0;c<12;c=c+1)begin:channels
        always @(posedge clk)begin
            product2[c]<=data1[c*8+:8]*strength1[c/3];
        end
    end endgenerate
    integer lane,ch;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            data1<=0;data2<=0;vpipe<=0;upipe<=0;lpipe<=0;
            O_tdata<=0;O_tvalid<=0;O_tuser<=0;O_tlast<=0;
            for(lane=0;lane<4;lane=lane+1)strength1[lane]<=0;
        end else begin
            data1<=smoothed;data2<=data1;
            for(lane=0;lane<4;lane=lane+1)strength1[lane]<=strength(smoothed[lane*24+:24]);
            vpipe<={vpipe[0],smooth_valid};upipe<={upipe[0],smooth_user};lpipe<={lpipe[0],smooth_last};
            O_tvalid<=vpipe[1];O_tuser<=upipe[1];O_tlast<=lpipe[1];
            for(ch=0;ch<12;ch=ch+1)
                O_tdata[ch*8+:8]<=vpipe[1]?lift(data2[ch*8+:8],product2[ch]):8'd0;
        end
    end
endmodule
