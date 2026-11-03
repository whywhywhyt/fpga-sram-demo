onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file isdirectory work_home]} {vlib work_home}
set h ../candidate/sc520_shapes/user_source/hdl_source
vlog -work work_home -sv $h/osd_font5x7.v $h/wall_light_painter.v tb_wall_home.sv
vsim -voptargs=+acc work_home.tb_wall_home
run -all
quit -code 0 -f
