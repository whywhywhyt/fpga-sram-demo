`timescale 1ns/1ps
module tb_awb_unit;
reg clk=0,rst=0,user=0,valid=0,last=0;
reg [95:0] data=0;
wire ready,ov,ol,ou;
wire [95:0] od;
awb #(.IMG_WIDTH(32),.IMG_HEIGHT(8)) dut(.I_clk(clk),.I_rst_n(rst),.I_tlast(last),.I_tuser(user),
 .I_tdata(data),.I_tvalid(valid),.I_tready(ready),.O_tlast(ol),.O_tuser(ou),.O_tdata(od),.O_tvalid(ov),.O_tready(1'b1));
always #5 clk=~clk;
integer errors=0,fd,rc,cycle=0,ri,ui,vi,li,evi,eli,eui;
reg [95:0] di,edi;reg[15:0] er,eb;
initial begin
 fd=$fopen("awb_unit_vectors.txt","r");if(!fd)$fatal(1,"Missing vectors");
 while(!$feof(fd))begin
  rc=$fscanf(fd,"%d %d %d %d %h %d %d %d %h %h %h\n",ri,ui,vi,li,di,evi,eli,eui,edi,er,eb);
  if(rc==11)begin
   @(negedge clk);rst=ri;user=ui;valid=vi;last=li;data=di;
   @(posedge clk);#1;
   if(ov!==evi[0] || ol!==eli[0] || ou!==eui[0] || od!==edi || dut.gain_r!==er || dut.gain_b!==eb || ready!==1'b1)begin
    if(errors<10)$display("AWB mismatch cycle=%0d valid=%b/%b last=%b/%b user=%b/%b data=%h/%h gain=%h,%h/%h,%h",cycle,ov,evi[0],ol,eli[0],ou,eui[0],od,edi,dut.gain_r,dut.gain_b,er,eb);
    errors=errors+1;
   end
   cycle=cycle+1;
  end
 end
 $fclose(fd);
 if(errors)$fatal(1,"AWB unit FAIL %0d",errors);
 $display("PASS: actual AWB frame statistics, atomic gains, 64-cycle alignment, all lanes, bubbles, incomplete frames and reset; %0d cycles",cycle);
 $finish;
end
endmodule

module tb_awb_ratio;
reg clk=0,rst=0,start=0;
reg [27:0] g=0,r=0,b=0;
wire busy,done;wire[15:0] gr,gb;
awb_serial_ratio dut(.clk(clk),.rst_n(rst),.start(start),.sum_g(g),.sum_r(r),.sum_b(b),
 .busy(busy),.done(done),.gain_r(gr),.gain_b(gb));
always #5 clk=~clk;
integer errors=0,fd,rc,count=0,waits;
reg[27:0] gi,ri,bi;reg[15:0] er,eb;
initial begin
 repeat(3)@(negedge clk);rst=1;
 fd=$fopen("ratio_vectors.txt","r");if(!fd)$fatal(1,"Missing divider vectors");
 while(!$feof(fd))begin
  rc=$fscanf(fd,"%h %h %h %h %h\n",gi,ri,bi,er,eb);
  if(rc==5)begin
   @(negedge clk);g=gi;r=ri;b=bi;start=1;
   @(negedge clk);start=0;waits=0;
   while(!done && waits<90)begin @(negedge clk);waits=waits+1;end
   if(!done || gr!==er || gb!==eb || waits!=80)begin
    if(errors<6)$display("Ratio mismatch %0d: %h,%h expected %h,%h latency %0d",count,gr,gb,er,eb,waits);
    errors=errors+1;
   end
   count=count+1;
  end
 end
 $fclose(fd);
 if(errors || count!=512)$fatal(1,"Ratio FAIL %0d cases %0d",errors,count);
 $display("PASS: shared divider 512 independent integer reference cases, zero denominators, clipping and 80-cycle result");
 $finish;
end
endmodule
