onerror {quit -code 1 -f}
if {![file isdirectory work_motion_controls]} {vlib work_motion_controls}
set h ../candidate/sc520_shapes/user_source/hdl_source
vlog -work work_motion_controls -sv $h/mode_button_control.v $h/frame_status_96.v $h/osd_font5x7.v tb_motion_controls.sv
vsim -onfinish stop -voptargs=+acc work_motion_controls.tb_motion_controls
run -all
if {[examine -radix unsigned /tb_motion_controls/completed] != 1} {quit -code 1 -f}
quit -code 0 -f
