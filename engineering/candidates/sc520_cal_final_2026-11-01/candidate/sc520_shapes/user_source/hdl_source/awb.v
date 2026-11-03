// Neutral-candidate AWB, RGB888 x4, MSB-first. Original contest RTL.
// Reject strongly colored, near-black and clipped reference pixels. Hold the
// last calibration when the scene has too few neutral candidates. Preserve
// the existing pixel pipeline, divider and SOF-only atomic gain publication.
// SOF intentionally precedes output by >=64 clocks for video_in FIFO reset.
module awb #(
    parameter integer IMG_HEIGHT=1080, IMG_WIDTH=1920,
    parameter integer MIN_SAMPLES=128
)(
    input I_clk,I_rst_n,I_tlast,I_tuser,
    input [95:0] I_tdata,
    input I_tvalid,
    output I_tready,O_tlast,O_tuser,
    output [95:0] O_tdata,
    output O_tvalid,
    input O_tready,
    input I_calibrate,I_cal_toggle,I_cal_clear,
    output wire [159:0] O_spatial_diag,
    output wire [172:0] O_diagnostics
);
    localparam integer FRAME_BEATS=IMG_HEIGHT*(IMG_WIDTH/4);
    localparam integer CW=(FRAME_BEATS<2)?1:$clog2(FRAME_BEATS);
    // At least 1/128 of the image must support a new illuminant estimate;
    // a handful of incidental gray/noisy pixels cannot retint the whole frame.
    localparam integer FRAME_MIN_SAMPLES=(IMG_HEIGHT*IMG_WIDTH+127)/128;
    localparam integer REQUIRED_SAMPLES=MIN_SAMPLES>FRAME_MIN_SAMPLES?
                                               MIN_SAMPLES:FRAME_MIN_SAMPLES;
    reg [27:0] sum_r,sum_g,sum_b;
    reg [21:0] samples;
    reg [CW-1:0] count;
    reg collecting;
    reg [15:0] gain_r,gain_b,pending_r,pending_b;
    reg pending_ready,acquired;
    reg [15:0] diagnostic_updates;
    reg [17:0] diagnostic_frame_words;
    function eligible;
        input [23:0] p;
        reg [7:0] hi,lo;
        reg [9:0] total;
        begin
            hi=p[23:16]>p[15:8]?p[23:16]:p[15:8];
            if(p[7:0]>hi)hi=p[7:0];
            lo=p[23:16]<p[15:8]?p[23:16]:p[15:8];
            if(p[7:0]<lo)lo=p[7:0];
            total={2'b0,p[23:16]}+{2'b0,p[15:8]}+{2'b0,p[7:0]};
            eligible=total>=96 && hi<240 && lo>=(hi-(hi>>1));
        end
    endfunction
    wire [3:0] ok;
    wire [7:0] sr[0:3],sg[0:3],sb[0:3];
    reg [3:0] screen_ok;
    reg [7:0] screen_r[0:3],screen_g[0:3],screen_b[0:3];
    reg screen_user,screen_take,screen_end;
    genvar lane;
    generate for(lane=0;lane<4;lane=lane+1)begin:statistics
        assign ok[lane]=eligible(I_tdata[lane*24+:24]);
        assign sr[lane]=ok[lane]?I_tdata[lane*24+16+:8]:8'd0;
        assign sg[lane]=ok[lane]?I_tdata[lane*24+8+:8]:8'd0;
        assign sb[lane]=ok[lane]?I_tdata[lane*24+:8]:8'd0;
        always @(posedge I_clk or negedge I_rst_n)begin
            if(!I_rst_n)begin screen_r[lane]<=0;screen_g[lane]<=0;screen_b[lane]<=0;end
            else begin screen_r[lane]<=sr[lane];screen_g[lane]<=sg[lane];screen_b[lane]<=sb[lane];end
        end
    end endgenerate
    wire [9:0] batch_r={2'b0,screen_r[0]}+{2'b0,screen_r[1]}+{2'b0,screen_r[2]}+{2'b0,screen_r[3]};
    wire [9:0] batch_g={2'b0,screen_g[0]}+{2'b0,screen_g[1]}+{2'b0,screen_g[2]}+{2'b0,screen_g[3]};
    wire [9:0] batch_b={2'b0,screen_b[0]}+{2'b0,screen_b[1]}+{2'b0,screen_b[2]}+{2'b0,screen_b[3]};
    wire [2:0] batch_n={2'b0,screen_ok[0]}+{2'b0,screen_ok[1]}+{2'b0,screen_ok[2]}+{2'b0,screen_ok[3]};
    wire [CW-1:0] position=I_tuser?{CW{1'b0}}:count;
    wire take=I_tvalid && (collecting || I_tuser);
    wire complete=take && position==FRAME_BEATS-1;
    // Observe the existing pipeline only. Neither field controls AWB.
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin diagnostic_updates<=0;diagnostic_frame_words<=0;end
        else begin
            if(I_tuser && pending_ready)diagnostic_updates<=diagnostic_updates+1'b1;
            if(complete)diagnostic_frame_words<=FRAME_BEATS;
            else if(I_tuser && collecting)diagnostic_frame_words<=count;
        end
    end
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin screen_ok<=0;screen_user<=0;screen_take<=0;screen_end<=0;end
        else begin screen_ok<=ok;screen_user<=I_tuser;screen_take<=take;screen_end<=complete;end
    end
    // Separate raw-pixel screening from accumulation and divider enables.
    // MIPI_RX_BYTE_CLK is 9.66 ns: do not join all three in one clock path.
    reg [9:0] batch_r_q,batch_g_q,batch_b_q;
    reg [2:0] batch_n_q;
    reg batch_user,batch_take,batch_end;
    reg [27:0] job_r,job_g,job_b;
    reg [21:0] job_samples;
    reg job_valid;
    assign O_diagnostics={acquired,gain_r,gain_b,diagnostic_updates,
                          job_samples,job_r,job_g,job_b,diagnostic_frame_words};
    wire [27:0] next_r=(batch_user?28'd0:sum_r)+batch_r_q;
    wire [27:0] next_g=(batch_user?28'd0:sum_g)+batch_g_q;
    wire [27:0] next_b=(batch_user?28'd0:sum_b)+batch_b_q;
    wire [21:0] next_n=(batch_user?22'd0:samples)+batch_n_q;
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin count<=0;collecting<=0;end
        else begin
            if(I_tuser)begin count<=0;collecting<=1;end
            if(take)begin
                count<=complete?{CW{1'b0}}:position+1'b1;
                if(complete)collecting<=0;
            end
        end
    end
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            batch_r_q<=0;batch_g_q<=0;batch_b_q<=0;batch_n_q<=0;
            batch_user<=0;batch_take<=0;batch_end<=0;
            sum_r<=0;sum_g<=0;sum_b<=0;samples<=0;
            job_r<=0;job_g<=0;job_b<=0;job_samples<=0;job_valid<=0;
        end else begin
            batch_r_q<=batch_r;batch_g_q<=batch_g;batch_b_q<=batch_b;batch_n_q<=batch_n;
            batch_user<=screen_user;batch_take<=screen_take;batch_end<=screen_end;
            if(batch_user)begin sum_r<=0;sum_g<=0;sum_b<=0;samples<=0;end
            if(batch_take)begin sum_r<=next_r;sum_g<=next_g;sum_b<=next_b;samples<=next_n;end
            job_valid<=batch_end;
            if(batch_end)begin job_r<=next_r;job_g<=next_g;job_b<=next_b;job_samples<=next_n;end
        end
    end
    wire ratio_busy,ratio_done;
    wire [15:0] ratio_r,ratio_b;
    wire cal_request,cal_enabled;
    wire [27:0] cal_sum_r,cal_sum_g,cal_sum_b;
    wire [15:0] spatial_r,spatial_b;
    reg ratio_owner;
    wire local_start=cal_request && !ratio_busy;
    wire global_start=job_valid && !ratio_busy && !cal_request &&
                      job_samples>=REQUIRED_SAMPLES && job_r!=0 && job_b!=0;
    always @(posedge I_clk or negedge I_rst_n)
        if(!I_rst_n)ratio_owner<=0;
        else if(local_start || global_start)ratio_owner<=local_start;
    awb_spatial_calibration #(.WIDTH(IMG_WIDTH),.HEIGHT(IMG_HEIGHT)) spatial(
        .clk(I_clk),.rst_n(I_rst_n),.user(I_tuser),.valid(I_tvalid),.data(I_tdata),
        .calibrate(I_calibrate===1'b1),.toggle(I_cal_toggle===1'b1),.clear(I_cal_clear===1'b1),
        .ratio_request(cal_request),.ratio_accept(local_start),
        .sum_r(cal_sum_r),.sum_g(cal_sum_g),.sum_b(cal_sum_b),
        .ratio_done(ratio_done && ratio_owner),.ratio_r(ratio_r),.ratio_b(ratio_b),
        .enabled(cal_enabled),.pixel_r(spatial_r),.pixel_b(spatial_b),.diagnostics(O_spatial_diag));
    awb_serial_ratio calculator(.clk(I_clk),.rst_n(I_rst_n),
        .start(local_start || global_start),
        .sum_g(local_start?cal_sum_g:job_g),.sum_r(local_start?cal_sum_r:job_r),.sum_b(local_start?cal_sum_b:job_b),
        .busy(ratio_busy),.done(ratio_done),.gain_r(ratio_r),.gain_b(ratio_b));
    function [15:0] smooth;
        input [15:0] current,target;
        reg signed [16:0] difference,value,step_value;
        begin
            difference=$signed({1'b0,target})-$signed({1'b0,current});
            // Q4.12 deadband (24/4096) suppresses noise-driven gain hunting.
            // A bounded 1/8 update adapts to lighting while limiting transient
            // global hue changes as objects enter/leave the reference pool.
            if(difference>=-17'sd24 && difference<=17'sd24)step_value=0;
            else if(difference>17'sd512)step_value=17'sd64;
            else if(difference< -17'sd512)step_value= -17'sd64;
            else step_value=difference>>>3;
            value=$signed({1'b0,current})+step_value;
            smooth=value[15:0];
        end
    endfunction
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            gain_r<=16'h1000;gain_b<=16'h1000;pending_r<=16'h1000;pending_b<=16'h1000;
            pending_ready<=0;acquired<=0;
        end else begin
            if(I_tuser && pending_ready)begin
                gain_r<=pending_r;gain_b<=pending_b;pending_ready<=0;acquired<=1;
            end
            if(ratio_done && !ratio_owner)begin
                pending_r<=acquired?smooth(gain_r,ratio_r):ratio_r;
                pending_b<=acquired?smooth(gain_b,ratio_b):ratio_b;
                pending_ready<=1;
            end
        end
    end
    wire [15:0] use_r=cal_enabled?spatial_r:(I_tuser && pending_ready)?pending_r:gain_r;
    wire [15:0] use_b=cal_enabled?spatial_b:(I_tuser && pending_ready)?pending_b:gain_b;
    reg [23:0] product_r[0:3],product_b[0:3];
    reg [7:0] green[0:3];
    reg product_valid,product_last;
    wire [95:0] corrected;
    generate for(lane=0;lane<4;lane=lane+1)begin:pixels
        always @(posedge I_clk)begin
            product_r[lane]<=use_r*I_tdata[lane*24+16+:8];
            product_b[lane]<=use_b*I_tdata[lane*24+:8];
            green[lane]<=I_tdata[lane*24+8+:8];
        end
        assign corrected[lane*24+16+:8]=|product_r[lane][23:20]?8'd255:product_r[lane][19:12];
        assign corrected[lane*24+8+:8]=green[lane];
        assign corrected[lane*24+:8]=|product_b[lane][23:20]?8'd255:product_b[lane][19:12];
    end endgenerate
    // Fixed delay uses 96x64 RAM; reset/SOF clears validity, not memory.
    (* ram_style="block" *) reg [95:0] delay_ram[0:63];
    reg [5:0] address;
    wire [5:0] read_address=address+6'd1;
    reg [95:0] delayed;
    reg [63:0] valid_pipe,last_pipe;
    always @(posedge I_clk)begin
        if(I_rst_n)begin
            delay_ram[address]<=corrected;
            delayed<=delay_ram[read_address];
        end
    end
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin address<=0;valid_pipe<=0;last_pipe<=0;product_valid<=0;product_last<=0;end
        else begin
            address<=address+1'b1;
            product_valid<=I_tvalid;
            product_last<=I_tlast;
            if(I_tuser)begin valid_pipe<=0;last_pipe<=0;end
            else begin
                valid_pipe<={valid_pipe[62:0],product_valid};
                last_pipe<={last_pipe[62:0],product_last};
            end
        end
    end
    assign I_tready=O_tready;
    assign O_tuser=I_rst_n && I_tuser;
    assign O_tvalid=I_rst_n && !I_tuser && valid_pipe[63];
    assign O_tlast=O_tvalid && last_pipe[63];
    assign O_tdata=O_tvalid?delayed:96'd0;
endmodule

// Restoring division (G<<12)/R then (G<<12)/B, 40 clocks per channel.
module awb_serial_ratio(
    input clk,rst_n,start,
    input [27:0] sum_g,sum_r,sum_b,
    output reg busy,done,
    output reg [15:0] gain_r,gain_b
);
    reg [39:0] dividend,quotient,saved_numerator;
    reg [27:0] denominator,saved_b;
    reg [28:0] remainder;
    reg [5:0] step;
    reg channel;
    wire [28:0] shifted={remainder[27:0],dividend[39]};
    wire subtract=shifted>={1'b0,denominator};
    wire [28:0] next_remainder=subtract?shifted-{1'b0,denominator}:shifted;
    wire [39:0] next_quotient={quotient[38:0],subtract};
    function [15:0] limited;
        input [39:0] value;
        begin
            if(value<40'd2048)limited=16'd2048;
            else if(value>40'd16384)limited=16'd16384;
            else limited=value[15:0];
        end
    endfunction
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            busy<=0;done<=0;gain_r<=4096;gain_b<=4096;
            dividend<=0;quotient<=0;saved_numerator<=0;denominator<=0;saved_b<=0;
            remainder<=0;step<=0;channel<=0;
        end else begin
            done<=0;
            if(start && !busy)begin
                busy<=1;channel<=0;step<=0;remainder<=0;quotient<=0;
                dividend<={sum_g,12'd0};saved_numerator<={sum_g,12'd0};
                denominator<=sum_r;saved_b<=sum_b;
            end else if(busy)begin
                remainder<=next_remainder;dividend<={dividend[38:0],1'b0};
                quotient<=next_quotient;step<=step+1'b1;
                if(step==39)begin
                    if(!channel)begin
                        gain_r<=denominator==0?16'd4096:limited(next_quotient);
                        channel<=1;step<=0;remainder<=0;quotient<=0;
                        dividend<=saved_numerator;denominator<=saved_b;
                    end else begin
                        gain_b<=denominator==0?16'd4096:limited(next_quotient);
                        busy<=0;done<=1;
                    end
                end
            end
        end
    end
endmodule

// Explicit four-frame white-field calibration. Five symmetric sample patches,
// full-height sampling, shared AWB divider and unchanged eight pixel DSPs.
// Valid local G/R and G/B gains always replace (never multiply) global AWB.
// The legacy toggle port is intentionally inert; no CAL OFF state exists.
module awb_spatial_calibration #(
 parameter integer WIDTH=1280,HEIGHT=720,CAL_FRAMES=4
)(
 input clk,rst_n,user,valid,input [95:0] data,
 input calibrate,toggle,clear,
 output wire ratio_request,input ratio_accept,
 output wire [27:0] sum_r,sum_g,sum_b,
 input ratio_done,input [15:0] ratio_r,ratio_b,
 output wire enabled,output wire [15:0] pixel_r,pixel_b,
 output wire [159:0] diagnostics
);
 localparam integer LOGSTEP=$clog2(WIDTH)-2;
 localparam integer STEP=1<<LOGSTEP;
 localparam integer K0=WIDTH/2-STEP,K1=WIDTH/2,K2=WIDTH/2+STEP;
 localparam integer HALF=(STEP/8<4)?4:STEP/8;
 localparam integer SX=WIDTH>=512?16:4;
 localparam integer YLOG=$clog2(HEIGHT)-2,YSTEP=1<<YLOG;
 localparam integer T0=HEIGHT/2-YSTEP,T1=HEIGHT/2,T2=HEIGHT/2+YSTEP;
 localparam integer YHALF=(YSTEP/4<2)?2:YSTEP/4;
 localparam integer ROWS=2*YHALF/4;
 localparam integer YPHASE=(ROWS%2==0)?2:0;
 localparam integer XPHASE=SX>=8?SX/2:0;
 localparam integer SAMPLES=2*HALF/SX*ROWS*CAL_FRAMES;
 localparam integer COUNTW=$clog2(SAMPLES+1),GAINW=14;
 localparam integer MINIMUM=(SAMPLES*9+9)/10;
 localparam integer SUMW=$clog2(SAMPLES*255+1);
 localparam integer BEATS=WIDTH/4*HEIGHT;
 localparam integer CW=$clog2(BEATS+1);
 localparam IDLE=0,SETTLE=1,CAPTURE=2,CHECK=3,REQUEST=4,WAIT_RATIO=5,READY=6;
 (* fsm_encoding="none" *) reg [2:0] state;
 reg [10:0] x,y;
 (* fsm_encoding="none" *) reg [CW-1:0] words;
 reg in_frame;
 (* fsm_encoding="none" *) reg [2:0] frames;
 (* fsm_encoding="none" *) reg [1:0] settle;
 reg [2:0] zone;
 reg [SUMW-1:0] reds[0:4],greens[0:4],blues[0:4];
 reg [COUNTW-1:0] counts[0:4];
 reg [GAINW-1:0] knots_r[0:4],knots_b[0:4],pending_r[0:4],pending_b[0:4];
 reg table_valid,publish,failed,clear_wait;
 reg [7:0] generation;
 wire sof=user;
 wire take=valid && (in_frame || sof);
 wire [10:0] px=sof?11'd0:x,py=sof?11'd0:y;
 wire finish=take && (sof?0:words)==BEATS-1;
 // Five disjoint, symmetrically sampled patches: L,C,R,T,B.
 wire [10:0] sample_x=SX>=8?px:px+11'd2;
 wire hband=(sample_x>=K0-HALF && sample_x<K0+HALF)||
            (sample_x>=K1-HALF && sample_x<K1+HALF)||
            (sample_x>=K2-HALF && sample_x<K2+HALF);
 wire middle_x=sample_x>=K1-HALF && sample_x<K1+HALF;
 wire middle_y=py>=T1-YHALF && py<T1+YHALF;
 wire vband=(py>=T0-YHALF && py<T0+YHALF)||middle_y||
            (py>=T2-YHALF && py<T2+YHALF);
 wire [2:0] sample_zone=!middle_y?(py<T1?3'd3:3'd4):
                         sample_x<K1-HALF?3'd0:sample_x<K2-HALF?3'd1:3'd2;
 wire sample=take && ((middle_y && hband)||(middle_x && vband)) &&
             px%SX==XPHASE && py%4==YPHASE;
 wire [23:0] reference_pixel=SX>=8?data[95:72]:data[47:24];
 wire [7:0] r=reference_pixel[23:16],g=reference_pixel[15:8],b=reference_pixel[7:0];
 wire [7:0] hi=r>g?(r>b?r:b):(g>b?g:b);
 wire [7:0] lo=r<g?(r<b?r:b):(g<b?g:b);
 // White/gray field only, no clipped or black samples and no saturated color.
 wire neutral=hi>=48 && hi<232 && lo>=hi-(hi>>1);
 reg sample_q;
 reg [2:0] zone_q;
 reg [7:0] red_q,green_q,blue_q;
 wire reset_statistics=state==SETTLE && sof && settle==1;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin sample_q<=0;zone_q<=0;red_q<=0;green_q<=0;blue_q<=0;end
  else begin
   sample_q<=state==CAPTURE && sample && neutral && !clear_wait;
   zone_q<=sample_zone;red_q<=r;green_q<=g;blue_q<=b;
  end
 end
 wire [SUMW-1:0] added_r=reds[zone_q]+red_q;
 wire [SUMW-1:0] added_g=greens[zone_q]+green_q;
 wire [SUMW-1:0] added_b=blues[zone_q]+blue_q;
 wire [COUNTW-1:0] added_count=counts[zone_q]+1'b1;
 wire [4:0] good;
 wire [15:0] report_count[0:2],report_r[0:2],report_b[0:2];
 genvar bank;
 generate for(bank=0;bank<5;bank=bank+1)begin:reference_banks
  assign good[bank]=counts[bank]>=MINIMUM && reds[bank]!=0 && blues[bank]!=0;
  always @(posedge clk or negedge rst_n)begin
   if(!rst_n)begin reds[bank]<=0;greens[bank]<=0;blues[bank]<=0;counts[bank]<=0;end
   else if(reset_statistics)begin reds[bank]<=0;greens[bank]<=0;blues[bank]<=0;counts[bank]<=0;end
   else if(sample_q && zone_q==bank && state==CAPTURE)begin
    reds[bank]<=added_r;greens[bank]<=added_g;
    blues[bank]<=added_b;counts[bank]<=added_count;
   end
  end
 end endgenerate
 generate for(bank=0;bank<3;bank=bank+1)begin:diagnostic_padding
  assign report_count[bank]=counts[bank];
  assign report_r[bank]=knots_r[bank];assign report_b[bank]=knots_b[bank];
 end endgenerate
 wire all_good=&good;
 assign ratio_request=state==REQUEST && !clear_wait;
 assign sum_r=reds[zone];assign sum_g=greens[zone];assign sum_b=blues[zone];
 wire commit=sof && publish && !clear_wait;
 wire effective_valid=clear_wait && sof?1'b0:table_valid || commit;
 assign enabled=effective_valid;
 wire [15:0] left_r=commit?pending_r[0]:knots_r[0],left_b=commit?pending_b[0]:knots_b[0];
 wire [15:0] mid_r=commit?pending_r[1]:knots_r[1],mid_b=commit?pending_b[1]:knots_b[1];
 wire [15:0] right_r=commit?pending_r[2]:knots_r[2],right_b=commit?pending_b[2]:knots_b[2];
 // Signed DDA: coefficient fractional precision STEP; add once per valid
 // four-pixel beat. No pixel-rate interpolation multiplier or divider.
 reg signed [27:0] interp_r,interp_b;
 reg signed [18:0] delta1r,delta2r,delta1b,delta2b;
 wire signed [18:0] diff1r=($signed({1'b0,mid_r})-$signed({1'b0,left_r}))*4;
 wire signed [18:0] diff2r=($signed({1'b0,right_r})-$signed({1'b0,mid_r}))*4;
 wire signed [18:0] diff1b=($signed({1'b0,mid_b})-$signed({1'b0,left_b}))*4;
 wire signed [18:0] diff2b=($signed({1'b0,right_b})-$signed({1'b0,mid_b}))*4;
 wire [15:0] horizontal_r=px<=K0?left_r:px>=K2?right_r:px==K1?mid_r:(interp_r>>>LOGSTEP);
 wire [15:0] horizontal_b=px<=K0?left_b:px>=K2?right_b:px==K1?mid_b:(interp_b>>>LOGSTEP);
 wire [15:0] top_r=commit?pending_r[3]:knots_r[3],top_b=commit?pending_b[3]:knots_b[3];
 wire [15:0] bottom_r=commit?pending_r[4]:knots_r[4],bottom_b=commit?pending_b[4]:knots_b[4];
 wire signed [16:0] top_dr=$signed({1'b0,top_r})-$signed({1'b0,mid_r});
 wire signed [16:0] top_db=$signed({1'b0,top_b})-$signed({1'b0,mid_b});
 wire signed [16:0] bottom_dr=$signed({1'b0,bottom_r})-$signed({1'b0,mid_r});
 wire signed [16:0] bottom_db=$signed({1'b0,bottom_b})-$signed({1'b0,mid_b});
 reg signed [GAINW+YLOG+2:0] vertical_r,vertical_b;
 reg signed [16:0] vstep1r,vstep2r,vstep1b,vstep2b;
 wire signed [17:0] offset_r=py<=T0?top_dr:py>=T2?bottom_dr:py==T1?18'sd0:(vertical_r>>>YLOG);
 wire signed [17:0] offset_b=py<=T0?top_db:py>=T2?bottom_db:py==T1?18'sd0:(vertical_b>>>YLOG);
 function [15:0] bounded_gain;
  input [15:0] horizontal;
  input signed [17:0] vertical;
  reg signed [18:0] total;
  begin
   total=$signed({1'b0,horizontal})+vertical;
   bounded_gain = total < 19'sd2048 ? 16'd2048 : total > 19'sd10240 ? 16'd10240 : total[15:0];
  end
 endfunction
 assign pixel_r=bounded_gain(horizontal_r,offset_r);
 assign pixel_b=bounded_gain(horizontal_b,offset_b);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin vertical_r<=0;vertical_b<=0;vstep1r<=0;vstep2r<=0;vstep1b<=0;vstep2b<=0;end
  else begin
   if(sof)begin
    vertical_r<=top_dr*YSTEP;vertical_b<=top_db*YSTEP;
    vstep1r<=-top_dr;vstep1b<=-top_db;vstep2r<=bottom_dr;vstep2b<=bottom_db;
   end
   if(take && px==WIDTH-4)begin
    if(py<T0)begin vertical_r<=top_dr*YSTEP;vertical_b<=top_db*YSTEP;end
    else if(py==T1)begin vertical_r<=vstep2r;vertical_b<=vstep2b;end
    else if(py<T1)begin vertical_r<=vertical_r+vstep1r;vertical_b<=vertical_b+vstep1b;end
    else if(py<T2)begin vertical_r<=vertical_r+vstep2r;vertical_b<=vertical_b+vstep2b;end
   end
  end
 end
 wire [2:0] report_state=state==SETTLE || state==CAPTURE?3'd1:
     state==CHECK || state==REQUEST || state==WAIT_RATIO || state==READY?3'd2:
     failed?3'd5:table_valid?3'd3:3'd0;
 assign diagnostics=report_state==0?160'd0:{generation,report_count[2],report_count[1],report_count[0],
       report_b[2],report_r[2],report_b[1],report_r[1],report_b[0],report_r[0],5'd0,report_state};
 integer i;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;x<=0;y<=0;words<=0;in_frame<=0;frames<=0;settle<=0;zone<=0;
   table_valid<=0;publish<=0;failed<=0;generation<=0;clear_wait<=0;
   interp_r<=4096*STEP;interp_b<=4096*STEP;delta1r<=0;delta2r<=0;delta1b<=0;delta2b<=0;
   for(i=0;i<5;i=i+1)begin
    knots_r[i]<=4096;knots_b[i]<=4096;pending_r[i]<=4096;pending_b[i]<=4096;
   end
  end else begin
   if(sof)begin
    x<=0;y<=0;words<=0;in_frame<=1;
    interp_r<=left_r*STEP;interp_b<=left_b*STEP;
    delta1r<=diff1r;delta2r<=diff2r;delta1b<=diff1b;delta2b<=diff2b;
    if(commit)begin
     for(i=0;i<5;i=i+1)begin knots_r[i]<=pending_r[i];knots_b[i]<=pending_b[i];end
     table_valid<=1;publish<=0;state<=IDLE;failed<=0;generation<=generation+1'b1;
    end
    if(clear_wait)begin
     state<=IDLE;table_valid<=0;publish<=0;failed<=0;clear_wait<=0;
    end
   end
   if(take)begin
    words<=finish?0:(sof?0:words)+1'b1;
    x<=px==WIDTH-4?0:px+4;y<=px==WIDTH-4?py+1'b1:py;
    if(finish)in_frame<=0;
    if(px<K0 || px==WIDTH-4)begin interp_r<=left_r*STEP;interp_b<=left_b*STEP;end
    else if(px==K1)begin
     interp_r<=$signed({1'b0,mid_r,{LOGSTEP{1'b0}}})+$signed(delta2r);
     interp_b<=$signed({1'b0,mid_b,{LOGSTEP{1'b0}}})+$signed(delta2b);
    end
    else if(px<K1)begin interp_r<=interp_r+delta1r;interp_b<=interp_b+delta1b;end
    else if(px<K2)begin interp_r<=interp_r+delta2r;interp_b<=interp_b+delta2b;end
   end
   case(state)
    SETTLE:if(sof)begin
      if(settle==1)begin
       frames<=0;state<=CAPTURE;
      end else settle<=settle+1'b1;
    end
    CAPTURE:begin
      if(sof && in_frame)begin state<=IDLE;failed<=1;end
      else if(finish)begin
       if(frames==CAL_FRAMES-1)begin state<=CHECK;zone<=0;end else frames<=frames+1'b1;
      end
    end
    CHECK:if(all_good)state<=REQUEST;else begin failed<=1;state<=IDLE;end
    REQUEST:if(ratio_accept)state<=WAIT_RATIO;
    WAIT_RATIO:if(ratio_done)begin
      if(ratio_r<2048 || ratio_r>10240 || ratio_b<2048 || ratio_b>10240)begin failed<=1;state<=IDLE;end
      else begin
       pending_r[zone]<=ratio_r;pending_b[zone]<=ratio_b;
       if(zone==4)begin publish<=1;state<=READY;end else begin zone<=zone+1'b1;state<=REQUEST;end
      end
    end
    default:begin end
   endcase
   // UI pulses are synchronized to this pixel clock. A new request never
   // mutates the active table; unsuccessful recalibration preserves it.
   if(calibrate && state==IDLE && !clear_wait)begin state<=SETTLE;settle<=0;failed<=0;end
   if(clear)begin clear_wait<=1;state<=IDLE;publish<=0;end
  end
 end
endmodule
