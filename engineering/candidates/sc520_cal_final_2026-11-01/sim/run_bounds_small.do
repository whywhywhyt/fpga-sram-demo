onerror {quit -code 1 -f}
if {![file isdirectory work_bounds_small]} {vlib work_bounds_small}
vlog -work work_bounds_small -sv ../candidate/sc520_shapes/user_source/hdl_source/awb.v tb_cross_bounds.sv
vsim -c -onfinish stop -voptargs=+acc -gWIDTH=128 -gHEIGHT=64 -gCASES=32 work_bounds_small.tb_cross_bounds
run -all
if {[examine -radix unsigned /tb_cross_bounds/completed] != 1} {quit -code 1 -f}
quit -code 0 -f
