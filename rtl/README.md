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
- `HEX0..1`: last sampled token id.
- `HEX2..3`: generated token count.
- `HEX4`: top-level state.
- `HEX5`: switch state.

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

The active microgpt core now uses a streamed 4-lane systolic MAC tile for the learned projection matrices. Projection stages such as `ST_Q_LINEAR`, `ST_K_LINEAR`, `ST_V_LINEAR`, `ST_ATTN_WO`, `ST_FC1`, `ST_FC2`, and `ST_LM_HEAD` reuse `systolic_matvec16_tile.sv` to consume one input column per cycle and accumulate four output rows in parallel.

The tile is intentionally 4 lanes, not 16, because the full 16-lane version simulated correctly but did not fit on the 5CSEMA5. The 4-lane streamed version preserves the model topology and fits with positive timing.

To recover throughput without changing the microGPT math order, the long normalization and attention-output divide paths were moved into exact multicycle engines: `rms_scale_engine.sv` computes the original RMS scale value iteratively, and `sat_div16_engine.sv` computes the same saturated attention divide result the prior RTL expression produced.

The streamed matvec tile asserts `done` on the final useful column instead of burning an extra idle cycle. This removes one cycle from each 4-row projection tile invocation while preserving the exact accumulated result.

The attention output divider starts at bit 31, not bit 63. This is still exact for this datapath because the numerator is bounded by `4096 * 32768 * 16 = 2^31`, but it removes 32 idle divide iterations for each attention output element. The core now runs two attention output channels for a head in parallel, with a one-cycle registered handoff into the divider numerators. This preserves the same per-channel softmax weights, weighted sums, and saturated division while halving the serial attention-value/divide passes.

The LM-head argmax is folded into the existing LM-head projection tiles, so the core no longer burns a separate vocabulary scan before sampling. The RTL sampler caches the per-token categorical weights and pipelines the temperature/index/weight stages; this keeps the same sampled token sequence while removing the long combinational sampler path from timing.

The active core clock is generated from the 50 MHz board clock with a 56.25 MHz PLL (`sys_pll_56_25.v`). The latest fitted slow-corner PLL-core Fmax is about 57.5 MHz with 0.386 ns setup slack at the 56.25 MHz target, so the current build is intentionally close to the timing limit and should not be raised further without another timing run and hardware validation.

The previous programmed build reported `..\run_inference.bat --steps 15 --temperature 0.5 --seed 2 --stream` as `output_text=kamon`, `perf_cycles=12060`, and `tokens_per_sec=23321` using the Python sampler over RTL logits. Its pure RTL sampler path (`--sampler rtl`) used a 24-bit scaled categorical cutoff over the accumulated Q12 softmax weights, instead of the earlier low-16-bit cutoff that biased strongly toward low token IDs. It reported `output_text=aariqaaaaa`, `perf_cycles=12396`, and `tokens_per_sec=45378` for the same seed/config; the 20-sample aggregate was 234 generated tokens, 285856 core cycles, and 46046 tokens/sec.

In ModelSim, the RTL sampler deterministic six-step test now completes in 10,698 core cycles for the same seed/config while preserving the calibrated output tokens `10 4 11 24 13`.

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
