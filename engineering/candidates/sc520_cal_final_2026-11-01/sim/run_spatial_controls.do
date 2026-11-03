transcript on
onerror {quit -code 1 -f}
vlib work_spatial_controls
vmap work_spatial_controls work_spatial_controls
vlog -work work_spatial_controls -sv ../candidate/sc520_shapes/user_source/hdl_source/mode_button_control.v ../candidate/sc520_shapes/user_source/hdl_source/osd_font5x7.v ../candidate/sc520_shapes/user_source/hdl_source/frame_status_96.v tb_spatial_controls.sv
vsim -c -voptargs=+acc work_spatial_controls.tb_spatial_controls
run -all
quit -code 0 -f
