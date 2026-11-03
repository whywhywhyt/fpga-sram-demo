onerror {quit -code 1 -f}
vlib work_caption_font
set h ../candidate/sc520_shapes/user_source/hdl_source
vlog -work work_caption_font -sv $h/osd_font5x7.v tb_caption_font.sv
vsim -c -onfinish stop work_caption_font.tb_caption_font
run -all
if {[examine -radix unsigned /tb_caption_font/completed] != 1} {quit -code 1 -f}
quit -code 0 -f
