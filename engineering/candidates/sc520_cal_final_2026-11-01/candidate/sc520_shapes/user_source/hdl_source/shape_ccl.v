// Exact 4-neighbor, same-color flood fill on a complete immutable color map.
// A consumed map pixel is cleared BEFORE it can be enqueued twice.
// RAM interfaces are synchronous reads with one clock of latency.
// Queue exhaustion invalidates the entire result; it never fabricates a box.
// boxes is the work/result bank, valid at done. The caller publishes atomically
// and supplies its last published bank as history_boxes, avoiding a third copy.
module shape_ccl #(
    parameter integer GRID_W=320,GRID_H=180,QLOG=12,
    parameter integer MIN_CELLS=64,MIN_SIDE=8,STABILIZE=0
)(
    input wire clk,rst_n,start,history_enable,
    input wire [255:0] history_boxes,
    output reg busy,done,overflow,
    output reg [15:0] mem_addr,
    input wire [2:0] mem_data,
    output reg mem_we,
    output wire [2:0] mem_wdata,
    output reg [255:0] boxes,
    output reg [2:0] shown,
    output reg [7:0] total
);
    localparam IDLE=0,SCAN_REQ=1,SCAN_GET=2,POP_REQ=3,POP_GET=4,
        NEI_REQ=5,NEI_GET=6,POP_CHECK=7,SIZE=8,
        MA=9,WA=10,
        CLASSIFY=19,MIN_SCAN=20,SELECT=22,KEEP=23,
        NEXT_SCAN=24,FINISH=25,ABORT=26,MATCH=27,SMOOTH=28,HIST_PICK=29,HIST_NEXT=30;
    // Bounds use the whole map, not a typical object. 64-bit constants avoid
    // elaboration overflow before $clog2. The 320x180 map needs 49 product bits.
    localparam integer CELLS=GRID_W*GRID_H;
    localparam integer SX_W=$clog2(64'd1*CELLS*(GRID_W-1)+1);
    localparam integer SY_W=$clog2(64'd1*CELLS*(GRID_H-1)+1);
    localparam integer R2_W=$clog2(64'd1*CELLS*((GRID_W-1)*(GRID_W-1)+(GRID_H-1)*(GRID_H-1))+1);
    localparam integer MOM_W=$clog2(64'd1*CELLS*CELLS*((GRID_W-1)*(GRID_W-1)+(GRID_H-1)*(GRID_H-1))+1);
    localparam integer CUBE_W=$clog2(64'd1*CELLS*CELLS*CELLS+1);
    localparam integer MUL_W=MOM_W>CUBE_W?MOM_W:CUBE_W;
    localparam integer COMP_W=MUL_W+7;
    localparam integer EX_W=SX_W+1,EY_W=SY_W+1;
    reg [4:0] state;
    reg [15:0] scan_addr;
    reg [8:0] scan_x,cur_x,nx,min_x,max_x;
    reg [7:0] scan_y,cur_y,ny,min_y,max_y;
    reg [1:0] direction,shape;
    reg [2:0] color;
    reg neighbor_ok;
    reg [15:0] area,bbox_area;
    reg [8:0] bw;
    reg [7:0] bh;
    reg [SX_W-1:0] sx;
    reg [SY_W-1:0] sy;
    reg [R2_W-1:0] sr2;
    reg [MUL_W-1:0] norm;
    wire [CUBE_W-1:0] cube;
    reg [EX_W-1:0] expected_x,scale_x;
    reg [EY_W-1:0] expected_y,scale_y;
    // A sign-extended subtraction plus absolute value shares the comparison
    // and difference instead of building two subtractors and a comparator.
    wire [EX_W:0] signed_dx={1'b0,sx,1'b0}-{1'b0,expected_x};
    wire [EY_W:0] signed_dy={1'b0,sy,1'b0}-{1'b0,expected_y};
    wire [EX_W-1:0] dx=signed_dx[EX_W]?-signed_dx[EX_W-1:0]:signed_dx[EX_W-1:0];
    wire [EY_W-1:0] dy=signed_dy[EY_W]?-signed_dy[EY_W-1:0]:signed_dy[EY_W-1:0];
    wire centered=dx<=(scale_x>>3) && dy<=(scale_y>>3);
    wire [COMP_W-1:0] n128={norm,7'd0};
    wire [COMP_W-1:0] cube_ext=cube;
    wire [COMP_W-1:0] cube23=(cube_ext<<4)+(cube_ext<<3)-cube_ext;
    wire [COMP_W-1:0] n128_plus_2cube=n128+(cube_ext<<1);
    // Four small constant products can use the saved DSP budget, reducing
    // the larger LUT/carry cost of parallel shift/add threshold networks.
    wire [20:0] box7=bbox_area*5'd7;
    wire [20:0] box3=bbox_area*3'd3;
    wire [20:0] box21=bbox_area*5'd21;
    wire [20:0] box6=bbox_area*5'd6;
    wire [20:0] box11=bbox_area*5'd11;
    wire [21:0] circle_fill_lhs={1'b0,area,5'd0}+{5'd0,bbox_area,1'b0};
    wire [21:0] circle_fill_rhs={1'b0,box21};
    wire [10:0] width3={1'b0,bw,1'b0}+{2'd0,bw};
    wire [10:0] height3={2'd0,bh,1'b0}+{3'd0,bh};
    reg m_start;
    reg [2:0] multiply_phase;
    reg [MUL_W-1:0] m_a;
    reg [R2_W-1:0] m_b;
    wire m_busy,m_done;
    wire [MUL_W-1:0] m_result;
    // At CLASSIFY the last operand is area squared and the held result is
    // area cubed. They need no separate copies outside this valid state.
    wire [31:0] area2=m_a;
    assign cube=m_result;
    shape_mul64 #(.PRODUCT_W(MUL_W),.B_W(R2_W)) multiply(.clk(clk),.rst_n(rst_n),.start(m_start),.a(m_a),.b(m_b),
        .busy(m_busy),.done(m_done),.result(m_result));
    reg [16:0] queue[0:(1<<QLOG)-1];
    reg [QLOG-1:0] wp,rp;
    reg [QLOG:0] queued;
    reg [16:0] queue_q;
    wire queue_full=queued==(1<<QLOG);
    wire seed_push=state==SCAN_GET && mem_data!=0;
    wire nei_push=state==NEI_GET && mem_data==color && !queue_full;
    wire [8:0] moment_x=state==SCAN_GET?scan_x:nx;
    wire [7:0] moment_y=state==SCAN_GET?scan_y:ny;
    wire [17:0] x_squared=moment_x*moment_x;
    wire [15:0] y_squared=moment_y*moment_y;
    wire [18:0] sample_r2={1'b0,x_squared}+{3'd0,y_squared};
    function [15:0] row_offset;
        input [7:0] y;
        integer bit_index;
        begin
            row_offset=0;
            for(bit_index=0;bit_index<10;bit_index=bit_index+1)
                if((GRID_W>>bit_index)&1)row_offset=row_offset+({8'd0,y}<<bit_index);
        end
    endfunction
    always @(posedge clk)begin
        queue_q<=queue[rp];
        if(seed_push)queue[wp]<={scan_y,scan_x};
        else if(nei_push)queue[wp]<={ny,nx};
    end
    assign mem_wdata=0;
    // Only one memory read/check is in flight, so clearing a pixel before
    // the next request makes visited state unambiguous even for cycles/holes.
    always @(*)begin
        nx=cur_x;ny=cur_y;neighbor_ok=1;
        case(direction)
            0:begin nx=cur_x-1'b1;neighbor_ok=cur_x!=0;end
            1:begin nx=cur_x+1'b1;neighbor_ok=cur_x<GRID_W-1;end
            2:begin ny=cur_y-1'b1;neighbor_ok=cur_y!=0;end
            3:begin ny=cur_y+1'b1;neighbor_ok=cur_y<GRID_H-1;end
        endcase
        mem_addr=scan_addr;
        if(state==NEI_REQ || state==NEI_GET)mem_addr=row_offset(ny)+nx;
        mem_we=seed_push || nei_push;
    end
    // Scan the four weights using one comparator and the existing probe.
    // Strict comparison keeps the first slot on equal weights, as before.
    reg [1:0] selected_slot;
    reg selected_valid;
    reg [63:0] selected_box;
    reg [15:0] selected_weight;
    reg [7:0] work_total;
    // Associate with one previous same-color box at a time. Reuse the public
    // previous boxes; no second frame/map buffer is introduced. Coordinates
    // are filtered only after association, never while following fast motion.
    reg history_active;
    reg [3:0] probe,used_history;
    reg [5:0] distance_sum,best_distance;
    reg reject_match,match_found;
    reg [1:0] matched_slot;
    wire [1:0] history_slot=state==SMOOTH?matched_slot:probe[3:2];
    wire [63:0] previous_box=history_boxes[history_slot*64 +:64];
    wire [10:0] new_coord=state==SMOOTH?selected_box[10:0]:selected_box[probe[1:0]*11 +:11];
    wire [10:0] old_coord=previous_box[probe[1:0]*11 +:11];
    wire [9:0] signed_delta={1'b0,new_coord[10:2]}-{1'b0,old_coord[10:2]};
    wire [8:0] delta_coord=signed_delta[9]?-signed_delta[8:0]:signed_delta[8:0];
    wire [15:0] probe_weight=boxes[probe[1:0]*64+48 +:16];
    wire [5:0] distance_next=distance_sum+{2'd0,delta_coord[3:0]};
    wire accept_match=!reject_match && delta_coord<=8 && previous_box[63:48]!=0 &&
        previous_box[45:44]==selected_box[45:44] &&
        previous_box[47:46]==selected_box[47:46] && !used_history[probe[3:2]] && distance_next<best_distance;
    wire [10:0] held_coord=old_coord;
    wire [9:0] midpoint={1'b0,new_coord[10:2]}+{1'b0,held_coord[10:2]};
    wire [10:0] smooth_coord=delta_coord<=2?held_coord:{midpoint[9:1],{2{probe[0]}}};
    // Preserve the original 4x4 measurement lattice at the bank boundary.
    // Invented sub-tile precision would widen every downstream overlay adder.
    wire [63:0] aligned_selected={selected_box[63:44],
        1'b0,selected_box[42:35],2'b11,1'b0,selected_box[31:24],2'b00,
        selected_box[21:13],2'b11,selected_box[10:2],2'b00};
    integer i;
    wire [63:0] candidate={area,shape,color[1:0],{1'b0,max_y,2'b11},{1'b0,min_y,2'b00},
        {max_x,2'b11},{min_x,2'b00}};
    wire [8:0] box_width=max_x-min_x+9'd1;
    wire [7:0] box_height=max_y-min_y+8'd1;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;busy<=0;done<=0;overflow<=0;boxes<=0;shown<=0;total<=0;
            scan_addr<=0;scan_x<=0;scan_y<=0;cur_x<=0;cur_y<=0;direction<=0;color<=0;shape<=0;
            min_x<=0;max_x<=0;min_y<=0;max_y<=0;area<=0;bw<=0;bh<=0;bbox_area<=0;
            sx<=0;sy<=0;sr2<=0;norm<=0;
            expected_x<=0;expected_y<=0;scale_x<=0;scale_y<=0;
            wp<=0;rp<=0;queued<=0;work_total<=0;m_start<=0;m_a<=0;m_b<=0;multiply_phase<=0;
            selected_slot<=0;selected_valid<=0;selected_box<=0;selected_weight<=0;
            history_active<=0;probe<=0;used_history<=0;distance_sum<=0;best_distance<=63;
            reject_match<=0;match_found<=0;matched_slot<=0;
        end else begin
            done<=0;m_start<=0;
            case(state)
                IDLE:if(start)begin
                    busy<=1;overflow<=0;state<=SCAN_REQ;scan_addr<=0;scan_x<=0;scan_y<=0;
                    wp<=0;rp<=0;queued<=0;work_total<=0;
                    history_active<=STABILIZE && history_enable;used_history<=0;
                    boxes<=0;
                end
                SCAN_REQ:state<=SCAN_GET;
                SCAN_GET:begin
                    if(mem_data==0)state<=NEXT_SCAN;
                    else begin
                        color<=mem_data;area<=1;min_x<=scan_x;max_x<=scan_x;min_y<=scan_y;max_y<=scan_y;
                        sx<=scan_x;sy<=scan_y;sr2<=sample_r2;
                        wp<=wp+1'b1;queued<=1;state<=POP_REQ;
                    end
                end
                POP_REQ:state<=POP_GET;
                POP_GET:begin
                    cur_x<=queue_q[8:0];cur_y<=queue_q[16:9];rp<=rp+1'b1;queued<=queued-1'b1;
                    direction<=0;state<=NEI_REQ;
                end
                NEI_REQ:begin
                    if(neighbor_ok)state<=NEI_GET;
                    else if(direction==3)state<=POP_CHECK;
                    else direction<=direction+1'b1;
                end
                NEI_GET:begin
                    if(mem_data==color)begin
                        if(queue_full)state<=ABORT;
                        else begin
                            wp<=wp+1'b1;queued<=queued+1'b1;area<=area+1'b1;
                            if(nx<min_x)min_x<=nx;if(nx>max_x)max_x<=nx;
                            if(ny<min_y)min_y<=ny;if(ny>max_y)max_y<=ny;
                            sx<=sx+nx;sy<=sy+ny;sr2<=sr2+sample_r2;
                            if(direction==3)state<=POP_CHECK;
                            else begin direction<=direction+1'b1;state<=NEI_REQ;end
                        end
                    end else if(direction==3)state<=POP_CHECK;
                    else begin direction<=direction+1'b1;state<=NEI_REQ;end
                end
                POP_CHECK:state<=queued==0?SIZE:POP_REQ;
                SIZE:begin
                    if(area<MIN_CELLS || max_x-min_x<MIN_SIDE-1 || max_y-min_y<MIN_SIDE-1)state<=NEXT_SCAN;
                    else begin
                        bw<=box_width;bh<=box_height;
                        // These small products cost less logic as DSPs than
                        // routing ten operand choices into the serial unit.
                        bbox_area<=box_width*box_height;
                        expected_x<=area*({1'b0,min_x}+{1'b0,max_x});
                        expected_y<=area*({1'b0,min_y}+{1'b0,max_y});
                        scale_x<=area*box_width;scale_y<=area*box_height;
                        multiply_phase<=0;state<=MA;
                    end
                end
                MA:begin
                    // Wide moment/area-cube products share one serial unit.
                    m_b<=area;
                    case(multiply_phase)
                        0:begin m_a<=area;m_b<=sr2;end
                        1:begin m_a<=sx;m_b<=sx;end
                        2:begin m_a<=sy;m_b<=sy;end
                        3:m_a<=area;
                    endcase
                    m_start<=1;state<=WA;
                end
                WA:if(m_done)begin
                    case(multiply_phase)
                        0:norm<=m_result;
                        1,2:norm<=norm-m_result;
                        3:m_a<=m_result;
                    endcase
                    if(multiply_phase==4)state<=CLASSIFY;
                    else begin multiply_phase<=multiply_phase+1'b1;state<=MA;end
                end
                CLASSIFY:begin
                    shape<=0;
                    if(min_x!=0 && min_y!=0 && max_x!=GRID_W-1 && max_y!=GRID_H-1)begin
                        if({area,3'd0}>=box7 && centered)shape<=3;
                        else if({area,2'd0}>=box3 && centered && n128_plus_2cube>=cube23)shape<=3;
                        else if(circle_fill_lhs>=circle_fill_rhs
                            && width3>={2'd0,bh,1'b0} && height3>={1'b0,bw,1'b0}
                            && centered && n128<cube23)shape<=1;
                        else if({area,1'b0}>=bbox_area && centered)shape<=3;
                        else if({area,4'd0}>=box6 && {area,4'd0}<=box11
                            && !centered && n128>=cube23)shape<=2;
                        else if({area,1'b0}>=bbox_area && centered)shape<=3;
                    end
                    selected_weight<=boxes[63:48];selected_slot<=0;probe<=1;
                    state<=MIN_SCAN;
                end
                MIN_SCAN:begin
                    if(probe_weight<selected_weight)begin selected_weight<=probe_weight;selected_slot<=probe[1:0];end
                    if(probe[1:0]==3)state<=SELECT;
                    else probe<=probe+1'b1;
                end
                SELECT:begin
                    selected_valid<=area>selected_weight;
                    selected_box<=candidate;
                    state<=KEEP;
                end
                HIST_PICK:begin
                    // Associate only the final top four. An evicted candidate
                    // must not consume the history needed by a retained one.
                    selected_box<=boxes[selected_slot*64 +:64];
                    probe<=0;distance_sum<=0;best_distance<=63;reject_match<=0;match_found<=0;
                    state<=boxes[selected_slot*64+48 +:16]!=0?MATCH:HIST_NEXT;
                end
                MATCH:begin
                    if(probe[1:0]==3)begin
                        if(accept_match)begin
                            match_found<=1;matched_slot<=probe[3:2];
                            best_distance<=distance_next;
                        end
                        distance_sum<=0;reject_match<=0;
                    end else begin
                        distance_sum<=distance_next;
                        reject_match<=reject_match || delta_coord>8;
                    end
                    if(probe==15)begin probe<=0;state<=SMOOTH;end
                    else probe<=probe+1'b1;
                end
                SMOOTH:begin
                    // +/-8px changes are held; larger associated changes use
                    // a half-step. Match requires stable color and shape.
                    // Rotate the four bounds instead of a variable-position
                    // register write. Four clocks restore the original order.
                    selected_box[43:0]<={match_found?smooth_coord:new_coord,selected_box[43:11]};
                    if(probe[1:0]==3)begin
                        if(match_found)used_history[matched_slot]<=1;
                        state<=HIST_NEXT;
                    end else probe<=probe+1'b1;
                end
                HIST_NEXT:begin
                    // Empty slots remain all-zero; edge offsets belong only
                    // to real boxes and must never manufacture an empty box.
                    if(selected_box[63:48]!=0)boxes[selected_slot*64 +:64]<=aligned_selected;
                    if(selected_slot==3)state<=FINISH;
                    else begin selected_slot<=selected_slot+1'b1;state<=HIST_PICK;end
                end
                KEEP:begin
                    if(work_total!=255)work_total<=work_total+1'b1;
                    if(selected_valid)begin
                        boxes[selected_slot*64 +:64]<=aligned_selected;
                    end
                    state<=NEXT_SCAN;
                end
                NEXT_SCAN:begin
                    if(scan_addr==GRID_W*GRID_H-1)begin
                        selected_slot<=0;state<=history_active?HIST_PICK:FINISH;
                    end
                    else begin
                        scan_addr<=scan_addr+1'b1;scan_x<=scan_x==GRID_W-1?9'd0:scan_x+1'b1;
                        if(scan_x==GRID_W-1)scan_y<=scan_y+1'b1;
                        state<=SCAN_REQ;
                    end
                end
                FINISH:begin
                    total<=work_total;shown<=work_total>4?3'd4:work_total[2:0];
                    busy<=0;done<=1;state<=IDLE;
                end
                ABORT:begin overflow<=1;boxes<=0;shown<=0;total<=0;busy<=0;done<=1;state<=IDLE;end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
