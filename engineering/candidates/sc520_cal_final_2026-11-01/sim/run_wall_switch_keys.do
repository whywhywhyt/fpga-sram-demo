onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file isdirectory work_switch_keys]} {vlib work_switch_keys}
set h ../candidate/sc520_shapes/user_source/hdl_source
vlog -work work_switch_keys -sv $h/mode_button_control.v $h/osd_font5x7.v $h/wall_light_painter.v $h/wall_paint_precision.v tb_wall_switch_keys.sv
vsim -voptargs=+acc work_switch_keys.tb_wall_switch_keys
run -all
quit -code 0 -f
