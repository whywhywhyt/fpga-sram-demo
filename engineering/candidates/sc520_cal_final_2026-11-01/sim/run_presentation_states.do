onerror {quit -code 1 -f}
if {![file isdirectory work_ui_states]} {vlib work_ui_states}
set h ../candidate/sc520_shapes/user_source/hdl_source
vlog -work work_ui_states -sv $h/osd_font5x7.v $h/frame_status_96.v tb_presentation_states.sv
vsim -c -onfinish stop -voptargs=+acc work_ui_states.tb_presentation_states
run -all
if {[examine -radix unsigned /tb_presentation_states/completed] != 1} {quit -code 1 -f}
quit -code 0 -f
