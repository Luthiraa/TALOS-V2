create_clock -name CLOCK_50_IN -period 20.000 [get_ports {CLOCK_50}]
create_generated_clock -name CORE_CLK -source [get_ports {CLOCK_50}] -divide_by 12 [get_registers {*core_clk_reg}]
derive_clock_uncertainty
