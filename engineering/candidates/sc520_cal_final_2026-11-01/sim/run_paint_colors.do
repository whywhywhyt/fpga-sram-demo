onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file isdirectory color_work]} {vlib color_work}
vlog -work color_work -sv ../candidate/sc520_shapes/user_source/hdl_source/osd_font5x7.v ../candidate/sc520_shapes/user_source/hdl_source/wall_light_painter.v tb_paint_colors.sv
vsim -voptargs=+acc color_work.tb_paint_colors
run -all
quit -code 0 -f
