proc mgpt_read32 {m addr} {
    return [lindex [master_read_32 $m $addr 1] 0]
}

proc mgpt_default_jdi_path {} {
    return [file normalize [file join [pwd] "de1_soc_microgpt.jdi"]]
}

proc mgpt_bool_env {name default_value} {
    if {[info exists ::env($name)]} {
        set raw [string tolower [string trim $::env($name)]]
        if {$raw in {"1" "true" "yes" "on"}} {
            return 1
        }
        if {$raw in {"0" "false" "no" "off"}} {
            return 0
        }
    }
    return $default_value
}

refresh_connections

set device_path [lindex [get_service_paths device] 0]
if {$device_path eq ""} {
    error "No device service found."
}

set jdi_path [mgpt_default_jdi_path]
if {[info exists ::env(MGPT_JDI)] && ($::env(MGPT_JDI) ne "")} {
    set jdi_path [file normalize $::env(MGPT_JDI)]
}
if {![file exists $jdi_path]} {
    error "JDI file not found: $jdi_path"
}

set design_path [design_load $jdi_path]
set design_inst [design_instantiate $design_path]
design_link $design_inst $device_path

set service_path [lindex [get_service_paths master] 0]
if {$service_path eq ""} {
    error "No JTAG master service found."
}
open_service master $service_path

set max_gen $::env(MGPT_MAX_GEN)
set temp_q8_8 $::env(MGPT_TEMP_Q8_8)
set seed $::env(MGPT_SEED)
set stream_tokens [mgpt_bool_env MGPT_STREAM_TOKENS 0]
set sample_count 1
if {[info exists ::env(MGPT_SAMPLE_COUNT)]} {
    set sample_count [expr {int($::env(MGPT_SAMPLE_COUNT))}]
    if {$sample_count < 1} {
        set sample_count 1
    }
}
set poll_ms 1
if {[info exists ::env(MGPT_POLL_MS)]} {
    set poll_ms [expr {int($::env(MGPT_POLL_MS))}]
    if {$poll_ms < 1} {
        set poll_ms 1
    }
}

for {set sample_idx 0} {$sample_idx < $sample_count} {incr sample_idx} {
    set sample_seed [expr {$seed + $sample_idx}]
    puts "SAMPLE_BEGIN=$sample_idx"
    flush stdout

    master_write_32 $service_path 0x08 0x00000002
    master_write_32 $service_path 0x10 [expr {($temp_q8_8 << 16) | (($max_gen & 0xff) << 8)}]
    master_write_32 $service_path 0x14 $sample_seed
    master_write_32 $service_path 0x08 0x00000001

    set timeout 5000
    set status 0
    set streamed_len 0
    while {$timeout > 0} {
        set status [mgpt_read32 $service_path 0x0C]
        set out_len_now [expr {($status >> 16) & 0xff}]
        if {$stream_tokens && ($out_len_now > $streamed_len)} {
            for {set i $streamed_len} {$i < $out_len_now} {incr i} {
                set token_word [mgpt_read32 $service_path [expr {0x60 + ($i * 4)}]]
                puts "STREAM_TOKEN=[expr {$token_word & 0xff}]"
                flush stdout
            }
            set streamed_len $out_len_now
        }
        if {$status & 0x8} {
            puts "ERROR=1"
            break
        }
        if {$status & 0x4} {
            puts "DONE=1"
            break
        }
        after $poll_ms
        incr timeout -1
    }

    puts [format {STATUS[%d]=0x%08X} $sample_idx $status]
    set out_len [expr {($status >> 16) & 0xff}]
    puts [format {OUT_LEN[%d]=%d} $sample_idx $out_len]

    set outputs {}
    for {set i 0} {$i < $out_len} {incr i} {
        lappend outputs [mgpt_read32 $service_path [expr {0x60 + ($i * 4)}]]
    }
    puts [format {OUTPUT_TOKENS[%d]=%s} $sample_idx $outputs]
    puts "SAMPLE_END=$sample_idx"
    flush stdout
}

close_service master $service_path
