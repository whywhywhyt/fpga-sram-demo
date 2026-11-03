# Invoked from phy_1, after a completed routed DB. No clock relaxation,
# false paths, RTL changes or hardware access.
source settings.cfg
import_device $device_name -package $package_name -speed $speed
open_project camera_to_dsi_display.prj -noanalyze
import_db camera_to_dsi_display_pr.db
update_timing -mode final
report_timing_summary -file pre_postopt_timing.rpt
phys_opt -post_route -effort $taskEffort
fix_hold
update_timing -mode final
report_timing_summary -file final_timing.rpt
report_area -io_info -file camera_to_dsi_display_phy.area
report_timing_exception -file camera_to_dsi_display_exception.timing
set taskHandle [open final_timing.rpt r]
set taskTiming [read $taskHandle]
close $taskHandle
if {![regexp {SWNS:\s*([-0-9.]+)ns, STNS:\s*([-0-9.]+)ns\s+HWNS:\s*([-0-9.]+)ns, HTNS:\s*([-0-9.]+)ns} $taskTiming all sw st hw ht]} {error "Timing summary missing"}
export_db camera_to_dsi_display_postopt.db
if {$sw<0 || $hw<0 || $st!=0 || $ht!=0} {error "Timing still violates: setup=$sw hold=$hw"}
export_db camera_to_dsi_display_pr.db
bitgen -bit camera_to_dsi_display.bit
puts "POST_ROUTE_TIMING_AND_BIT_PASSED"
