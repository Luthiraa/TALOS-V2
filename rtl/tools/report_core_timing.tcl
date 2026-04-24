project_open de1_soc_microgpt_rtl -revision de1_soc_microgpt_rtl
create_timing_netlist
read_sdc
update_timing_netlist

puts "==== CORE_CLK SETUP PATHS ===="
report_timing -from_clock CORE_CLK -to_clock CORE_CLK -setup -npaths 10 -detail full_path

puts "==== CORE_CLK FMAX ===="
report_clock_fmax_summary

project_close
