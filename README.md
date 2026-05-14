# TALOS-V2

TALOS-V2 is an RTL implementation of a Karpathy's microGPT language model for the DE1-SoC / Cyclone V FPGA.

The project includes the FPGA RTL, generated model ROMs, simulation files, Python host utilities, and board-level scripts needed to build, program, and run inference over JTAG.

## Features

- SystemVerilog inference core
- DE1-SoC top level with switch, LED, HEX display, and JTAG/MMIO control
- Fixed-point model weights stored as ROM hex files
- RTL sampler for hardware token generation
- ModelSim testbench for deterministic core simulation
- Python tools for JTAG inference, reference runs, and weight export

## Repository Layout

```text
rtl/src/           Synthesizable RTL
rtl/src/include/   RTL include fragments
rtl/generated/     Fixed-point model ROM hex files
rtl/microgpt/      Saved model weights and training dataset
rtl/python/        Python host and reference utilities
rtl/tcl/           System Console and Quartus TCL scripts
rtl/sim/           ModelSim testbenches
rtl/ip/            JTAG-to-Avalon bridge IP
rtl/docs/          Additional notes and archived writeups
```

Root-level batch files provide the main workflow commands.

## Requirements

- Intel Quartus Prime 18.1 Lite or compatible Cyclone V toolchain
- ModelSim Intel FPGA Edition
- Python 3
- DE1-SoC board for hardware inference

If Quartus is not installed in a standard location, set `QUARTUS_ROOTDIR` before running the build or programming scripts.

## Quick Start

Run commands from the repository root.

Simulate the RTL core:

```bat
run_core_sim.bat
```

Build the FPGA project:

```bat
compile_only.bat
```

Program the DE1-SoC:

```bat
program_fpga.bat
```

Build and program in one step:

```bat
run_de1soc.bat
```

Run inference over JTAG:

```bat
run_inference.bat --sampler rtl --steps 15 --temperature 0.5 --seed 2 --stream
```

Run the Python reference model:

```bat
reference_microgpt.bat --count 20 --temperature 0.5
```

## Board Controls

- `SW0`: enable
- `SW1`: reset, high resets and low runs

Status outputs:

- `LEDR0`: ready
- `LEDR1`: busy
- `LEDR2`: generation done
- `LEDR3`: JTAG activity
- `LEDR4`: reset deasserted
- `LEDR5`: enable state
- `LEDR6`: busy blink
- `LEDR7..9`: low bits of the last sampled token
- `HEX0..1`: last sampled token id
- `HEX2..3`: generated token count
- `HEX4`: top-level state
- `HEX5`: switch state

## Regenerating Weights

The RTL uses Q4.12 fixed-point ROM files in `rtl/generated/`. To regenerate them from the saved model weights:

```bat
cd rtl
python python\export_weights.py --weights microgpt\weights_only.npy --outdir generated
```

## Validation

The main local checks are:

```bat
run_core_sim.bat
cd rtl\python
python -m unittest test_reference_equivalence.py
```

For hardware validation, rebuild the Quartus project, program the board, and run the JTAG inference command.

## License

Original TALOS-V2 source code, RTL, scripts, configuration, and documentation are licensed under the Apache License, Version 2.0. See `LICENSE` and `NOTICE`.

This repository also contains third-party reference material, Intel/Altera FPGA IP or generated tool outputs, and model/dataset artifacts with separate ownership or licensing terms. See `THIRD_PARTY_NOTICES.md` before redistributing the full repository or using those artifacts outside local development and validation.

## Notes

The RTL follows the microGPT transformer structure, but it uses fixed-point hardware arithmetic and an RTL-friendly sampler. Outputs are deterministic for the same seed and configuration.
