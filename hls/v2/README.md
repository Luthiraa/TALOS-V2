# DE1-SoC microgpt JTAG Inference

This workspace targets Karpathy's 4,192-parameter microgpt model on the DE1-SoC. The intended data path is:

`PC -> JTAG Blaster -> JTAG-to-Avalon master -> FPGA MMIO wrapper -> HLS microgpt token-step core -> FPGA MMIO wrapper -> JTAG Blaster -> PC`

The HPS is not required in this baseline. All token generation runs in FPGA fabric once the host writes the prompt and starts the engine.

## Verified locally

- `model_weights.npy` is parsed as the exact 4,192-parameter microgpt layout.
- `tools/export_microgpt_weights.py` emits `generated/microgpt_model.h` and `generated/model_manifest.json`.
- `tools/reference_microgpt.py` runs both float and quantized inference and matches the generated tokens on tested prompts.
- `qsys/create_jtag_microgpt_bridge.tcl` generates a Quartus 18.1 JTAG master bridge with exported Avalon-MM master ports.

## Not yet fully closed

- Intel HLS 18.1 accepts the kernel front end and enters optimization, but full RTL/component emission was not completed in the time budget.
- Quartus full-chip compile and on-board validation have not been run from this workspace.

## Model and quantization

- Model: 1 layer, 4 heads, 16-d embedding, 64-d MLP, 16-token context, 27-token vocabulary.
- Tokenization: lowercase `a-z` plus BOS/EOS token `^` at id `26`.
- Embeddings: int16 `Q5.11`.
- Dense weights: int8 symmetric per-output-row plus `Q0.16` scale.
- Activations/KV cache: int16 `Q5.11`.
- Attention softmax and RMS normalization: scalar float-style arithmetic in HLS.

Packed model footprint from `generated/model_manifest.json`: 5,222 bytes.

## Register map

- `0x00` ID, expected `0x4D475054`
- `0x04` version, expected `0x00010000`
- `0x08` control
  - bit 0: start
  - bit 1: clear
  - bit 2: clear done latch
- `0x0C` status
  - bit 0 idle
  - bit 1 busy
  - bit 2 done
  - bit 3 error
  - bit 4 host activity toggle
  - bit 5 `SW0` enable
  - bit 6 `SW1` sample mode
  - bits `15:8` prompt length
  - bits `23:16` output length
  - bits `31:24` current position
- `0x10` config
  - bits `7:0` prompt length
  - bits `15:8` max generated tokens
  - bits `31:16` temperature `Q8.8`
- `0x14` RNG seed
- `0x18` last result: sampled token, argmax token, top1 logit
- `0x1C` last result: top2 token, top2 logit
- `0x20..0x5C` prompt token RAM, 16 x 32-bit words, low byte used
- `0x60..0x9C` output token RAM, 16 x 32-bit words, low byte used
- `0xA0..0xD4` last logits, 7 x 64-bit packs exposed as 14 x 32-bit words

## Board controls

- `SW0`: accelerator enable gate
- `SW1`: greedy/sample mode select
- `KEY0`: manual start
- `KEY1`: manual clear/reset

LEDs:

- `LEDR0`: idle
- `LEDR1`: busy
- `LEDR2`: done
- `LEDR3`: host activity
- `LEDR4`: error
- `LEDR5`: `SW0`
- `LEDR6`: `SW1`

## Build order

1. `run_hls_build.bat`
2. `compile_only.bat`
3. `generate_rbf.bat`
4. `program_fpga.bat`

Single command:

- `rebuild_and_program.bat`

## Host run

Use System Console over JTAG:

```bat
run_inference.bat --prompt emma --steps 8 --temperature 1.0 --seed 1
```

Stream tokens to the PC as they are produced:

```bat
run_inference.bat --prompt emma --steps 8 --stream
```

Interactive PC input loop with continuous output:

```bat
run_inference.bat
```

Notes:

- Leave `SW0` on to enable the accelerator.
- `SW1` is not used by the current token-step RTL.
- Empty input in interactive mode reruns the previous prompt.

Direct software-only reference:

```bat
python tools\reference_microgpt.py --prompt emma --steps 8
```

## Performance expectation

This tiny model can plausibly approach or exceed 50k tok/s only if the HLS kernel closes at a healthy clock and the on-board generation loop stays entirely on fabric, which this design does. The practical range to expect before place-and-route is roughly 30k to 80k tok/s for the core alone. JTAG is not on the per-token critical path because prompt upload and output readback happen once per sequence, not once per token.

The main risks are:

- HLS over-unrolling raising area or compile time
- attention softmax and normalization reducing Fmax
- wrapper/control timing around the exported HLS core
- Quartus fit once the fully generated HLS component is available

## Files

- `tools/export_microgpt_weights.py`: turns `model_weights.npy` into FPGA header + manifest
- `tools/reference_microgpt.py`: float + quantized reference runner
- `src/microgpt_step.cpp`: HLS token-step core
- `rtl/microgpt_mmio.v`: Avalon-MM wrapper, prompt/output buffers, board controls
- `rtl/de1_soc_microgpt.v`: DE1-SoC top level
- `qsys/create_jtag_microgpt_bridge.tcl`: Platform Designer JTAG bridge generator
- `host/system_console_infer.tcl`: JTAG System Console transaction script
- `host/jtag_infer.py`: host wrapper that encodes prompt and runs the Tcl script
