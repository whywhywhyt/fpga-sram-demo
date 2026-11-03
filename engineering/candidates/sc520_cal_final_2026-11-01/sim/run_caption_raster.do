onerror {quit -code 1 -f}
vlib work_caption_raster
set h ../candidate/sc520_shapes/user_source/hdl_source
vlog -work work_caption_raster -sv $h/osd_font5x7.v $h/frame_status_96.v $h/latency_meter.v $h/wall_light_painter.v tb_caption_raster.sv
vsim -c -onfinish stop work_caption_raster.tb_caption_raster
run -all
if {[examine -radix unsigned /tb_caption_raster/completed] != 1} {quit -code 1 -f}
if {[catch {exec python verify_caption_raster.py} result]} {puts $result; quit -code 1 -f}
puts $result
quit -code 0 -f
