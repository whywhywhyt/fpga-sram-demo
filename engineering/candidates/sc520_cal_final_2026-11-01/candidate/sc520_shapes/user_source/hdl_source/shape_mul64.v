// Shared unsigned shift/add multiplier. No '/' and no replicated wide DSPs.
// The low PRODUCT_W product bits are valid at done and held until start.
// Reuse the result register as the accumulator; intermediate values are busy.
module shape_mul64 #(parameter integer PRODUCT_W=64, B_W=34)(
    input wire clk,rst_n,start,
    input wire [PRODUCT_W-1:0] a,
    input wire [B_W-1:0] b,
    output reg busy,done,
    output reg [PRODUCT_W-1:0] result
);
    reg [PRODUCT_W-1:0] shift_a;
    reg [B_W-1:0] shift_b;
    reg [5:0] remaining;
    wire [PRODUCT_W-1:0] step=result+(shift_b[0]?shift_a:{PRODUCT_W{1'b0}});
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin busy<=0;done<=0;result<=0;shift_a<=0;shift_b<=0;remaining<=0;end
        else begin
            done<=0;
            if(start && !busy)begin busy<=1;remaining<=B_W;result<=0;shift_a<=a;shift_b<=b;end
            else if(busy)begin
                result<=step;shift_a<=shift_a<<1;shift_b<=shift_b>>1;remaining<=remaining-1'b1;
                if(remaining==1)begin busy<=0;done<=1;end
            end
        end
    end
endmodule
