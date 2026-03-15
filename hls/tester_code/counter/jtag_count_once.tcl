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

puts "hardware=$hardware_name"
puts "device=$device_name"
open_device -hardware_name $hardware_name -device_name $device_name
device_lock -timeout 10000
device_virtual_ir_shift -instance_index 0 -ir_value 1 -no_captured_ir_value
set count_hex [device_virtual_dr_shift -instance_index 0 -length 32 -value_in_hex]
device_unlock
close_device

scan $count_hex "%x" count
puts [format "count=0x%08X (%u)" $count $count]
flush stdout
