onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file isdirectory work]} {vlib work}
vlog -sv ../candidate/sc520_shapes/user_source/hdl_source/shape_mul64.v ../candidate/sc520_shapes/user_source/hdl_source/shape_ccl.v ../candidate/sc520_shapes/user_source/hdl_source/shape_color_vote_96.v ../candidate/sc520_shapes/user_source/hdl_source/shape_detector_96.v ../candidate/sc520_shapes/user_source/hdl_source/shape_overlay_96.v ../candidate/sc520_shapes/user_source/hdl_source/osd_font5x7.v tb_shape_overlay.sv
vsim -voptargs=+acc work.tb_shape_overlay
run -all
quit -code 0 -f
