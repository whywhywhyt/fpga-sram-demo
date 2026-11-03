onerror {quit -code 1 -f}
if {![file isdirectory work_motion_extent]} {vlib work_motion_extent}
set h ../candidate/sc520_shapes/user_source/hdl_source
vlog -work work_motion_extent -sv $h/motion_detect_96.v tb_motion_extent.sv
vsim -onfinish stop -voptargs=+acc work_motion_extent.tb_motion_extent
run -all
if {[examine -radix unsigned /tb_motion_extent/completed] != 1} {quit -code 1 -f}
quit -code 0 -f
