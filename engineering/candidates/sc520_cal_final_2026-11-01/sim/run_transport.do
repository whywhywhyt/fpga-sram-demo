onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file isdirectory work]} {vlib work}
vlog -sv ../candidate/sc520_shapes/user_source/hdl_source/osd_font5x7.v ../candidate/sc520_shapes/user_source/hdl_source/wall_paint_precision.v ../candidate/sc520_shapes/user_source/hdl_source/wall_light_painter.v ../candidate/sc520_shapes/user_source/hdl_source/interactive_lightwall.v tb_transport.sv
vsim -voptargs=+acc work.tb_transport
run -all
quit -code 0 -f
