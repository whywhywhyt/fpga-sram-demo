// Authored frame latency measurement. Time tags travel IN the RGB payload,
// through the real DDR FIFOs, not through an unrelated buffer-pointer bus.
// Time unit 0.1 ms. 24-bit modulo clock wraps after about 28 minutes.
// Use the board's actual 50 MHz oscillator, not the nominally named
// S_24m_clk (the camera PLL output is really 1500/63 = 23.8095 MHz).
module latency_timebase #(parameter integer TICK_CYCLES=5000)(
    input wire clk,rst_n,output reg [23:0] gray
);
    localparam integer DW=TICK_CYCLES<2?1:$clog2(TICK_CYCLES);
    reg [DW-1:0] divider;
    reg [23:0] ticks;
    wire [23:0] next_ticks=ticks+1'b1;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)begin divider<=0;ticks<=0;gray<=0;end
        else if(divider==TICK_CYCLES-1)begin
            divider<=0;ticks<=next_ticks;gray<=next_ticks^(next_ticks>>1);
        end else divider<=divider+1'b1;
endmodule

module latency_clock_sync(input wire clk,rst_n,input wire [23:0] gray,
    output wire [23:0] ticks);
    (* async_reg="true" *) reg [23:0] sync1,sync2;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)begin sync1<=0;sync2<=0;end
        else begin sync1<=gray;sync2<=sync1;end
    genvar k;
    generate for(k=0;k<24;k=k+1)begin:decode
        assign ticks[k]=^sync2[23:k];
    end endgenerate
endmodule

module latency_capture(input wire clk,rst_n,sof,input wire [23:0] ticks,
    output reg [95:0] tag);
    reg [15:0] frame_id;
    wire [15:0] next_id=frame_id+1'b1;
    wire [7:0] check_byte=8'ha5^next_id[15:8]^next_id[7:0]^
        ticks[23:16]^ticks[15:8]^ticks[7:0];
    always @(posedge clk or negedge rst_n)
        if(!rst_n)begin frame_id<=0;tag<=0;end
        else if(sof)begin
            frame_id<=next_id;
            tag<={24'h4c4154,next_id,ticks,~ticks,check_byte};
        end
endmodule

// Reserve the first and last EIGHT pixels of each frame (16 / 921600).
// Each end contains a 96-bit tag and its inverse. No extra FIFO words.
module latency_tag_96 #(parameter integer WIDTH=1280,HEIGHT=720)(
    input wire clk,rst_n,user,valid,input wire [95:0] pixel,tag,
    output wire [95:0] tagged_pixel
);
    localparam integer GROUPS=WIDTH*HEIGHT/4;
    localparam integer CW=$clog2(GROUPS);
    reg [CW-1:0] group_index;
    reg [95:0] frame_tag;
    wire [CW-1:0] current_group=user?0:group_index;
    wire [95:0] current_tag=user?tag:frame_tag;
    assign tagged_pixel=(current_group==0 || current_group==GROUPS-2)?current_tag:
        (current_group==1 || current_group==GROUPS-1)?~current_tag:pixel;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)begin group_index<=0;frame_tag<=0;end
        else begin
            if(user)begin group_index<=0;frame_tag<=tag;end
            if(valid)group_index<=current_group==GROUPS-1?0:current_group+1'b1;
        end
endmodule

// Samples the time of the FIRST displayed pixel, validates both ends at the
// LAST pixel, then publishes a previous-complete-frame result. Missing tags,
// torn frame IDs, read underflow and implausible ages never produce VALID.
module latency_reader #(parameter integer WIDTH=1280,HEIGHT=720)(
    input wire clk,rst_n,de,user,last,underflow,
    input wire [23:0] pixel,ticks,
    output wire [23:0] clean_pixel,
    output reg sample_valid,output reg sample_done,
    output reg [23:0] latency_ticks,
    output reg [15:0] displayed_id,
    output reg repeated,output reg [15:0] repeat_count
);
    reg [11:0] x,y;
    wire [11:0] px=user?0:x,py=user?0:y;
    reg [95:0] shift,head;
    reg head_ok,tail_ok;
    reg [23:0] first_tick;
    reg have_previous;
    reg [15:0] previous_id;
    wire [95:0] collected={shift[71:0],pixel};
    wire [7:0] expected_check=8'ha5^head[71:64]^head[63:56]^
        head[55:48]^head[47:40]^head[39:32];
    wire [23:0] age=first_tick-head[55:32];
    wire head_area=py==0 && px<8;
    wire tail_area=py==HEIGHT-1 && px>=WIDTH-8;
    assign clean_pixel=(head_area || tail_area)?24'd0:pixel;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)begin
            x<=0;y<=0;shift<=0;head<=0;head_ok<=0;tail_ok<=0;
            first_tick<=0;sample_valid<=0;sample_done<=0;latency_ticks<=0;
            displayed_id<=0;repeated<=0;repeat_count<=0;have_previous<=0;previous_id<=0;
        end else begin
            sample_done<=0;
            if(user)begin x<=0;y<=0;head_ok<=0;tail_ok<=0;sample_valid<=0;end
            if(de)begin
                x<=last?0:px+1'b1;y<=last?py+1'b1:py;
                if(px==0 && py==0)begin first_tick<=ticks;head_ok<=0;tail_ok<=0;end
                if(head_area || tail_area)shift<=collected;
                if(py==0 && px==3)head<=collected;
                if(py==0 && px==7)head_ok<=collected==~head &&
                    head[95:72]==24'h4c4154 && head[31:8]==~head[55:32] &&
                    head[7:0]==expected_check;
                if(py==HEIGHT-1 && px==WIDTH-5)tail_ok<=collected==head;
                if(py==HEIGHT-1 && px==WIDTH-1)begin
                    sample_done<=1;
                    sample_valid<=head_ok && tail_ok && collected==~head && !underflow && age<10000;
                    if(head_ok && tail_ok && collected==~head && !underflow && age<10000)begin
                        latency_ticks<=age;displayed_id<=head[71:56];
                        repeated<=have_previous && previous_id==head[71:56];
                        if(have_previous && previous_id==head[71:56])repeat_count<=repeat_count+1'b1;
                        previous_id<=head[71:56];have_previous<=1;
                    end
                end
            end
        end
endmodule

// Low-cost serial binary-to-BCD, five decimal digits = 0000.0 ms.
module latency_bcd(input wire clk,rst_n,start,input wire [23:0] value,
    output reg [19:0] digits,output reg ready);
    reg [23:0] binary;
    reg [19:0] scratch;
    reg [4:0] count;
    reg busy;
    reg [19:0] adjusted;
    integer n;
    always @(*)begin
        adjusted=scratch;
        for(n=0;n<5;n=n+1)
            if(scratch[n*4+:4]>=5)adjusted[n*4+:4]=scratch[n*4+:4]+4'd3;
    end
    always @(posedge clk or negedge rst_n)
        if(!rst_n)begin binary<=0;scratch<=0;count<=0;busy<=0;digits<=0;ready<=0;end
        else begin
            ready<=0;
            if(start)begin binary<=value;scratch<=0;count<=0;busy<=1;end
            else if(busy)begin
                scratch<={adjusted[18:0],binary[23]};binary<=binary<<1;
                if(count==23)begin digits<={adjusted[18:0],binary[23]};ready<=1;busy<=0;end
                else count<=count+1'b1;
            end
        end
endmodule

// Same input/output timing as the existing two-cycle Logo OSD; text is
// composited before that OSD. Results latch once per displayed frame.
// Compact presentation panel. Timestamp measurement and its validity checks
// remain unchanged. Invalid samples explicitly display WAIT, never stale ms.
module latency_panel(input wire clk,rst_n,de,user,last,
 input wire [23:0] pixel,input wire sample_done,sample_valid,
 input wire [23:0] latency_ticks,input wire [15:0] displayed_id,repeat_count,
 input wire repeated,output wire [23:0] out_pixel);
 reg [11:0] x,y;
 wire [11:0] px=user?0:x,py=user?0:y;
 wire [19:0] new_digits;wire digits_ready;
 latency_bcd convert(clk,rst_n,sample_done && sample_valid,latency_ticks,new_digits,digits_ready);
 reg valid_hold,pending_valid,pending_seen;reg [19:0] digits;
 wire region=de && px>=944 && px<1264 && py>=16 && py<48;
 wire [8:0] dx=px-952;wire [4:0] dy=py-24;wire [4:0] pos=dx>>4;
 reg [7:0] code;
 always @*begin
  code=32;
  case(pos)
   0:code=8'd169;1:code=8'd170;2:code=8'd171;3:code=8'd172;
   5:code=valid_hold?48+digits[19:16]:8'd173;
   6:code=valid_hold?48+digits[15:12]:8'd140;
   7:if(valid_hold)code=48+digits[11:8];
   8:if(valid_hold)code=48+digits[7:4];
   9:if(valid_hold)code=".";
   10:if(valid_hold)code=48+digits[3:0];
   12:if(valid_hold)code="m";
   13:if(valid_hold)code="s";
   default:code=32;
  endcase
 end
 wire [15:0] glyph;
 presentation_font16 font(.code(code),.row(dy[3:0]),.bits(glyph));
 wire ink=px>=952 && py>=24 && py<40 && glyph[15-dx[3:0]];
 assign out_pixel=region?(ink?(valid_hold?24'hf0f4f8:24'hffd080):24'h101820):pixel;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin x<=0;y<=0;valid_hold<=0;pending_valid<=0;pending_seen<=0;digits<=0;end
  else begin
   if(user)begin x<=0;y<=0;valid_hold<=pending_seen && pending_valid;pending_seen<=0;digits<=new_digits;end
   if(de)begin x<=last?0:px+1'b1;y<=last?py+1'b1:py;end
   if(sample_done)begin pending_valid<=sample_valid;pending_seen<=1;end
  end
 end
endmodule
