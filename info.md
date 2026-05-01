# TALOS-V2 RTL Repository

This repository is organized around the hand-written RTL implementation of Karpathy-style microGPT inference for the DE1-SoC.

## Layout

- `rtl/src/`: synthesizable RTL sources.
- `rtl/src/include/`: SystemVerilog include fragments used by the core.
- `rtl/generated/`: exported Q4.12 model ROM hex files.
- `rtl/microgpt/`: saved trained weights and training dataset used to regenerate ROMs.
- `rtl/python/`: JTAG host, reference model, and weight export scripts.
- `rtl/tcl/`: System Console and Quartus TCL helpers.
- `rtl/sim/`: ModelSim testbenches and simulation launch TCL.
- `rtl/docs/`: archived notes and longer design writeups.
- Repository-root `.bat` files: normal build, program, inference, and reference entrypoints.

## Common Commands

From the repository root:

```bat
compile_only.bat
program_fpga.bat
run_inference.bat --sampler rtl --steps 15 --temperature 0.5 --seed 2 --stream
reference_microgpt.bat --count 20 --temperature 0.5
run_core_sim.bat
```

Or from `rtl/`, run the core simulation directly:

```bat
vsim -c -do "do sim/testbench_core.tcl"
```

Regenerate fixed-point ROMs from the saved weights:

```bat
cd rtl
python python\export_weights.py --weights microgpt\weights_only.npy --outdir generated
```

## Active RTL Files

- `rtl/src/de1_soc_microgpt_rtl.sv`: DE1-SoC top-level, JTAG/MMIO wrapper, displays, and generation control.
- `rtl/src/microgpt_exact_core.sv`: one-token-at-a-time microGPT inference FSM.
- `rtl/src/microgpt_categorical_sampler.sv`: RTL categorical sampler.
- `rtl/src/systolic_matvec16_tile.sv`: shared 4-lane streamed matvec tile.
- `rtl/src/rms_scale_engine.sv`: iterative RMSNorm scale engine.
- `rtl/src/sat_div16_engine.sv`: saturated signed divide engine used by attention.

The RTL is deterministic for a fixed seed/configuration but is not bit-exact to Karpathy's floating-point Python implementation. It uses fixed-point Q4.12 arithmetic, LUT-based exponential weights, saturation, and xorshift-based sampling.
