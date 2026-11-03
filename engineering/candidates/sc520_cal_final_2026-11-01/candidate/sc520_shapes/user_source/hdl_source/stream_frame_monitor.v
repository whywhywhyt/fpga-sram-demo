// Count accepted words between SOF pulses, including SOF+valid coincidences.
// The first SOF arms measurement; a later SOF publishes the preceding frame.
module stream_frame_monitor #(
    parameter integer EXPECTED_WORDS = 172800
)(
    input wire clk, rst_n, sof, valid,
    output reg seen, completed, good_seen, bad_seen,
    output reg [19:0] last_words
);
    reg [19:0] words;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            seen <= 0; completed <= 0; good_seen <= 0; bad_seen <= 0;
            words <= 0; last_words <= 0;
        end else if(sof) begin
            seen <= 1;
            if(seen) begin
                completed <= 1;
                last_words <= words;
                if(words == EXPECTED_WORDS) good_seen <= 1;
                else bad_seen <= 1;
            end
            words <= valid ? 20'd1 : 20'd0;
        end else if(seen && valid && words != 20'hfffff) begin
            words <= words + 1'b1;
        end
    end
endmodule
