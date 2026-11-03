// Modes: 0 RGB, 1 gray, 2 binary, 3 Prewitt, 4 enhancement, 5 shapes, 6 motion, 7 cartoon.
// Legacy requested_color carries enhancement strength 1 LOW / 2 MED / 3 HIGH.
// Enhancement edge gating is fixed at 96, independent of PREWITT threshold.
// All paths have three clocks of latency. Requests latch only at input SOF,
// then the mode travels through the same pipeline as that frame's pixels.
module image_modes_96(
    input wire clk,rst_n,
    input wire I_tlast,I_tuser,I_tvalid,
    input wire [95:0] I_tdata,
    input wire [2:0] requested_mode,
    input wire [1:0] requested_color,
    input wire [7:0] requested_binary_threshold,requested_edge_threshold,requested_red_threshold,
    output wire O_tlast,O_tuser,O_tvalid,
    output wire [95:0] O_tdata,
    output wire [2:0] active_mode,
    output wire [7:0] active_threshold,
    output wire [1:0] active_color
);
    wire [95:0] rgb1,gray1,binary1,edge_data,enhance_data,cartoon_data;
    wire edge_user,edge_valid,edge_last;
    reg [95:0] rgb2,gray2,binary2,rgb3,gray3,binary3;
    reg [2:0] frame_mode,mode1,mode2,mode3;
    reg [1:0] frame_level;
    reg [7:0] frame_binary,frame_edge,frame_red,threshold1,threshold2,threshold3;
    wire [7:0] red_threshold=I_tuser?requested_red_threshold:frame_red;
    wire [7:0] binary_threshold=I_tuser?requested_binary_threshold:frame_binary;
    wire [7:0] edge_threshold=I_tuser?requested_edge_threshold:frame_edge;
    wire [2:0] selected_mode=I_tuser?requested_mode:frame_mode;
    wire [1:0] safe_level=requested_color==0?2'd1:requested_color;
    wire [1:0] enhance_level=I_tuser?safe_level:frame_level;
    natural_enhance_96 enhance_stage(.clk(clk),.rst_n(rst_n),
        .user(I_tuser),.valid(I_tvalid),.data(I_tdata),.level(enhance_level),
        .edge_mask({edge_data[95],edge_data[71],edge_data[47],edge_data[23]}),.color(enhance_data),.cartoon_color(cartoon_data));
    rgb_identity_96 original(
        .clk(clk),.rst_n(rst_n),.I_tlast(I_tlast),.I_tuser(I_tuser),
        .I_tvalid(I_tvalid),.I_tdata(I_tdata),.O_tlast(),.O_tuser(),.O_tvalid(),.O_tdata(rgb1));
    gray_transform_96 grayscale(
        .clk(clk),.rst_n(rst_n),.I_tlast(I_tlast),.I_tuser(I_tuser),
        .I_tvalid(I_tvalid),.I_tdata(I_tdata),.O_tlast(),.O_tuser(),.O_tvalid(),.O_tdata(gray1));
    binary_transform_96 binary_stage(
        .threshold(binary_threshold),
        .clk(clk),.rst_n(rst_n),.I_tlast(I_tlast),.I_tuser(I_tuser),
        .I_tvalid(I_tvalid),.I_tdata(I_tdata),.O_tlast(),.O_tuser(),.O_tvalid(),.O_tdata(binary1));
    prewitt_detect_96 edge_stage(
        .threshold(selected_mode==4?11'd96:{3'b0,edge_threshold}),
        .I_clk(clk),.I_rst_n(rst_n),.I_tlast(I_tlast),.I_tuser(I_tuser),
        .I_tdata(I_tdata),.I_tvalid(I_tvalid),.I_tready(1'b1),
        .O_tlast(edge_last),.O_tuser(edge_user),.O_tdata(edge_data),.O_tvalid(edge_valid),.O_tready()
    );
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin frame_level<=2;rgb2<=0;gray2<=0;binary2<=0;rgb3<=0;gray3<=0;binary3<=0;frame_mode<=3;mode1<=3;mode2<=3;mode3<=3; frame_binary<=96;frame_edge<=96;frame_red<=32;threshold1<=96;threshold2<=96;threshold3<=96; end
        else begin
            rgb2<=rgb1; gray2<=gray1; binary2<=binary1;
            rgb3<=rgb2;gray3<=gray2;binary3<=binary2;
            if(I_tuser) begin
                frame_mode<=requested_mode;
                frame_binary<=requested_binary_threshold;frame_edge<=requested_edge_threshold;frame_red<=requested_red_threshold;
            end
            if(I_tuser)frame_level<=safe_level;
            mode1<=I_tuser ? requested_mode : frame_mode;
            mode2<=mode1;mode3<=mode2;
            // Use existing variable threshold bits [4:3], not new transport registers.
            threshold1<=selected_mode==4?{3'b0,enhance_level,3'b0}:selected_mode==2 ? binary_threshold : (selected_mode==5 || selected_mode==6) ? red_threshold : edge_threshold;
            threshold2<=threshold1;threshold3<=threshold2;
        end
    end
    assign active_mode=mode3;
    assign active_color=2'd0; // SHAPES is simultaneous RGB, never a color selector.
    assign active_threshold=threshold3;
    assign O_tuser=edge_user;
    assign O_tvalid=edge_valid;
    assign O_tlast=edge_last;
    assign O_tdata=mode3==0 ? rgb3 : mode3==1 ? gray3 : mode3==2 ? binary3 : mode3==3 ? edge_data : mode3==4 ? enhance_data : mode3==7 ? cartoon_data : rgb3;
endmodule
