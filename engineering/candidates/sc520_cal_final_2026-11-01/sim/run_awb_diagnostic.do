transcript on
onerror {quit -code 1 -f}
vlib work_awb_diagnostic
vmap work_awb_diagnostic work_awb_diagnostic
vlog -work work_awb_diagnostic -sv ../candidate/sc520_shapes/user_source/hdl_source/awb.v ../candidate/sc520_shapes/user_source/hdl_source/osd_font5x7.v ../candidate/sc520_shapes/user_source/hdl_source/frame_status_96.v tb_awb_diagnostic.sv
vsim -c -voptargs=+acc work_awb_diagnostic.tb_awb_diagnostic
run -all
quit -code 0 -f
