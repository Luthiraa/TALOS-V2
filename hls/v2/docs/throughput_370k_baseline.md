# DE1-SoC MicroGPT Throughput Baseline

This note records the optimization state that currently gives the best verified hardware throughput in this workspace, along with the failed trials that were tested afterward.

## Current Best Verified Result

Hardware benchmark command:

```powershell
.\run_inference.bat --count 100 --steps 15 --temperature 0.5
```

Measured result on the board:

```text
Tokens generated : 539
Board cycles     : 72732
Core time        : 0.001455 s
Throughput       : 370538.42 tok/s
Latency          : 2.70 us/tok
```

This is the current known-good baseline.

## Reference Starting Point

The earliest throughput-tagged commit on this branch is:

```text
8bb7f8d  52k tk benchmark
```

That appears to be the first commit in this line of work with a measured token-throughput checkpoint. If a different `60k` commit was intended, update this note to point at that exact commit instead.

## What Changed Since The 52k Commit

Git range used for this comparison:

```text
8bb7f8d..afed59c
```

High-level diff summary for `hls/v2` over that range:

```text
18 files changed
690 insertions
41 deletions
```

The important point is that most of the throughput gain from `~52k` to `~370k` came from `microgpt_step.cpp`, not from a large change in the MMIO shell.

### Commit Sequence After 52k

```text
8bb7f8d  52k tk benchmark
e63fdcf  further optimizations
343af92  260k tk/s!
2473e09  benchmarking
49ac8bd  350k thru
659f541  files for 350k
afed59c  370k
```

### What Stayed The Same

These parts were already present at the `52k` checkpoint and are not the main reason the design reached `370k`:

- MMIO state machine structure in `microgpt_mmio.v`
  - `ST_IDLE`
  - `ST_START`
  - `ST_WAIT`
  - `ST_EVAL`
- on-board cycle counter in `perf_cycles_reg`
- host-side benchmark reporting in `jtag_infer.py`
- JTAG/System Console measurement path
- one-token-at-a-time generation flow

So the main improvement path was not a rewrite of the shell around the kernel. It was mostly a reshaping of the HLS kernel datapath and loops.

### Kernel Changes From 52k To 370k

The main kernel file in both points is:

- [microgpt_step.cpp](C:/Users/luthi/Documents/TALOS-V2/hls/v2/src/microgpt_step.cpp)

The `52k` checkpoint used a simpler kernel:

- no explicit `DOT_LANES`
- no explicit `HIDDEN_ROW_PAR`
- no explicit `LOGIT_ROW_PAR`
- plain nested loops for both hidden and logits matvecs
- no explicit `#pragma ii 1` on the row loops
- no lane-partitioned dot-product helper
- simpler temperature branching inside the sampler loop

The current `370k` baseline changed that kernel in the following ways:

1. Added a manually lane-partitioned dot product.
   - `DOT_LANES = 4`
   - introduced `dot_i8_i16()`
   - split the inner product into four parallel accumulators

2. Added explicit row-parallel structure.
   - `HIDDEN_ROW_PAR = 1`
   - `LOGIT_ROW_PAR = 2`
   - hidden and logits loops now iterate by row groups instead of simple scalar rows

3. Added explicit HLS loop directives.
   - `#pragma unroll` on fixed-size loops
   - `#pragma ii 1` on hidden and logits outer loops
   - this is a major part of the actual performance increase

4. Reshaped the logits pass.
   - grouped row processing by `LOGIT_ROW_PAR`
   - still computes top-1 / top-2 during the logits pass
   - improved the synthesized datapath relative to the original scalar loop form

5. Cleaned up sampling control.
   - replaced repeated temperature branches inside the 4-sample loop with a precomputed `sample_shift`
   - reduced control overhead in the sampler body

6. Added explicit padding support for the logits scratch array.
   - `LOGIT_SLOTS`
   - avoids synthesis warnings on tail handling
   - this is mostly a cleanup/safety improvement, not the original source of the `52k -> 370k` jump

### Non-Kernel Changes Since 52k

Other useful changes in the range:

1. Added offline throughput-model tooling.
   - [hls_kernel_sim.py](C:/Users/luthi/Documents/TALOS-V2/hls/v2/tools/hls_kernel_sim.py)
   - used to estimate cycle cost for `DOT_LANES`, `HIDDEN_ROW_PAR`, and `LOGIT_ROW_PAR`

2. Added GPU/offline benchmarking support.
   - [gpu_benchmark.py](C:/Users/luthi/Documents/TALOS-V2/hls/v2/tools/gpu_benchmark.py)
   - useful for comparison, but not part of the on-board `370k` result itself

3. Regenerated bridge/system integration files several times.
   - `jtag_microgpt_bridge.*`
   - these tracked Qsys/HLS regeneration as the kernel changed

4. Added more README guidance.
   - [README.md](C:/Users/luthi/Documents/TALOS-V2/hls/v2/README.md)

### Practical Interpretation

From the first benchmark commit to the current baseline, the architecture did not fundamentally change from “stateful one-token HLS step wrapped by an MMIO controller.” The big change was that the HLS kernel stopped looking like a straightforward scalar C loop nest and started looking like a deliberately lane-structured, pipelined datapath.

That is the main reason the design moved from the early `~52k tok/s` checkpoint to the current verified `370538.42 tok/s`.

## What Was Done To Reach This

The active kernel is a compact quantized one-token-at-a-time MicroGPT step engine implemented in HLS and wrapped by an MMIO control block.

The important optimization choices that are part of the current `~370k tok/s` baseline are:

1. The token step was reduced to a small fixed-size datapath.
   - `EMBED_DIM = 16`
   - `VOCAB_SIZE = 27`
   - No batch dimension
   - One token evaluated at a time

2. The core dot product was manually lane-partitioned.
   - `DOT_LANES = 4`
   - `dot_i8_i16()` accumulates four independent MAC lanes and then reduces them.
   - This is the main inner-product structure used for both the hidden projection and the logits projection.

3. The HLS loops were explicitly shaped for pipelining and unrolling.
   - `#pragma unroll` is used on the lane loops and several fixed-size loops.
   - `#pragma ii 1` is used on the hidden-row loop and the logit-row loop.

4. The hidden-state update stayed conservative.
   - `HIDDEN_ROW_PAR = 1`
   - Hidden rows are computed one at a time through the pipelined dot-product structure.
   - Increasing this looked attractive in the cycle model, but it was worse on real hardware.

5. The logits path uses light row parallelism.
   - `LOGIT_ROW_PAR = 2`
   - Two logit rows are processed per outer iteration.
   - This is the best verified setting so far.

6. The logit buffer tail is padded.
   - `LOGIT_SLOTS = ceil(VOCAB_SIZE / LOGIT_ROW_PAR) * LOGIT_ROW_PAR`
   - This avoids HLS out-of-bounds warnings on the final partially filled unrolled group.
   - This cleanup did not change the verified good architecture choice; it just made the implementation cleaner and safer for synthesis.

7. Sampling stays in hardware.
   - The kernel computes top-1 / top-2 and packed logits.
   - RNG uses `xorshift32`.
   - Temperature handling is done with simple shift rules.
   - A small LUT approximates the acceptance weight for sampled alternatives.

## Current Architecture

## HLS Kernel

Active file:

- [microgpt_step.cpp](C:/Users/luthi/Documents/TALOS-V2/hls/v2/src/microgpt_step.cpp)

Current constants:

```cpp
static const int EMBED_DIM = 16;
static const int VOCAB_SIZE = 27;
static const int DOT_LANES = 4;
static const int HIDDEN_ROW_PAR = 1;
static const int LOGIT_ROW_PAR = 2;
```

Per-token flow inside the kernel:

1. Build `x_vec` from token embedding, positional embedding, and half-scaled previous hidden state.
2. Compute `hidden_next` using `g_wq_q[row] dot x_vec`.
3. Compute logits using `g_lm_q[row] dot x_vec`.
4. Track `best_idx` and `second_idx` during the logits pass.
5. Run the lightweight hardware sampler.
6. Commit `hidden_next` into `hidden_state`.
7. Return sampled token, argmax token, RNG state, top logits, and packed logits.

Important architectural properties:

- The hidden state is stored as a static array inside the HLS component.
- The kernel is stateful across tokens.
- `clear_cache` resets the hidden state at the start of a new sample.
- The design is inference-only and optimized around short sampled-name generation.

## MMIO / Control Shell

Active file:

- [microgpt_mmio.v](C:/Users/luthi/Documents/TALOS-V2/hls/v2/rtl/microgpt_mmio.v)

Current control structure:

- `ST_IDLE`
- `ST_START`
- `ST_WAIT`
- `ST_EVAL`

What the MMIO shell does:

- Holds prompt memory and output memory.
- Starts the HLS step kernel.
- Tracks generation position and output length.
- Stores packed logits and latest score metadata.
- Exposes a performance counter at register `0xD8` via `perf_cycles_reg`.

The hardware benchmark reported by the host script comes from this cycle counter.

## Host / Measurement Path

Relevant files:

- [jtag_infer.py](C:/Users/luthi/Documents/TALOS-V2/hls/v2/host/jtag_infer.py)
- [system_console_infer.tcl](C:/Users/luthi/Documents/TALOS-V2/hls/v2/host/system_console_infer.tcl)

Measurement method:

1. The host launches `system-console`.
2. It requests generation over the MMIO/JTAG bridge.
3. It streams generated tokens to the PC console.
4. It reads `STREAM_CYCLES` from the board.
5. It computes throughput as:

```text
tokens_generated / (board_cycles / 50_000_000)
```

This means the reported `tok/s` value is based on on-board cycle count, not PC-side print speed.

## Variants Tested After 370k

Two incremental hardware variants were built, programmed, and benchmarked. Both were worse than the baseline.

### Trial 1: Increase Hidden Row Parallelism

Change:

```cpp
HIDDEN_ROW_PAR = 2
LOGIT_ROW_PAR = 2
DOT_LANES = 4
```

Measured result:

```text
Throughput : 269053.37 tok/s
Latency    : 3.72 us/tok
```

Conclusion:

- Worse than baseline by a large margin.
- The cycle model overpredicted this change.
- More hidden-row parallelism did not translate into better full-design hardware throughput.

### Trial 2: Increase Logit Row Parallelism

Change:

```cpp
HIDDEN_ROW_PAR = 1
LOGIT_ROW_PAR = 3
DOT_LANES = 4
```

Measured result:

```text
Throughput : 264008.62 tok/s
Latency    : 3.79 us/tok
```

Conclusion:

- Also worse than baseline by a large margin.
- Increasing row parallelism in the logits path regressed the synthesized design.

## Final Status

The current checked-in and revalidated architecture is:

```text
DOT_LANES      = 4
HIDDEN_ROW_PAR = 1
LOGIT_ROW_PAR  = 2
```

Verified hardware throughput:

```text
370538.42 tok/s
```

## Practical Takeaway

The obvious next-row-parallelism knobs have already been tested on hardware and both regressed performance. The next optimization pass should not start by raising `HIDDEN_ROW_PAR` or `LOGIT_ROW_PAR` again.

The next likely areas to investigate are:

- control/state overhead between `ST_START`, `ST_WAIT`, and `ST_EVAL`
- HLS-generated scheduling overhead around the current pipelined loops
- dot-product structure changes that preserve the good `4x1x2` macro shape
- ROM / memory access structure in the synthesized datapath
