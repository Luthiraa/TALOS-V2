project_open de1_soc_microgpt_rtl -revision de1_soc_microgpt_rtl
create_timing_netlist
read_sdc
update_timing_netlist

puts "==== CORE_CLK SETUP PATHS ===="
set core_clocks [get_clocks {*PLL_OUTPUT_COUNTER*}]
if {[llength $core_clocks] == 0} {
    set core_clocks [get_clocks {CORE_CLK CLOCK_50_IN}]
}
report_timing -from_clock $core_clocks -to_clock $core_clocks -setup -npaths 10 -detail full_path

puts "==== CORE_CLK FMAX ===="
report_clock_fmax_summary

project_close
