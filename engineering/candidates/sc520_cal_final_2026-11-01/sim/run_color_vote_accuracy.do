onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file isdirectory work]} {vlib work}
vlog -sv ../candidate/sc520_shapes/user_source/hdl_source/shape_color_vote_96.v tb_color_vote_accuracy.sv
vsim -voptargs=+acc work.tb_color_vote_accuracy
run -all
quit -code 0 -f
