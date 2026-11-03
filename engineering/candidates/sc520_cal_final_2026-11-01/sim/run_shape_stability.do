onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file isdirectory work]} {vlib work}
vlog -sv ../candidate/sc520_shapes/user_source/hdl_source/shape_mul64.v ../candidate/sc520_shapes/user_source/hdl_source/shape_ccl.v tb_shape_stability.sv
vsim -voptargs=+acc work.tb_shape_stability
run -all
quit -code 0 -f
