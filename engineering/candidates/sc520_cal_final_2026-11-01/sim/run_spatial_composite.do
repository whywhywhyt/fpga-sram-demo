transcript on
onerror {quit -code 1 -f}
vlib work_spatial_composite
vmap work_spatial_composite work_spatial_composite
vlog -work work_spatial_composite -sv ../candidate/sc520_shapes/user_source/hdl_source/frame_status_96.v ../candidate/sc520_shapes/user_source/hdl_source/osd_font5x7.v ../candidate/sc520_shapes/user_source/hdl_source/latency_meter.v ../candidate/sc520_shapes/user_source/hdl_source/wall_light_painter.v ../candidate/sc520_shapes/user_source/hdl_source/wall_paint_precision.v ../candidate/sc520_shapes/user_source/hdl_source/video_osd.v ../candidate/sc520_shapes/user_source/hdl_source/logo_index_rom.v tb_spatial_composite.sv
vsim -c -voptargs=+acc work_spatial_composite.tb_spatial_composite
run -all
if {[examine -radix unsigned /tb_spatial_composite/completed] != 1} {quit -code 1 -f}
quit -code 0 -f
