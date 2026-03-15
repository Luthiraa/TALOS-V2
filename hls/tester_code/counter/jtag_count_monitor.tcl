if {[catch {load_package jtag}]} {
    error "Run this script with quartus_stp -t, not system-console."
}

set hardware_name ""
foreach candidate [get_hardware_names] {
    if {[string match "*DE-SoC*" $candidate] || [string match "*USB-1*" $candidate]} {
        set hardware_name $candidate
        break
    }
}
if {$hardware_name eq ""} {
    set hardware_name [lindex [get_hardware_names] 0]
}
if {$hardware_name eq ""} {
    error "No programming hardware found."
}

set device_name ""
foreach candidate [get_device_names -hardware_name $hardware_name] {
    if {[string match "@2*" $candidate]} {
        set device_name $candidate
        break
    }
}
if {$device_name eq ""} {
    set device_name [lindex [get_device_names -hardware_name $hardware_name] 0]
}
if {$device_name eq ""} {
    error "No FPGA device found on the selected hardware."
}

open_device -hardware_name $hardware_name -device_name $device_name

set last_value ""
puts "Monitoring counter over USB-Blaster JTAG. Press Ctrl+C to stop."
puts "hardware=$hardware_name"
puts "device=$device_name"
flush stdout

while {1} {
    device_lock -timeout 10000
    device_virtual_ir_shift -instance_index 0 -ir_value 1 -no_captured_ir_value
    set count_hex [device_virtual_dr_shift -instance_index 0 -length 32 -value_in_hex]
    device_unlock

    scan $count_hex "%x" count
    set value [format "0x%08X" $count]
    if {$value ne $last_value} {
        puts [format "count=0x%08X (%u)" $count $count]
        flush stdout
        set last_value $value
    }
    after 100
}
