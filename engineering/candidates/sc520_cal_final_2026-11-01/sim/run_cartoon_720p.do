onerror {quit -code 1 -f}
if {![file isdirectory work]} {vlib work}
vlog -sv ../candidate/sc520_shapes/user_source/hdl_source/natural_enhance_96.v natural_enhance_reference.v ../candidate/sc520_shapes/user_source/hdl_source/isp/prewitt_detect_96.v tb_cartoon.sv
vsim -c -onfinish stop -voptargs=+acc -gWIDTH=1280 -gHEIGHT=720 -gFRAMES=1 -gINPUT_FILE=full_rgb.hex -gEXPECTED_FILE=full_cartoon.hex work.tb_cartoon
run -all
if {[examine -radix unsigned /tb_cartoon/completed] != 1} {quit -code 1 -f}
quit -code 0 -f
