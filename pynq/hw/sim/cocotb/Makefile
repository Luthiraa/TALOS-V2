# -----------------------------------------------------------------------------
# cocotb Makefile -- microgpt_pynq_top AXI4-Lite slave testbench.
#
# Drives the wrapper directly with cocotbext-axi (no BD, no PS7 model needed)
# so we can catch handshake / register-map regressions before paying for a
# 30-minute Vivado build and a board power cycle.
#
# Usage:
#     cd hw/sim/cocotb
#     make                     # all tests, default simulator (icarus)
#     make SIM=verilator       # use Verilator instead
#     make WAVES=1             # dump a waveform alongside the run
#     make MODULE=test_microgpt_axi TESTCASE=test_03_write_completes_does_not_hang
# -----------------------------------------------------------------------------

TOPLEVEL_LANG ?= verilog

# Auto-pick whichever simulator is installed (prefer icarus when both are
# present, since it's the cocotb default). Override with `make SIM=...`.
ifeq ($(SIM),)
    ifneq ($(shell command -v iverilog 2>/dev/null),)
        SIM := icarus
    else ifneq ($(shell command -v verilator 2>/dev/null),)
        SIM := verilator
    else
        $(error Neither iverilog nor verilator found in PATH. Install one: \
                sudo pacman -S iverilog  OR  sudo pacman -S verilator)
    endif
endif

PWD       := $(shell pwd)
REPO_ROOT := $(abspath $(PWD)/../../..)
HW_ROOT   := $(REPO_ROOT)/hw

# DUT + the unmodified TALOS-V2 core it instantiates. Children stay
# SystemVerilog (Icarus -g2012 / Verilator handle the dialect).
VERILOG_SOURCES += $(HW_ROOT)/src/top/microgpt_pynq_top.sv
VERILOG_SOURCES += $(wildcard $(HW_ROOT)/src/core/*.sv)

ifeq ($(SIM),icarus)
    COMPILE_ARGS += -g2012
    COMPILE_ARGS += -I$(HW_ROOT)/src/core/include
    COMPILE_ARGS += -I$(HW_ROOT)/ip
    # Shrink the heartbeat counter for sim so test_08 sees a toggle quickly.
    COMPILE_ARGS += -Pmicrogpt_pynq_top.HEARTBEAT_BITS=12
endif

ifeq ($(SIM),verilator)
    EXTRA_ARGS   += --trace --trace-structs
    EXTRA_ARGS   += -I$(HW_ROOT)/src/core/include
    EXTRA_ARGS   += -I$(HW_ROOT)/ip
    EXTRA_ARGS   += --timescale 1ns/1ps
    EXTRA_ARGS   += -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT
    # Shrink the heartbeat counter for sim so test_08 sees a toggle quickly.
    EXTRA_ARGS   += -GHEARTBEAT_BITS=12
endif

TOPLEVEL = microgpt_pynq_top
MODULE  ?= test_microgpt_axi

include $(shell cocotb-config --makefiles)/Makefile.sim
