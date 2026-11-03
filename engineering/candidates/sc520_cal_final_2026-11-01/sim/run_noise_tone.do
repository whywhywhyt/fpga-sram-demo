onerror {quit -code 1 -f}
if {![file isdirectory work]} {vlib work}
vlog -sv ../candidate/sc520_shapes/user_source/hdl_source/isp/isp_top.v tb_noise_tone.sv
vsim -c -onfinish stop -voptargs=+acc work.tb_noise_tone
run -all
if {[examine -radix unsigned /tb_noise_tone/completed] != 1} {quit -code 1 -f}
quit -code 0 -f
