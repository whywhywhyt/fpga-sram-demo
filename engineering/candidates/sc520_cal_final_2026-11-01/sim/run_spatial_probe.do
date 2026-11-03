transcript on
onerror {quit -code 1 -f}
vlib work_spatial_probe
vmap work_spatial_probe work_spatial_probe
vlog -work work_spatial_probe -sv ../candidate/sc520_shapes/user_source/hdl_source/osd_font5x7.v ../candidate/sc520_shapes/user_source/hdl_source/frame_status_96.v frame_status_baseline.v tb_spatial_probe.sv
vsim -c -voptargs=+acc work_spatial_probe.tb_spatial_probe
run -all
quit -code 0 -f
