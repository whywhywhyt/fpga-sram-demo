onerror {quit -code 1 -f}
if {![file isdirectory work_atomic]} {vlib work_atomic}
set h ../candidate/sc520_shapes/user_source/hdl_source
vlog -work work_atomic -sv $h/motion_detect_96.v tb_motion_regions.sv
vsim -onfinish stop -voptargs=+acc -gAUTO=1 work_atomic.tb_motion_regions
run -all
if {[examine -radix unsigned /tb_motion_regions/completed] != 1} {quit -code 1 -f}
quit -code 0 -f
