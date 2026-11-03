onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file isdirectory work]} {vlib work}
vlog -sv ../candidate/sc520_shapes/user_source/hdl_source/wall_paint_precision.v tb_paint_overlay.sv
vsim -voptargs=+acc work.tb_paint_overlay
run -all
quit -code 0 -f
