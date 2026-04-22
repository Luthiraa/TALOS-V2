# Working System RTL Full

## Status

This is the current working DE1-SoC RTL microgpt system.

It has been rebuilt with the trained model weights from:

```text
rtl/microgpt/weights_only.npy
```

Those weights were exported into Q4.12 ROM hex files in:

```text
rtl/generated/
```

The Quartus project compiled successfully and produced:

```text
rtl/de1_soc_microgpt_rtl.sof
```

The current RTL top level also includes the JTAG-to-Avalon bridge from:

```text
hls/v2/jtag_microgpt_bridge/synthesis/jtag_microgpt_bridge.qip
```

The host-side RTL JTAG runner is:

```text
rtl/run_jtag_inference.bat
rtl/host/jtag_rtl_infer.py
rtl/host/system_console_rtl_infer.tcl
```

## Important Caveat

This is not a bit-exact replica of Karpathy's Python `microgpt.py`.

It is an architecture-faithful RTL inference implementation of the same model topology, but it does not produce numerically identical results to the Python implementation.

The differences are:

- Python uses floating-point math; this RTL uses Q4.12 fixed-point weights and activations.
- Python uses `math.exp` and true division in softmax; this RTL uses lookup/approximate exponential weights and fixed hardware division where retained.
- Python sampling uses `random.choices`; this RTL uses a small xorshift RNG and hardware-friendly sampling logic.
- Temperature scaling is approximated with shift buckets rather than exact floating-point division.
- Rounding, saturation, overflow, and operation ordering differ from Python.
- The DE1-SoC fabric core is clock-divided to close timing because the exact topology has long normalization and softmax paths.

So the correct description is:

```text
Same microgpt architecture, trained weights loaded, running inference on FPGA fabric, hardware-approximated numerics.
```

The incorrect description would be:

```text
Bit-exact Python microgpt running on FPGA.
```

## Architecture Implemented

The RTL core implements the microgpt inference topology:

1. Token embedding lookup: `wte[token_id]`
2. Position embedding lookup: `wpe[pos_id]`
3. Embedding add: `x = wte + wpe`
4. Initial RMSNorm
5. Transformer layer 0 attention block
6. Attention pre-RMSNorm
7. Query projection: `attn_wq`
8. Key projection: `attn_wk`
9. Value projection: `attn_wv`
10. KV cache write for the current position
11. Four-head causal attention over positions `0..pos_id`
12. Attention output projection: `attn_wo`
13. Attention residual add
14. MLP pre-RMSNorm
15. MLP first projection: `mlp_fc1`
16. ReLU activation
17. MLP second projection: `mlp_fc2`
18. MLP residual add
19. Final logits projection: `lm_head`
20. Token sampling

Model dimensions:

```text
vocab_size = 27
block_size = 16
n_embd     = 16
n_head     = 4
head_dim   = 4
n_layer    = 1
mlp_dim    = 64
```

## Compute Structure

The active microgpt core uses direct matrix-vector dot products inside the core FSM. It is not a systolic array.

Projection stages walk rows and columns with one accumulator:

- `ST_Q_LINEAR`: query projection
- `ST_K_LINEAR`: key projection
- `ST_V_LINEAR`: value projection
- `ST_ATTN_WO`: attention output projection
- `ST_FC1`: MLP first projection
- `ST_FC2`: MLP second projection
- `ST_LM_HEAD`: final logits projection

The `matrixmul_unit.sv` and `processing_element.sv` files are separate matrix-multiply test hardware. They are not instantiated by the active `de1_soc_microgpt_rtl.sv` top level.

## Board Controls

- `SW0`: enable
- `SW1`: reset, active high
- JTAG host control register: start or restart generation

`KEY0` and `KEY1` are no longer used by the active RTL top level.

## LEDs

- `LEDR0`: ready while enabled and idle
- `LEDR1`: busy while generating
- `LEDR2`: generation done
- `LEDR3`: host JTAG activity
- `LEDR4`: reset deasserted
- `LEDR5`: enable switch state
- `LEDR6`: busy blink
- `LEDR7..9`: low bits of the last sampled token

## HEX Displays

- `HEX0..1`: last sampled token id
- `HEX2..3`: generated token count
- `HEX4`: top-level state
- `HEX5`: switch state

## Build Commands

From:

```text
C:\Users\luthi\Documents\TALOS-V2\rtl
```

Export weights:

```bat
python .\tools\export_weights.py --weights .\microgpt\weights_only.npy --outdir .\generated
```

Compile:

```bat
.\compile_only.bat
```

Program:

```bat
.\program_fpga.bat
```

Build and program:

```bat
.\run_de1soc.bat
```

Run inference over JTAG:

```bat
.\run_jtag_inference.bat --steps 15 --temperature 0.5 --seed 2 --stream
```

The generated name appears first as plain text and again in the packet summary as `output_text=...`.

The C launcher in the repository root sends the BOS-start command through the same JTAG/MMIO bridge:

```bat
clang -Wall -Wextra main.c -o microgpt_bos_start.exe
.\microgpt_bos_start.exe --steps 15 --temperature 0.5 --seed 2
```

The fake `--karpathy-reference`/`KREF` token stream was removed. The JTAG commands now report only the active RTL inference core output.

## Latest Build Result

The trained-weight RTL build completed successfully with Quartus Prime 18.1 Lite.

Fit summary:

```text
Device: 5CSEMA5F31C6
Logic utilization: 15,091 / 32,070 ALMs (47%)
Registers: 13,305
Pins: 55 / 457
Block memory bits: 512 / 4,065,280
DSP blocks: 13 / 87
Timing: positive setup/hold slack reported for CLOCK_50_IN, CORE_CLK, and altera_reserved_tck in the latest run
```

The design uses a divided core clock:

```text
CORE_CLK = CLOCK_50 / 128
```

This is intentionally slow, but it allows the current hardware implementation to meet timing.

## Verification Added

Two verification helpers were added:

```text
rtl/tools/karpathy_exact_reference.py
rtl/tb_microgpt_core.sv
```

The exact Python reference command:

```bat
python .\tools\karpathy_exact_reference.py --count 20 --temperature 0.5
```

This reproduces the Karpathy-style trained-weight output:

```text
sample  1: kamon
sample  2: ann
sample  3: karai
```

The ModelSim deterministic RTL test compiles and runs with:

```bat
vlib work_microgpt_core
vlog -nolock -sv -work work_microgpt_core microgpt_exact_core.sv tb_microgpt_core.sv
vsim -c work_microgpt_core.tb_microgpt_core -do "run -all; quit -f"
```

Observed result:

```text
RTL deterministic output tokens: 12
Karpathy exact first sample tokens are 10 0 12 14 13 26 (kamon).
PASS: RTL core is deterministic for repeated seed/config.
```

This means the current RTL is deterministic, but it is not exact to Karpathy Python. Exact matching would require changing the arithmetic and sampler behavior, not the transformer topology.

Preloading Python/Colab random numbers into memory can make the sampling thresholds deterministic, but it does not by itself make the probability distribution identical. Exact distribution matching also requires the RTL to expose or compute the same logits and softmax probabilities as Python for each generated position.

## JTAG/MMIO Changes

The RTL top-level JTAG register path currently provides:

- ID register: `0x4D475254`
- version register: `0x00020000`
- control register bits for host start and host clear
- configuration register for max generation length and temperature
- seed register
- status register with ready, busy, done, error, host activity, output length, and position
- BOS token register at `0x1C`
- output token memory window at `0x60`
- performance cycle and token-rate counters

Two bridge-facing bugs were fixed:

- status register packing is now 32 bits, so the host decodes `out_len` correctly
- output token reads now index `output_mem` with the full Avalon word address offset
