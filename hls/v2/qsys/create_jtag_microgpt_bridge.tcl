package require -exact qsys 18.1

set qsys_name jtag_microgpt_bridge

create_system $qsys_name

set_project_property DEVICE_FAMILY {Cyclone V}
set_project_property DEVICE {5CSEMA5F31C6}

add_instance clk_0 clock_source
set_instance_parameter_value clk_0 {clockFrequency} {50000000.0}
set_instance_parameter_value clk_0 {clockFrequencyKnown} {1}
set_instance_parameter_value clk_0 {resetSynchronousEdges} {DEASSERT}

add_instance jtag_master altera_jtag_avalon_master
set_instance_parameter_value jtag_master {AUTO_DEVICE} {5CSEMA5F31C6}
set_instance_parameter_value jtag_master {AUTO_DEVICE_FAMILY} {Cyclone V}
set_instance_parameter_value jtag_master {AUTO_DEVICE_SPEEDGRADE} {6}
set_instance_parameter_value jtag_master {FAST_VER} {1}
set_instance_parameter_value jtag_master {FIFO_DEPTHS} {8}
set_instance_parameter_value jtag_master {PLI_PORT} {50000}
set_instance_parameter_value jtag_master {USE_PLI} {0}

add_connection clk_0.clk jtag_master.clk
add_connection clk_0.clk_reset jtag_master.clk_reset

add_interface clk clock sink
set_interface_property clk EXPORT_OF clk_0.clk_in

add_interface reset reset sink
set_interface_property reset EXPORT_OF clk_0.clk_in_reset

add_interface master avalon start
set_interface_property master EXPORT_OF jtag_master.master

set_interconnect_requirement {$system} {qsys_mm.clockCrossingAdapter} {AUTO}
set_interconnect_requirement {$system} {qsys_mm.maxAdditionalLatency} {1}
set_interconnect_requirement {$system} {qsys_mm.enableEccProtection} {FALSE}
set_interconnect_requirement {$system} {qsys_mm.insertDefaultSlave} {FALSE}

save_system ${qsys_name}.qsys
