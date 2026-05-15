# -----------------------------------------------------------------------------
# build.tcl -- Vivado non-project / project-based build for microgpt_pynq_top
#              targeting the PYNQ-Z2 (Zynq-7000, XC7Z010-1CLG400C).
#
# Usage (from the repository root):
#     vivado -mode batch -source hw/tcl/build.tcl
#
# Outputs:
#     hw/build/microgpt_pynq.xpr        Vivado project
#     overlays/microgpt.bit             Final bitstream
#     overlays/microgpt.hwh             Hardware handoff for PYNQ
#
# DE1 deviation: replaces Quartus .qpf/.qsf flow. Generates an AXI block
# design instead of the Avalon-MM JTAG bridge / Altera PLL hierarchy.
# -----------------------------------------------------------------------------

# --- Paths -----------------------------------------------------------------
set repo_root   [file normalize [file join [file dirname [info script]] .. ..]]
set hw_root     [file join $repo_root "hw"]
set src_root    [file join $hw_root  "src"]
set core_root   [file join $src_root "core"]
set core_inc    [file join $core_root "include"]
set top_root    [file join $src_root "top"]
set ip_root     [file join $hw_root  "ip"]
set constr_root [file join $hw_root  "constraints"]
set build_root  [file join $hw_root  "build"]
set overlays    [file join $repo_root "overlays"]

file mkdir $build_root
file mkdir $overlays

# --- Project ---------------------------------------------------------------
set proj_name "microgpt_pynq"
set part      "xc7z020clg400-1"

create_project -force $proj_name $build_root -part $part
set_property board_part tul.com.tw:pynq-z2:part0:1.0 [current_project]

# --- Sources ---------------------------------------------------------------
# RTL
add_files -norecurse [glob [file join $core_root "*.sv"]]
add_files -norecurse [file join $top_root "microgpt_pynq_top.sv"]

# SystemVerilog headers (.svh) -- must be added as project files (not just
# resolved via include_dirs) for create_bd_cell -type module -reference to
# accept the referencing RTL module.
set svh_files [glob -nocomplain [file join $core_inc "*.svh"]]
if {[llength $svh_files] > 0} {
    add_files -norecurse $svh_files
    set_property file_type "Verilog Header" [get_files -of_objects [get_filesets sources_1] *.svh]
}

# Hex weights -- added so they are tracked, but FILE_TYPE is left as default
# ("Memory File"); $readmemh resolves them through the include search path
# below rather than via the FILE_TYPE = "Memory Initialization Files" hook.
add_files -norecurse [glob [file join $ip_root "*.hex"]]

# Constraints
add_files -fileset constrs_1 -norecurse [file join $constr_root "pynq_z2.xdc"]

# Verilog includes (.svh) and the hex search directory
set_property include_dirs [list $core_inc $ip_root] [get_filesets sources_1]
set_property include_dirs [list $core_inc $ip_root] [get_filesets sim_1]

# Make sure SystemVerilog compile is used
set_property file_type SystemVerilog [get_files -filter {NAME =~ "*.sv"}]

# Vivado's `create_bd_cell -type module -reference` rejects a SystemVerilog
# file as the top of a module reference (filemgmt-56-195). microgpt_pynq_top.sv
# is Verilog-2001 compatible (no logic/always_ff/interfaces/packages -- only
# wire/reg, +: part-selects, and inline X_INTERFACE_INFO attributes), so we
# re-tag just that one file as Verilog. Children stay SystemVerilog.
set_property file_type Verilog \
    [get_files -of_objects [get_filesets sources_1] "microgpt_pynq_top.sv"]

# --- Block design ----------------------------------------------------------
set bd_name "system"
create_bd_design $bd_name

# Zynq-7000 PS with PYNQ-Z2 preset (falls back to apply_bd_automation if the
# board file is not installed).
set zynq_ps [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7_0]
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config { make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable" } \
    $zynq_ps

# Force FCLK_CLK0 = 50 MHz, single AXI GP master, fabric interrupt enabled
# so we can wire microgpt_0/done_irq up to IRQ_F2P[0].
set_property -dict [list \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {50} \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
    CONFIG.PCW_IRQ_F2P_INTR {1} \
    CONFIG.PCW_EN_CLK0_PORT {1} \
    CONFIG.PCW_EN_RST0_PORT {1} \
] $zynq_ps

# Custom IP wrapper (RTL module brought in as a BD cell)
set top_cell [create_bd_cell -type module -reference microgpt_pynq_top microgpt_0]

# Processor System Reset
set rst_inst [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ps7_50m]

# AXI Interconnect (1 master, 1 slave)
set axi_ic [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_ic_0]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] $axi_ic

# Connections -- clock / reset
connect_bd_net  [get_bd_pins ps7_0/FCLK_CLK0]    [get_bd_pins rst_ps7_50m/slowest_sync_clk]
connect_bd_net  [get_bd_pins ps7_0/FCLK_RESET0_N] [get_bd_pins rst_ps7_50m/ext_reset_in]
connect_bd_net  [get_bd_pins ps7_0/FCLK_CLK0]    [get_bd_pins ps7_0/M_AXI_GP0_ACLK]
connect_bd_net  [get_bd_pins ps7_0/FCLK_CLK0]    [get_bd_pins axi_ic_0/ACLK]
connect_bd_net  [get_bd_pins ps7_0/FCLK_CLK0]    [get_bd_pins axi_ic_0/S00_ACLK]
connect_bd_net  [get_bd_pins ps7_0/FCLK_CLK0]    [get_bd_pins axi_ic_0/M00_ACLK]
connect_bd_net  [get_bd_pins ps7_0/FCLK_CLK0]    [get_bd_pins microgpt_0/s_axi_aclk]
connect_bd_net  [get_bd_pins rst_ps7_50m/interconnect_aresetn] [get_bd_pins axi_ic_0/ARESETN]
connect_bd_net  [get_bd_pins rst_ps7_50m/peripheral_aresetn]   [get_bd_pins axi_ic_0/S00_ARESETN]
connect_bd_net  [get_bd_pins rst_ps7_50m/peripheral_aresetn]   [get_bd_pins axi_ic_0/M00_ARESETN]
connect_bd_net  [get_bd_pins rst_ps7_50m/peripheral_aresetn]   [get_bd_pins microgpt_0/s_axi_aresetn]

# AXI buses
connect_bd_intf_net [get_bd_intf_pins ps7_0/M_AXI_GP0]      [get_bd_intf_pins axi_ic_0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_ic_0/M00_AXI]     [get_bd_intf_pins microgpt_0/s_axi]

# LEDs out to top-level ports
create_bd_port -dir O led_busy
create_bd_port -dir O led_done
create_bd_port -dir O led_error
create_bd_port -dir O led_heartbeat
connect_bd_net [get_bd_pins microgpt_0/led_busy]      [get_bd_ports led_busy]
connect_bd_net [get_bd_pins microgpt_0/led_done]      [get_bd_ports led_done]
connect_bd_net [get_bd_pins microgpt_0/led_error]     [get_bd_ports led_error]
connect_bd_net [get_bd_pins microgpt_0/led_heartbeat] [get_bd_ports led_heartbeat]

# PL->PS interrupt: route microgpt_0/done_irq to IRQ_F2P[0] via xlconcat so
# the BD can grow more interrupt sources later (the GIC F2P input is a
# 16-bit bus). One source today, but the wiring is future-proof.
set irq_concat [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 irq_concat]
set_property -dict [list CONFIG.NUM_PORTS {1}] $irq_concat
connect_bd_net [get_bd_pins microgpt_0/done_irq] [get_bd_pins irq_concat/In0]
connect_bd_net [get_bd_pins irq_concat/dout]     [get_bd_pins ps7_0/IRQ_F2P]

# Address map: microgpt @ 0x4000_0000, range 4 KB
# The AXI4-Lite slave inferred from microgpt_pynq_top names its segment
# 'reg0' (Vivado's default when the HDL doesn't bind an explicit Reg name),
# so the PS7 master segment auto-derives as SEG_microgpt_0_reg0.
assign_bd_address [get_bd_addr_segs {microgpt_0/s_axi/reg0}]
set_property offset 0x40000000 [get_bd_addr_segs ps7_0/Data/SEG_microgpt_0_reg0]
set_property range  4K          [get_bd_addr_segs ps7_0/Data/SEG_microgpt_0_reg0]

validate_bd_design
save_bd_design

# Generate synthesis / simulation / hw-handoff products for the BD before
# wrapping. Required so the .hwh appears under $proj.gen/.../hw_handoff and
# so make_wrapper sees up-to-date generated sources.
generate_target all [get_files ${bd_name}.bd]

# HDL wrapper
set bd_file [get_files ${bd_name}.bd]
set wrapper_file [make_wrapper -files $bd_file -top -import]
add_files -norecurse -fileset sources_1 $wrapper_file
set_property top "${bd_name}_wrapper" [get_filesets sources_1]

# --- Implementation -------------------------------------------------------
update_compile_order -fileset sources_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%" || [get_property STATUS [get_runs synth_1]] != "synth_design Complete!"} {
    puts "ERROR: Synthesis failed."
    exit 1
}
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%" || ![string match "*write_bitstream Complete!*" [get_property STATUS [get_runs impl_1]]]} {
    puts "ERROR: Implementation / bitstream write failed."
    exit 1
}

# --- Export bit + hwh -----------------------------------------------------
# `get_files -of_objects [get_runs ...]` is rejected in Vivado 2024.1
# (run objects are not a supported -of_objects type), so wrap and fall through
# to the run-directory glob.
if {[catch {get_files -of_objects [get_runs impl_1] *.bit} bit_src]} {
    set bit_src ""
}
if {$bit_src eq ""} {
    set bit_src [glob -nocomplain [file join $build_root "$proj_name.runs" "impl_1" "*.bit"]]
}
file copy -force $bit_src [file join $overlays "microgpt.bit"]

# .hwh lives next to the BD after write_bitstream / generate_target
set hwh_src [glob -nocomplain \
    [file join $build_root "$proj_name.gen" "sources_1" "bd" $bd_name "hw_handoff" "${bd_name}.hwh"]]
if {$hwh_src eq ""} {
    set hwh_src [glob -nocomplain \
        [file join $build_root "$proj_name.srcs" "sources_1" "bd" $bd_name "hw_handoff" "${bd_name}.hwh"]]
}
if {$hwh_src ne ""} {
    file copy -force $hwh_src [file join $overlays "microgpt.hwh"]
} else {
    puts "WARNING: could not locate ${bd_name}.hwh -- check your Vivado version's BD output paths."
}

puts "Done. Artifacts in [file join $overlays]:"
puts "  microgpt.bit"
puts "  microgpt.hwh"
