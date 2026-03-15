package require -exact qsys 18.1

set qsys_name jtag_counter_bridge

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
set_instance_parameter_value jtag_master {FAST_VER} {0}
set_instance_parameter_value jtag_master {PLI_PORT} {50000}
set_instance_parameter_value jtag_master {USE_PLI} {0}

add_instance counter_pio altera_avalon_pio
set_instance_parameter_value counter_pio {bitClearingEdgeCapReg} {0}
set_instance_parameter_value counter_pio {bitModifyingOutReg} {0}
set_instance_parameter_value counter_pio {captureEdge} {0}
set_instance_parameter_value counter_pio {direction} {Input}
set_instance_parameter_value counter_pio {edgeType} {RISING}
set_instance_parameter_value counter_pio {generateIRQ} {0}
set_instance_parameter_value counter_pio {irqType} {LEVEL}
set_instance_parameter_value counter_pio {resetValue} {0.0}
set_instance_parameter_value counter_pio {simDoTestBenchWiring} {0}
set_instance_parameter_value counter_pio {simDrivenValue} {0.0}
set_instance_parameter_value counter_pio {width} {32}

add_connection clk_0.clk jtag_master.clk
add_connection clk_0.clk_reset jtag_master.clk_reset
add_connection clk_0.clk counter_pio.clk
add_connection clk_0.clk_reset counter_pio.reset

add_connection jtag_master.master counter_pio.s1
set_connection_parameter_value jtag_master.master/counter_pio.s1 arbitrationPriority {1}
set_connection_parameter_value jtag_master.master/counter_pio.s1 baseAddress {0x0000}
set_connection_parameter_value jtag_master.master/counter_pio.s1 defaultConnection {0}

add_interface clk clock sink
set_interface_property clk EXPORT_OF clk_0.clk_in

add_interface reset reset sink
set_interface_property reset EXPORT_OF clk_0.clk_in_reset

add_interface counter_pio_external_connection conduit end
set_interface_property counter_pio_external_connection EXPORT_OF counter_pio.external_connection

set_interconnect_requirement {$system} {qsys_mm.clockCrossingAdapter} {AUTO}
set_interconnect_requirement {$system} {qsys_mm.maxAdditionalLatency} {1}
set_interconnect_requirement {$system} {qsys_mm.enableEccProtection} {FALSE}
set_interconnect_requirement {$system} {qsys_mm.insertDefaultSlave} {FALSE}

save_system ${qsys_name}.qsys
