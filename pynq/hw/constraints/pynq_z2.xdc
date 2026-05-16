# -----------------------------------------------------------------------------
# pynq_z2.xdc -- PYNQ-Z2 (Zynq XC7Z020-1CLG400C / -1 family) PL pin constraints.
#
# DE1 deviation: only the four PL LEDs LD0..LD3 are pinned out. CLOCK_50, SW,
# HEX0..HEX5, and LEDR[9:0] from the original DE1 board are removed -- the PS
# supplies the clock through FCLK_CLK0 and the host runs over AXI.
#
# No clock constraints are needed: FCLK_CLK0 is constrained automatically
# by the Zynq PS IP.
# -----------------------------------------------------------------------------

# DIAGNOSTIC SWAP: LD3 stayed dark even with the heartbeat counter's R pin
# proven clean. To isolate "physical LD3/M14" vs "design heartbeat path", the
# four functional LED nets are rotated one position over the four physical LEDs:
#   LD0 (R14) <- led_heartbeat   (must blink at ~0.74 Hz if the path works)
#   LD1 (P14) <- led_busy
#   LD2 (N16) <- led_done
#   LD3 (M14) <- led_error       (lights only after the forced-error inference)
# The README register-map and software driver still see the same signals; only
# the visible LED that each one drives changed.
# LD0
set_property -dict { PACKAGE_PIN R14  IOSTANDARD LVCMOS33 } [get_ports { led_heartbeat }];
# LD1
set_property -dict { PACKAGE_PIN P14  IOSTANDARD LVCMOS33 } [get_ports { led_busy }];
# LD2
set_property -dict { PACKAGE_PIN N16  IOSTANDARD LVCMOS33 } [get_ports { led_done }];
# LD3
set_property -dict { PACKAGE_PIN M14  IOSTANDARD LVCMOS33 } [get_ports { led_error }];
