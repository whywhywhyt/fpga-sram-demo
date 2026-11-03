onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file isdirectory defect]} {vlib defect}
vlog -sv -work defect ../candidate/sc520_shapes/user_source/hdl_source/osd_font5x7.v ../candidate/sc520_shapes/user_source/hdl_source/wall_paint_precision.v ../candidate/sc520_shapes/user_source/hdl_source/wall_light_painter.v ../../sc520_lightwall_interactive_2026-10-28/candidate/sc520_shapes/user_source/hdl_source/interactive_lightwall.v tb_capture.sv
vsim -voptargs=+acc defect.tb_capture
run -all
quit -code 0 -f
