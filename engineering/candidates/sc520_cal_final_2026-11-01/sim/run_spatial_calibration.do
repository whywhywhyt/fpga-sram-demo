transcript on
onerror {quit -code 1 -f}
vlib work_spatial_calibration
vmap work_spatial_calibration work_spatial_calibration
vlog -work work_spatial_calibration -sv ../candidate/sc520_shapes/user_source/hdl_source/awb.v tb_spatial_calibration.sv tb_spatial_720p.sv
foreach test {tb_spatial_calibration tb_spatial_720p} {
    vsim -c -onfinish stop -voptargs=+acc work_spatial_calibration.$test
    run -all
    if {[examine -radix decimal /$test/completed] != 1} {quit -code 1 -f}
    quit -sim
}
quit -code 0 -f
