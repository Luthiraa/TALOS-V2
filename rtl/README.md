# DE1-SoC RTL microgpt

This directory contains a standalone RTL implementation of the microgpt inference path for the DE1-SoC.

## Current status

- The active top level is `de1_soc_microgpt_rtl.sv`.
- The microgpt core is in `microgpt_exact_core.sv`.
- The JTAG-to-Avalon bridge is included through `../hls/v2/jtag_microgpt_bridge/synthesis/jtag_microgpt_bridge.qip`.
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
compile_only.bat
program_fpga.bat
```

`run_de1soc.bat` runs both steps.

The core uses Q4.12 fixed-point weights exported from the trained RTL weights by:

```bat
python tools\export_weights.py --weights microgpt\weights_only.npy --outdir generated
```

## Run inference over JTAG

From this directory in PowerShell:

```powershell
.\run_jtag_inference.bat --steps 15 --temperature 0.5 --seed 2 --stream
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

The active core clock is generated from the 50 MHz board clock with a divide-by-4 register clock, so the active core runs at about 12.5 MHz. The latest fitted slow-corner direct-core Fmax is about 13.22 MHz, so `/4` is the highest simple divider that still closes timing with margin on the current board build.

With the current programmed build, `.\run_jtag_inference.bat --steps 15 --temperature 0.5 --seed 2 --stream` reports `output_text=m`, `perf_cycles=5286`, and `tokens_per_sec=2365`.

The separate `matrixmul_unit.sv` and `processing_element.sv` files are a standalone matrix-multiply test path and are not instantiated by `de1_soc_microgpt_rtl.sv`.

## Determinism and exactness

The RTL is deterministic for the same seed and settings. `tb_microgpt_core.sv` verifies that repeated runs with the same seed produce the same RTL token sequence in ModelSim.

The RTL does not currently match Karpathy's Python `microgpt.py` bit-for-bit. The Python reference uses floating-point math, exact `math.exp` softmax, and Python `random.choices`; this RTL uses Q4.12 fixed-point arithmetic, approximate exponential weights, saturation/rounding, and an xorshift32 sampler.

The fake hardware-resident Karpathy reference stream was removed. `run_jtag_inference.bat` now only reports the active RTL inference core output.

To make the probability distribution match Karpathy exactly, the hardware path needs the same numerical logits-to-probability behavior as Python: equivalent precision/order for RMSNorm, matvec, attention softmax, MLP, final softmax/temperature, and Python-compatible sampling thresholds. Preloading random numbers alone only fixes the sampler; it does not make the probability distribution match if the logits and softmax differ.

Use this command to show the exact Karpathy reference output from the trained RTL weights:

```powershell
python .\tools\karpathy_exact_reference.py --count 20 --temperature 0.5
```
