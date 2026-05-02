# DE1-SoC RTL microgpt

This directory contains a standalone RTL implementation of the microgpt inference path for the DE1-SoC.

## Current status

- Synthesizable RTL lives under `src/`.
- The active top level is `src/de1_soc_microgpt_rtl.sv`.
- The microgpt core is in `src/microgpt_exact_core.sv`.
- Shared core definitions, fixed-point helpers, and ROM initialization live under `src/include/` and are included by `microgpt_exact_core.sv`.
- Simulation files live under `sim/`, host/reference Python lives under `python/`, and System Console TCL lives under `tcl/`.
- The JTAG-to-Avalon bridge is included through `ip/jtag_microgpt_bridge/synthesis/jtag_microgpt_bridge.qip`.
- Board pushbuttons are no longer used by the active top level.
- Generation is started from the host over JTAG/MMIO.

## Controls

- `SW0`: enable.
- `SW1`: reset. Set high to reset, low to run.
- JTAG host control register: start or restart generation.

## LEDs and displays

- `LEDR0`: ready while enabled and idle.
- `LEDR1`: busy while the core is generating.
- `LEDR2`: generation done.
- `LEDR3`: host JTAG activity.
- `LEDR4`: reset is deasserted.
- `LEDR5`: enable switch state.
- `LEDR6`: busy blink.
- `LEDR7..9`: low bits of the last sampled token.
- `HEX0..5`: most recent generated name characters, pushed by the JTAG host.

## Build and program

```bat
..\compile_only.bat
..\program_fpga.bat
..\run_core_sim.bat
```

`..\run_de1soc.bat` runs both steps.

The core uses Q4.12 fixed-point weights exported from the trained RTL weights in `microgpt/` by:

```bat
python python\export_weights.py --weights microgpt\weights_only.npy --outdir generated
```

## Run inference over JTAG

From this directory in PowerShell:

```powershell
..\run_inference.bat --steps 15 --temperature 0.5 --seed 2 --stream
```

The generated name is printed as plain text first and repeated in `output_text=...`.

The C launcher in the repository root also starts generation from BOS over the same JTAG/MMIO bridge:

```powershell
clang -Wall -Wextra main.c -o microgpt_bos_start.exe
.\microgpt_bos_start.exe --steps 15 --temperature 0.5 --seed 2
```

## Compute structure

The active microgpt core now uses a streamed 16-lane systolic MAC tile for the learned projection matrices. Projection stages such as `ST_Q_LINEAR`, `ST_K_LINEAR`, `ST_V_LINEAR`, `ST_ATTN_WO`, `ST_FC1`, `ST_FC2`, and `ST_LM_HEAD` reuse `systolic_matvec16_tile.sv` to consume one input column per cycle and accumulate a full 16-row tile in parallel while preserving the model topology.

To recover throughput without changing the microGPT math order, the long normalization and attention-output divide paths were moved into exact multicycle engines: `rms_scale_engine.sv` computes the original RMS scale value iteratively, and `sat_div16_engine.sv` computes the same saturated attention divide result the prior RTL expression produced.

The streamed matvec tile asserts `done` on the final useful column instead of burning an extra idle cycle. This removes one cycle from each projection tile invocation while preserving the exact accumulated result.

The attention output divider starts at bit 31, not bit 63. This is still exact for this datapath because the numerator is bounded by `4096 * 32768 * 16 = 2^31`, but it removes 32 idle divide iterations for each attention output element. The core now runs all four attention output channels for a head in parallel, with registered weight/value handoff into the accumulators and four parallel divider engines. This preserves the same per-channel softmax weights, weighted sums, and saturated division while removing the second serial value/divide pass per head.

The LM-head argmax is folded into the existing LM-head projection tiles, then reduced across the 16-lane tile in a short registered state sequence. The RTL sampler caches the per-token categorical weights and pipelines the temperature/index/weight stages; this keeps the same sampled token sequence while removing long combinational sampler paths from timing.

The active core clock is generated from the 50 MHz board clock with a 56.25 MHz PLL (`sys_pll_56_25.v`). The current fitted build uses 25,851 / 32,070 ALMs, 18,509 registers, and 38 / 87 DSP blocks. Slow 1100 mV 85 C setup slack is 1.692 ns at the 56.25 MHz target.

The previous programmed 4-lane build reported `..\run_inference.bat --steps 15 --temperature 0.5 --seed 2 --sampler rtl` at 45,378 tokens/sec for the single sample and 46,046 tokens/sec over 20 samples. The current 16-lane RTL has not been hardware-JTAG sampled in this workspace yet, but the deterministic ModelSim run now clears the 50k target at the core-cycle level.

In ModelSim, the RTL sampler deterministic six-step test now completes in 5,508 core cycles while preserving the calibrated output tokens `10 4 11 24 13`. Counting the five generated tokens over all six core steps, that is about 51,060 tokens/sec at 56.25 MHz.

The separate `matrixmul_unit.sv` and `processing_element.sv` files are a standalone matrix-multiply test path and are not instantiated by `de1_soc_microgpt_rtl.sv`.

## Determinism and exactness

The RTL is deterministic for the same seed and settings. `tb_microgpt_core.sv` verifies that repeated runs with the same seed produce the same RTL token sequence in ModelSim.

The RTL does not currently match Karpathy's Python `microgpt.py` bit-for-bit. The Python reference uses floating-point math, exact `math.exp` softmax, and Python `random.choices`; this RTL uses Q4.12 fixed-point arithmetic, approximate exponential weights, saturation/rounding, and an xorshift32 sampler.

The fake hardware-resident Karpathy reference stream was removed. `..\run_inference.bat` now only reports the active RTL inference core output.

To make the probability distribution match Karpathy exactly, the hardware path needs the same numerical logits-to-probability behavior as Python: equivalent precision/order for RMSNorm, matvec, attention softmax, MLP, final softmax/temperature, and Python-compatible sampling thresholds. Preloading random numbers alone only fixes the sampler; it does not make the probability distribution match if the logits and softmax differ.

Use this command from `rtl/` to show the exact Karpathy reference output from the trained RTL weights:

```powershell
python .\python\karpathy_exact_reference.py --count 20 --temperature 0.5
```
