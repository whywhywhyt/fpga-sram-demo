onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file isdirectory marker_work]} {vlib marker_work}
vlog -work marker_work -sv ../candidate/sc520_shapes/user_source/hdl_source/osd_font5x7.v ../candidate/sc520_shapes/user_source/hdl_source/wall_light_painter.v ../candidate/sc520_shapes/user_source/hdl_source/wall_paint_precision.v tb_paint_precision.sv tb_red_marker.sv
vsim -voptargs=+acc marker_work.tb_red_marker
run -all
quit -code 0 -f
