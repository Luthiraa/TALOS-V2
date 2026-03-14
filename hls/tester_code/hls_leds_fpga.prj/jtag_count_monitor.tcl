refresh_connections
set device_path [lindex [get_service_paths device] 0]
if {$device_path eq ""} {
    error "No JTAG device found. Check USB-Blaster connection."
}

set design_path [design_load "C:/Users/luthi/Documents/TALOS-V2/hls/tester_code/hls_leds_fpga.prj/de1_soc_hls_leds.jdi"]
set design_inst [design_instantiate $design_path]
design_link $design_inst $device_path

set services [get_service_paths issp]
if {[llength $services] == 0} {
    error "No linked In-System Sources and Probes service found. Program the FPGA first."
}

array unset bit_services
foreach service $services {
    if {[catch {array set node_info [marker_get_info $service]}]} {
        continue
    }
    if {[info exists node_info(FULL_HPATH)] && [regexp {jtag_count_probe_bits\[(\d+)\]\.jtag_count_probe$} $node_info(FULL_HPATH) -> bit_idx]} {
        set bit_services($bit_idx) $service
    }
}

if {[array size bit_services] != 32} {
    error "Expected 32 JTAG counter bit probes, found [array size bit_services]."
}

set last_value ""

puts "Monitoring counter over USB-Blaster JTAG. Press Ctrl+C to stop."
while {1} {
    set count 0
    for {set bit_idx 0} {$bit_idx < 32} {incr bit_idx} {
        set claim_path [claim_service issp $bit_services($bit_idx) count_mon]
        set raw_bit [issp_read_probe_data $claim_path]
        close_service issp $claim_path
        scan $raw_bit "%x" bit_value
        if {$bit_value != 0} {
            set count [expr {$count | (1 << $bit_idx)}]
        }
    }
    set value [format "0x%08X" $count]
    if {$value ne $last_value} {
        puts [format "count=0x%08X (%u)" $count $count]
        flush stdout
        set last_value $value
    }
    after 100
}
