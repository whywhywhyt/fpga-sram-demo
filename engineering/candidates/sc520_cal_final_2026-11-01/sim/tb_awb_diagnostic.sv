`timescale 1ns/1ps
module tb_awb_diagnostic;
 reg clk=0,rst=0,v=0,u=0,l=0;always #5 clk=~clk;
 reg [95:0] data=0;
 wire [172:0] stats;
 awb #(.IMG_WIDTH(32),.IMG_HEIGHT(8)) aw(.I_clk(clk),.I_rst_n(rst),
  .I_tlast(l),.I_tuser(u),.I_tdata(data),.I_tvalid(v),.I_tready(),
  .O_tlast(),.O_tuser(),.O_tdata(),.O_tvalid(),.O_tready(1'b1),.O_diagnostics(stats));
 reg ov=0,ou=0;reg [172:0] ds=0;
 wire [95:0] od;wire valid_o,user_o,last_o;
 frame_status_96 #(.IMG_WIDTH(1280),.IMG_HEIGHT(160)) overlay(
  .clk(clk),.rst_n(rst),.I_tlast(1'b0),.I_tuser(ou),.I_tvalid(ov),
  .I_tdata(96'h102030405060708090a0b0c0),.I_mode(3'd0),.I_threshold(8'd96),
  .I_awb_diag(ds),.O_tlast(last_o),.O_tuser(user_o),.O_tvalid(valid_o),.O_tdata(od));
 string lines[0:2];reg [172:0] reference_stats;
 integer checks=0,frame,x,y,row,col,i,code,words=0;
 initial begin
  repeat(4)@(negedge clk);rst=1;
  @(negedge clk);u=1;
  @(negedge clk);u=0;
  for(i=0;i<64;i=i+1)begin @(negedge clk);v=1;l=i%8==7;data={4{24'h608058}};end
  @(negedge clk);v=0;l=0;
  repeat(170)@(negedge clk);
  if(stats[17:0]!==18'd64 || stats[123:102]!==22'd256 ||
     stats[101:74]!==28'd24576 || stats[73:46]!==28'd32768 || stats[45:18]!==28'd22528)
    $fatal(1,"AWB diagnostic frame/statistics mismatch %h",stats);
  @(negedge clk);u=1;@(negedge clk);u=0;
  if(!stats[172] || stats[171:156]!==16'd5461 || stats[155:140]!==16'd5957 || stats[139:124]!==16'd1)
    $fatal(1,"AWB diagnostic gains/update mismatch %h",stats);
  for(frame=0;frame<2;frame=frame+1)begin
   reference_stats=frame==0?{1'b1,16'h1abc,16'h2345,16'h6789,22'h3abcde,
      28'h1234567,28'h89abcde,28'hf012345,18'h38400}:
      {1'b0,16'h1000,16'h4000,16'hfedc,22'h012345,28'hfedcba9,28'h8765432,28'h10abcde,18'h00123};
   lines[0]=$sformatf("WB R %04h B %04h A %1h U %04h   ",reference_stats[171:156],reference_stats[155:140],reference_stats[172],reference_stats[139:124]);
   lines[1]=$sformatf("N %06h F %05h              ",reference_stats[123:102],reference_stats[17:0]);
   lines[2]=$sformatf("R %07h G %07h B %07h ",reference_stats[101:74],reference_stats[73:46],reference_stats[45:18]);
   for(y=0;y<160;y=y+1)for(x=0;x<1280;x=x+4)begin
    @(negedge clk);ov=1;ou=(x==0 && y==0);ds=(x==0 && y==0)?reference_stats:~reference_stats;
    #1;
    if(overlay.diagnostic_area)begin
     row=(y-100)/16;col=(x-192)/16;code=lines[row].getc(col);
     if(code>=97 && code<=102)code=code-32;
     if(overlay.diagnostic_code!==code[7:0])$fatal(1,"diagnostic char frame%0d x%0d y%0d code%h expected%h",frame,x,y,overlay.diagnostic_code,code);
     checks=checks+1;
    end
    @(posedge clk);#1;
    if(words>0 && (!valid_o || last_o!==((words-1)%320==319)))$fatal(1,"overlay transport/last changed");
    words=words+1;
   end
  end
  @(negedge clk);ov=0;ou=0;repeat(4)@(negedge clk);
  if(checks!=11520)$fatal(1,"diagnostic raster coverage %0d",checks);
  $display("PASS AWB diagnostic: real gains/statistics/frame count, 11520 text groups, all hex digits, SOF atomic snapshot and 2-stage transport");$finish;
 end
 initial begin #3000000;$fatal(1,"diagnostic watchdog");end
endmodule
