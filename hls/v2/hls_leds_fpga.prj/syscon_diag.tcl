refresh_connections
puts "commands=[lsort [info commands *service*]]"
if {[llength [info commands get_service_types]]} {
    puts "service_types=[get_service_types]"
}
set device_path [lindex [get_service_paths device] 0]
puts "device_path=$device_path"
if {$device_path ne ""} {
    set design_path [design_load "C:/Users/luthi/Documents/TALOS-V2/hls/v2/hls_leds_fpga.prj/de1_soc_hls_leds.jdi"]
    set design_inst [design_instantiate $design_path]
    design_link $design_inst $device_path
}
catch {puts "all_service_paths=[get_service_paths]"} msg
puts "get_service_paths_noarg=$msg"
foreach kind {device jtag_debug master slave sld issp bytestream packet marker monitor io_bus trace trace_db processor} {
    catch {set paths [get_service_paths $kind]} err
    if {[info exists paths]} {
        puts "$kind=[llength $paths] $paths"
        unset paths
    } else {
        puts "$kind err=$err"
    }
}
set sld_paths [get_service_paths sld]
if {[llength $sld_paths] > 0} {
    set sld0 [lindex $sld_paths 0]
    catch {set addable [get_services_to_add $sld0]} add_err
    if {[info exists addable]} {
        puts "services_to_add=$addable"
    } else {
        puts "services_to_add err=$add_err"
    }
}
flush stdout
