proc mgpt_read32 {m addr} {
    return [lindex [master_read_32 $m $addr 1] 0]
}

proc mgpt_write32 {m addr value} {
    master_write_32 $m $addr $value
}

proc mgpt_signed32 {value} {
    if {$value >= 0x80000000} {
        return [expr {$value - 0x100000000}]
    }
    return $value
}

proc mgpt_cleanup {} {
    if {[info exists ::mgpt_service_path] && ($::mgpt_service_path ne "")} {
        catch {close_service master $::mgpt_service_path}
    }
}

proc mgpt_seed {seed} {
    mgpt_write32 $::mgpt_service_path 0x14 [expr {$seed & 0xFFFFFFFF}]
    puts "SEED_SET=1"
    flush stdout
}

proc mgpt_step {token pos clear poll_ms} {
    set step_cfg [expr {1 | (($clear & 1) << 1) | (($pos & 0xFF) << 8) | (($token & 0xFF) << 16)}]
    mgpt_write32 $::mgpt_service_path 0x20 $step_cfg
    mgpt_write32 $::mgpt_service_path 0x24 0x00000001

    set timeout 20000
    set status 0
    while {$timeout > 0} {
        set status [mgpt_read32 $::mgpt_service_path 0x0C]
        if {$status & 0x8} {
            break
        }
        if {$status & 0x4} {
            break
        }
        if {$poll_ms > 0} {
            after $poll_ms
        }
        incr timeout -1
    }

    if {$timeout <= 0} {
        puts "STEP_TIMEOUT=1"
        flush stdout
        return
    }

    puts [format {STEP_STATUS=0x%08X} $status]
    puts [format {STEP_PERF_CYCLES=%u} [mgpt_read32 $::mgpt_service_path 0xD8]]
    set logits {}
    for {set i 0} {$i < 27} {incr i} {
        set raw_logit [mgpt_read32 $::mgpt_service_path [expr {0x100 + ($i * 4)}]]
        lappend logits [mgpt_signed32 $raw_logit]
    }
    puts [format {STEP_LOGITS=%s} $logits]
    puts "STEP_END=1"
    flush stdout
}

proc mgpt_close {} {
    mgpt_cleanup
    puts "SESSION_CLOSED=1"
    flush stdout
}

refresh_connections

set device_path [lindex [get_service_paths device] 0]
if {$device_path eq ""} {
    error "No device service found."
}

set jdi_path [file normalize [file join [pwd] "de1_soc_microgpt_rtl.jdi"]]
if {[info exists ::env(MGPT_JDI)] && ($::env(MGPT_JDI) ne "")} {
    set jdi_path [file normalize $::env(MGPT_JDI)]
}
if {![file exists $jdi_path]} {
    error "JDI file not found: $jdi_path"
}

set design_path [design_load $jdi_path]
set design_inst [design_instantiate $design_path]
design_link $design_inst $device_path

set ::mgpt_service_path [lindex [get_service_paths master] 0]
if {$::mgpt_service_path eq ""} {
    error "No JTAG master service found."
}
open_service master $::mgpt_service_path
mgpt_write32 $::mgpt_service_path 0x08 0x00000002

puts "SESSION_READY=1"
flush stdout
