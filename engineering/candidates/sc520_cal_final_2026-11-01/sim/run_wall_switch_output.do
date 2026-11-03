onerror {quit -code 1 -f}
if {![file isdirectory work_switch_output]} {vlib work_switch_output}
set h ../candidate/sc520_shapes/user_source/hdl_source
vlog -work work_switch_output -sv $h/osd_font5x7.v $h/wall_paint_precision.v $h/wall_light_painter.v $h/interactive_lightwall.v tb_wall_switch_output.sv tb_wall_switch_live.sv
vsim -onfinish stop -voptargs=+acc work_switch_output.tb_wall_switch_output
run -all
if {[examine -radix unsigned /tb_wall_switch_output/completed] != 1} {quit -code 1 -f}
quit -sim
vsim -onfinish stop -voptargs=+acc work_switch_output.tb_wall_switch_live
run -all
if {[examine -radix unsigned /tb_wall_switch_live/completed] != 1} {quit -code 1 -f}
quit -code 0 -f
