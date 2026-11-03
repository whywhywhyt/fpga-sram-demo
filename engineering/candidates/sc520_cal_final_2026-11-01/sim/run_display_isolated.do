transcript on
onerror {quit -code 1 -f}
if {![file isdirectory work_display_isolated]} {vlib work_display_isolated}
set h ../candidate/sc520_shapes/user_source/hdl_source
vlog -work work_display_isolated -sv $h/isp/isp_top.v $h/awb.v $h/isp/data128_96/data128_96.v $h/data_96bit_to_128bit.v $h/image_modes_96.v $h/rgb_mode_96.v $h/natural_enhance_96.v $h/isp/prewitt_detect_96.v $h/motion_detect_96.v $h/shape_overlay_96.v $h/shape_detector_96.v $h/shape_ccl.v $h/shape_mul64.v $h/shape_color_vote_96.v $h/osd_font5x7.v $h/frame_status_96.v tb_display_isolated.sv
vsim -c -onfinish stop -voptargs=+acc work_display_isolated.tb_display_isolated
run -all
if {[examine -radix unsigned /tb_display_isolated/completed] != 1} {quit -code 1 -f}
quit -code 0 -f
