`timescale 1ns/1ps
module tb_shape_stability;
  localparam integer W=64,H=48,N=W*H;
  reg clk=0;always #5 clk=~clk;
  reg rst_n=0,start=0,history_enable=0;
  reg [255:0] history_boxes=0;
  wire busy,done,overflow,mem_we;
  wire [15:0] mem_addr;
  reg [2:0] mem_data;
  wire [2:0] mem_wdata;
  wire [255:0] boxes;
  wire [2:0] shown;
  wire [7:0] total;
  reg [2:0] map[0:N-1];
  integer i,x,y,cycles;
  reg [63:0] first_box;
  reg [255:0] saved_boxes;
  reg [1:0] expected_shape=3,expected_color=1;

  shape_ccl #(.GRID_W(W),.GRID_H(H),.QLOG(12),.MIN_CELLS(64),.MIN_SIDE(8),.STABILIZE(1)) dut(
    .clk(clk),.rst_n(rst_n),.start(start),.history_enable(history_enable),.history_boxes(history_boxes),
    .busy(busy),.done(done),.overflow(overflow),.mem_addr(mem_addr),.mem_data(mem_data),
    .mem_we(mem_we),.mem_wdata(mem_wdata),.boxes(boxes),.shown(shown),.total(total));
  always @(posedge clk)begin mem_data<=map[mem_addr];if(mem_we)map[mem_addr]<=mem_wdata;end

  task clear_map;
    begin for(i=0;i<N;i=i+1)map[i]=0;end
  endtask
  task fill_rectangle;
    input integer x0,y0,x1,y1;
    begin for(y=y0;y<=y1;y=y+1)for(x=x0;x<=x1;x=x+1)map[y*W+x]=3'd1;end
  endtask
  task process_map;
    begin
      @(negedge clk);start=1;@(negedge clk);start=0;cycles=0;
      while(!done && cycles<500000)begin @(posedge clk);cycles=cycles+1;end
      if(!done)$fatal(1,"shape stability timeout");
      if(overflow || shown!=1 || boxes[63:48]==0 || boxes[47:46]!=expected_shape || boxes[45:44]!=expected_color)
        $fatal(1,"bad rectangle classification: overflow=%b shown=%0d shape=%0d color=%0d",overflow,shown,boxes[47:46],boxes[45:44]);
      @(negedge clk);
    end
  endtask

  initial begin
    clear_map();repeat(4)@(posedge clk);rst_n=1;
    fill_rectangle(18,12,35,27);process_map();
    first_box=boxes[63:0];saved_boxes=boxes;

    clear_map();fill_rectangle(19,13,36,28);
    history_enable=1;history_boxes=saved_boxes;process_map();
    if(boxes[43:0]!==first_box[43:0])$fatal(1,"one-cell camera/sample jitter moved the accepted box");

    clear_map();fill_rectangle(20,14,37,29);
    history_boxes=saved_boxes;process_map();
    if(boxes[43:0]!==first_box[43:0])$fatal(1,"two-cell boundary jitter moved the accepted box");

    clear_map();fill_rectangle(22,16,39,31);
    history_boxes=boxes;process_map();
    if(boxes[10:2] < first_box[10:2]+9'd1 || boxes[10:2] > first_box[10:2]+9'd3)
      $fatal(1,"real motion did not follow with a stable half-step: old=%0d new=%0d",first_box[10:2],boxes[10:2]);

    // An adjacent rectangle of a different color must not inherit geometry.
    clear_map();fill_rectangle(19,13,36,28);
    for(y=13;y<=28;y=y+1)for(x=19;x<=36;x=x+1)map[y*W+x]=3'd2;
    history_boxes=saved_boxes;expected_color=2;process_map();
    if(boxes[10:0]!=76)$fatal(1,"different-color object inherited prior coordinates");

    // The same color with a different previous shape must not be associated.
    clear_map();fill_rectangle(19,13,36,28);expected_color=1;
    history_boxes=saved_boxes;history_boxes[47:46]=1;process_map();
    if(boxes[10:0]!=76)$fatal(1,"different-shape object inherited prior coordinates");

    // Independent clean shapes plus isolated same-color noise.
    history_enable=0;clear_map();expected_shape=1;expected_color=0;
    for(y=14;y<=34;y=y+1)for(x=22;x<=42;x=x+1)
      if((x-32)*(x-32)+(y-24)*(y-24)<=25)map[y*W+x]=3'd4;
    map[3*W+3]=4;map[40*W+58]=4;
    process_map();
    if(total!=1)$fatal(1,"speckle counted as an object");
    saved_boxes=boxes;

    clear_map();expected_shape=2;expected_color=2;
    for(y=12;y<=35;y=y+1)for(x=20;x<=44;x=x+1)
      if((x>=32-(y-12)/2) && (x<=32+(y-12)/2))map[y*W+x]=3'd2;
    process_map();

    // A blank frame must clear old boxes, not manufacture a ghost target.
    clear_map();history_enable=1;history_boxes=saved_boxes;
    @(negedge clk);start=1;@(negedge clk);start=0;cycles=0;
    while(!done && cycles<500000)begin @(posedge clk);cycles=cycles+1;end
    if(!done || overflow || shown!=0 || total!=0 || boxes!==256'd0)$fatal(1,"blank frame retained stale object");
    $display("PASS box stability: jitter held, motion followed, color association isolated; circle/triangle/rectangle, speckles and target removal correct");
    $finish;
  end
endmodule
