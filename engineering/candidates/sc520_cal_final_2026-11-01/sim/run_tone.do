transcript on
onerror {quit -code 1 -f}
if {![file isdirectory work_tone]} {vlib work_tone}
vlog -work work_tone -sv ../candidate/sc520_shapes/user_source/hdl_source/isp/isp_top.v tb_tone.sv
vsim -c -onfinish stop -voptargs=+acc work_tone.tb_tone
run -all
if {[examine -radix unsigned /tb_tone/completed] != 1} {quit -code 1 -f}
quit -code 0 -f
