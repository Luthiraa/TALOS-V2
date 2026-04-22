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

## Board Controls

- `SW0`: enable
- `SW1`: reset, active high
- `KEY0`: start or restart generation

## LEDs

- `LEDR0`: ready while enabled and idle
- `LEDR1`: busy while generating
- `LEDR2`: generation done
- `LEDR3`: one-cycle core done pulse
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

## Latest Build Result

The trained-weight RTL build completed successfully with Quartus Prime 18.1 Lite.

Fit summary:

```text
Device: 5CSEMA5F31C6
Logic utilization: about 40% ALMs
DSP blocks: 11 / 87
Timing: closed on CLOCK_50_IN and divided CORE_CLK
```

The design uses a divided core clock:

```text
CORE_CLK = CLOCK_50 / 128
```

This is intentionally slow, but it allows the current hardware implementation to meet timing.

