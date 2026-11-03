onerror {quit -code 1 -f}
if {![file isdirectory work_bounds_720p]} {vlib work_bounds_720p}
vlog -work work_bounds_720p -sv ../candidate/sc520_shapes/user_source/hdl_source/awb.v tb_cross_bounds.sv
vsim -c -onfinish stop -voptargs=+acc  work_bounds_720p.tb_cross_bounds
run -all
if {[examine -radix unsigned /tb_cross_bounds/completed] != 1} {quit -code 1 -f}
quit -code 0 -f
