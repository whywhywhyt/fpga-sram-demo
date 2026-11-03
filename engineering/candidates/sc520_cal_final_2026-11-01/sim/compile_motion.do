onerror {quit -code 1 -f}
onbreak {quit -code 1 -f}
if {![file isdirectory work_motion]} {vlib work_motion}
set h ../candidate/sc520_shapes/user_source/hdl_source
vlog -work work_motion -sv $h/motion_detect_96.v $h/frame_status_96.v $h/osd_font5x7.v $h/mode_button_control.v
quit -code 0 -f
