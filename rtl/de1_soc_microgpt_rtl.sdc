create_clock -name CLOCK_50_IN -period 20.000 [get_ports {CLOCK_50}]
derive_pll_clocks
set_clock_groups -asynchronous \
    -group [get_clocks {CLOCK_50_IN}] \
    -group [get_clocks {*PLL_OUTPUT_COUNTER*}]
derive_clock_uncertainty
