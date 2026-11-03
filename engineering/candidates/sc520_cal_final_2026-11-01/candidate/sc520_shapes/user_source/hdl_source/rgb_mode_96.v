// Camera-stream pixel modes, four RGB888 pixels per beat.
// All three stages are registered once so mode selection preserves AXI timing.
module rgb_identity_96(
    input wire clk, rst_n, input wire I_tlast, I_tuser, I_tvalid,
    input wire [95:0] I_tdata,
    output reg O_tlast, O_tuser, O_tvalid, output reg [95:0] O_tdata
);
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin O_tlast<=0; O_tuser<=0; O_tvalid<=0; O_tdata<=0; end
    else begin O_tlast<=I_tlast; O_tuser<=I_tuser; O_tvalid<=I_tvalid; O_tdata<=I_tdata; end
end
endmodule

module gray_transform_96(
    input wire clk, rst_n, input wire I_tlast, I_tuser, I_tvalid,
    input wire [95:0] I_tdata,
    output reg O_tlast, O_tuser, O_tvalid, output reg [95:0] O_tdata
);
function [7:0] gray;
 input [23:0] p; reg [9:0] sum;
 begin sum={2'b0,p[23:16]}+{1'b0,p[15:8],1'b0}+{2'b0,p[7:0]}; gray=sum[9:2]; end
endfunction
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin O_tlast<=0; O_tuser<=0; O_tvalid<=0; O_tdata<=0; end
    else begin
        O_tlast<=I_tlast; O_tuser<=I_tuser; O_tvalid<=I_tvalid;
        O_tdata<= {{3{gray(I_tdata[95:72])}},{3{gray(I_tdata[71:48])}},{3{gray(I_tdata[47:24])}},{3{gray(I_tdata[23:0])}}};
    end
end
endmodule

module binary_transform_96 #(
    parameter [7:0] THRESHOLD=8'd96
)(
    input wire clk, rst_n, input wire I_tlast, I_tuser, I_tvalid,
    input wire [95:0] I_tdata,
    input wire [7:0] threshold,
    output reg O_tlast, O_tuser, O_tvalid, output reg [95:0] O_tdata
);
function [23:0] binary;
 input [23:0] p; reg [9:0] sum; reg [7:0] y;
 begin sum={2'b0,p[23:16]}+{1'b0,p[15:8],1'b0}+{2'b0,p[7:0]}; y=sum[9:2]; binary=(y>=threshold)?24'hffffff:24'h000000; end
endfunction
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin O_tlast<=0; O_tuser<=0; O_tvalid<=0; O_tdata<=0; end
    else begin
        O_tlast<=I_tlast; O_tuser<=I_tuser; O_tvalid<=I_tvalid;
        O_tdata<={binary(I_tdata[95:72]),binary(I_tdata[71:48]),binary(I_tdata[47:24]),binary(I_tdata[23:0])};
    end
end
endmodule
