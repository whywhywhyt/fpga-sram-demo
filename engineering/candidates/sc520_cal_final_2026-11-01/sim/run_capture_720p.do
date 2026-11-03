onerror {quit -code 1 -f}
if {![file isdirectory work_capture_720p]} {vlib work_capture_720p}
vlog -work work_capture_720p -sv ../candidate/sc520_shapes/user_source/hdl_source/awb.v tb_cross_capture_720p.sv
vsim -c -onfinish stop -voptargs=+acc work_capture_720p.tb_cross_capture_720p
run -all
if {[examine -radix unsigned /tb_cross_capture_720p/completed] != 1} {quit -code 1 -f}
quit -code 0 -f
