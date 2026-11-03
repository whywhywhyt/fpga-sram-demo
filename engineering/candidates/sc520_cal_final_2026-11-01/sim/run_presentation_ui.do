onerror {quit -code 1 -f}
if {![file isdirectory work_ui]} {vlib work_ui}
set h ../candidate/sc520_shapes/user_source/hdl_source
vlog -work work_ui -sv $h/shape_mul64.v $h/shape_ccl.v $h/shape_color_vote_96.v $h/shape_detector_96.v $h/shape_overlay_96.v $h/osd_font5x7.v $h/frame_status_96.v $h/latency_meter.v $h/wall_light_painter.v tb_presentation_ui.sv
vsim -c -onfinish stop -voptargs=+acc work_ui.tb_presentation_ui
run -all
if {[examine -radix unsigned /tb_presentation_ui/completed] != 1} {quit -code 1 -f}
quit -code 0 -f
