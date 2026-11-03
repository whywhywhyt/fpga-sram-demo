if {[catch {source camera_to_dsi_display.tcl} message]} {
    puts stderr "FLOW_FAILED: $message"
    exit 1
}
puts "FLOW_SCRIPT_COMPLETED"
exit 0
