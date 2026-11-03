transcript on
onerror {quit -code 1 -f}
vlib work_color_fidelity
vmap work_color_fidelity work_color_fidelity
vlog -work work_color_fidelity -sv ../candidate/sc520_shapes/user_source/hdl_source/awb.v tb_awb_unit.v
foreach test {tb_awb_unit tb_awb_ratio} {
    vsim -c -onfinish stop work_color_fidelity.$test
    run -all
    if {[examine -radix decimal /$test/errors] != 0} {quit -code 1 -f}
    quit -sim
}
puts "PASS color fidelity AWB: independent exact-cycle RGB/gains, strong-color rejection, reference dropout, lighting transition, reset and shared divider"
quit -code 0 -f
