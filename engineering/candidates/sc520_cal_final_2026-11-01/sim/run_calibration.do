onerror {quit -code 1 -f}
if {![file isdirectory work_calibration]} {vlib work_calibration}
vlog -work work_calibration -sv ../candidate/sc520_shapes/user_source/hdl_source/awb.v tb_cross_calibration.sv
vsim -c -onfinish stop -voptargs=+acc  work_calibration.tb_cross_calibration
run -all
if {[examine -radix unsigned /tb_cross_calibration/completed] != 1} {quit -code 1 -f}
quit -code 0 -f
