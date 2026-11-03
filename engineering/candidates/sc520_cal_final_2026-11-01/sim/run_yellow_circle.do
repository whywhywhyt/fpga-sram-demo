onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file isdirectory work]} {vlib work}
vlog -sv ../candidate/sc520_shapes/user_source/hdl_source/shape_mul64.v ../candidate/sc520_shapes/user_source/hdl_source/shape_ccl.v ../candidate/sc520_shapes/user_source/hdl_source/shape_color_vote_96.v ../candidate/sc520_shapes/user_source/hdl_source/shape_detector_96.v tb_yellow_circle.sv
vsim -voptargs=+acc work.tb_yellow_circle
run -all
quit -code 0 -f
