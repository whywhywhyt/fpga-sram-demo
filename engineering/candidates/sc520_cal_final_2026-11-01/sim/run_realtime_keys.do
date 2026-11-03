onerror {quit -code 1 -f}
if {![file isdirectory work_realtime]} {vlib work_realtime}
set h ../candidate/sc520_shapes/user_source/hdl_source
vlog -work work_realtime -sv $h/mode_button_control.v $h/osd_font5x7.v $h/wall_light_painter.v tb_realtime_keys.sv tb_wall_home.sv
vsim -onfinish stop -voptargs=+acc work_realtime.tb_realtime_keys
run -all
if {[examine -radix unsigned /tb_realtime_keys/completed] != 1} {quit -code 1 -f}
quit -sim
vsim -onfinish stop -voptargs=+acc work_realtime.tb_realtime_50m
run -all
if {[examine -radix unsigned /tb_realtime_50m/completed] != 1} {quit -code 1 -f}
quit -code 0 -f
