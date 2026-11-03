// Authored two-stage OSD. Input user/last must accompany the same active pixel.
// Graphic palette is generated from the supplied Anlogic logo asset; overlay,
// text rasterization, coordinate tracking and timing alignment are original.
module video_osd (
    input wire clk, rst_n,
    input wire vsync, hsync, de, user, last,
    input wire [23:0] pixel,
    output reg out_vsync, out_hsync, out_de,
    output reg [23:0] out_pixel
);
    reg [11:0] x, y;
    wire [11:0] px = user ? 12'd0 : x;
    wire [11:0] py = user ? 12'd0 : y;
    wire logo_area = px >= 16 && px < 176 && py >= 16 && py < 176;
    wire [14:0] logo_addr = logo_area ? (py-12'd16)*15'd160 + (px-12'd16) : 15'd0;
    wire [1:0] logo_index;
    logo_index_rom logo(clk, logo_addr, logo_index);
    reg [23:0] base_d;
    reg vs_d, hs_d, de_d, logo_d, text_d, panel_d;
    wire text_area = px >= 192 && px < 480 && py >= 32 && py < 46;
    wire [8:0] text_x = px - 192;
    wire [4:0] char_index = text_x / 12;
    wire [3:0] char_x = text_x % 12;
    wire [2:0] char_y = (py - 32) >> 1;
    wire [7:0] code;
    wire [4:0] font_row;
    osd_title_char title(char_index, code);
    osd_font5x7 font(code, char_y, font_row);
    wire text_on = text_area && char_x < 10 && font_row[4-(char_x >> 1)];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x <= 0; y <= 0;
            base_d <= 0; vs_d <= 0; hs_d <= 0; de_d <= 0;
            logo_d <= 0; text_d <= 0; panel_d <= 0;
            out_vsync <= 0; out_hsync <= 0; out_de <= 0; out_pixel <= 0;
        end else begin
            if (de) begin
                x <= last ? 12'd0 : px + 1'b1;
                y <= last ? py + 1'b1 : py;
            end else if (user) begin x <= 0; y <= 0; end
            base_d <= pixel;
            vs_d <= vsync; hs_d <= hsync; de_d <= de;
            logo_d <= de && logo_area;
            text_d <= 1'b0;
            panel_d <= 1'b0;
            out_vsync <= vs_d; out_hsync <= hs_d; out_de <= de_d;
            if (!de_d) out_pixel <= 0;
            else if (logo_d && logo_index == 1) out_pixel <= 24'h1f315c;
            else if (logo_d && logo_index == 2) out_pixel <= 24'hec1c2d;
            else if (text_d) out_pixel <= 24'h00e6ff;
            else if (panel_d) out_pixel <= 24'h101820;
            else out_pixel <= base_d;
        end
    end
endmodule
