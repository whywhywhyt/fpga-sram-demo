onerror {quit -code 1 -f}
if {![file isdirectory work_cartoon_route]} {vlib work_cartoon_route}
set h ../candidate/sc520_shapes/user_source/hdl_source
vlog -work work_cartoon_route -sv $h/image_modes_96.v $h/rgb_mode_96.v $h/natural_enhance_96.v $h/isp/prewitt_detect_96.v tb_cartoon_routing.sv
vsim -c -onfinish stop -voptargs=+acc work_cartoon_route.tb_cartoon_routing
run -all
if {[examine -radix unsigned /tb_cartoon_routing/completed] != 1} {quit -code 1 -f}
quit -code 0 -f
