# TALOS-V2 — PYNQ-Z2 port

Self-contained Xilinx **PYNQ-Z2** (Zynq-7020 XC7Z020CLG400-1) port of
the [TALOS-V2](https://github.com/Luthiraa/TALOS-V2) "exact" microGPT
SystemVerilog accelerator. The PL keeps the upstream
`microgpt_exact_core` and its sub-blocks **byte-identical**; only the
host bridge, clocking, I/O, and host-side tooling are rewritten for the
Vivado / PYNQ flow. Per-file attribution lives in
[`UPSTREAM.md`](UPSTREAM.md).

The original Intel DE1-SoC flow at the [repository root](..) is
unchanged. Both flows coexist in this repository so users with either
board can build and run microGPT from a single clone.

**Licensing:** files byte-identical to upstream are governed by
Apache-2.0 (`../LICENSE`); original PYNQ-port additions are governed
by BSD 3-Clause (`LICENSE.original`). See `../NOTICE`.

## Directory layout

```
docs/                   Design notes + draft upstream license request
demos/                  Pre-computed weight heatmaps for the portfolio site
hw/
  build/                Vivado project (gitignored output)
  constraints/          pynq_z2.xdc (LD0..LD3 only)
  ip/                   Q12 weight ROMs (.hex) — origin: TALOS-V2
  src/
    core/               Unmodified TALOS-V2 RTL + .svh includes
    top/                microgpt_pynq_top.sv (AXI4-Lite wrapper — new)
  sim/cocotb/           cocotb regression suite for the AXI wrapper
  tcl/                  build.tcl (Vivado batch build — new)
overlays/               microgpt.bit / microgpt.hwh land here
sw/
  drivers/              microgpt.py (pynq.MMIO driver — new)
  notebooks/            demo.ipynb, hardware_advantage.ipynb, throughput.ipynb
  tests/
tutorials/              Three-notebook workflow walkthrough
UPSTREAM.md             Per-file attribution (TALOS-V2 vs this fork)
LICENSE_STATUS.md       Why this repo is not yet open-source-redistributable
```

## Tutorials

Start with [`tutorials/00_overview.ipynb`](tutorials/00_overview.ipynb)
for the workflow loop, then `01_explore_weights.ipynb` to visualise
the Q12 ROMs, then `02_register_map_and_driver.ipynb` for the
AXI4-Lite layout and driver hot path.

## Quick-start

### 1. Build the bitstream

```bash
# From repo root
vivado -mode batch -source hw/tcl/build.tcl
```

This creates the Vivado project under `hw/build/`, runs synthesis and
implementation, and copies `microgpt.bit` + `microgpt.hwh` into
`overlays/`.

### 2. Deploy to the PYNQ-Z2

```bash
scp overlays/microgpt.bit overlays/microgpt.hwh \
    xilinx@<board-ip>:/home/xilinx/pynq/overlays/microgpt/
scp -r sw/drivers sw/notebooks \
    xilinx@<board-ip>:/home/xilinx/jupyter_notebooks/microgpt/
```

### 3. Run on the board

Open Jupyter (`http://<board-ip>:9090`) and run
`sw/notebooks/demo.ipynb`, or from a Python shell:

```python
from microgpt import MicroGPT
gpt = MicroGPT()
text, info = gpt.generate(max_tokens=8, temperature=1.0, seed=42)
print(text, info["cycles"])
```

## Register map (AXI4-Lite slave at 0x4000_0000, 4 KB)

| Offset  | RW | Field                                                         |
|--------:|:--:|:--------------------------------------------------------------|
| 0x000   | RO | Magic = `0x4D475254` ("MGRT")                                 |
| 0x004   | RO | Version = `0x00020001`                                        |
| 0x008   | WO | bit0 = start pulse, bit1 = clear pulse                        |
| 0x00C   | RO | Status `{pos, out_len, 0, 0, direct_mode, toggle, error, done, busy, ready}` |
| 0x010   | RW | Config `{temp_q8_8[31:16], max_gen[15:8], 0[7:0]}`            |
| 0x014   | RW | RNG seed                                                      |
| 0x018   | RO | `{top_logit_q12[31:16], argmax_token[15:8], last_token[7:0]}` |
| 0x01C   | RO | BOS_TOKEN (`26`)                                              |
| 0x020   | RW | Step config `{0, step_token, step_pos, step_clear, direct_mode}` |
| 0x024   | WO | Step trigger pulse (bit0)                                     |
| 0x028   | RO | heartbeat_reg snapshot (debug; zero-padded to 32b)            |
| 0x060.. | RO | `output_mem[0..15]` -- 16 generated tokens                    |
| 0x0D8   | RO | perf_cycles                                                   |
| 0x0DC   | RO | tokens_per_sec                                                |
| 0x100.. | RO | 27 sign-extended logits (Q12)                                 |

PL LEDs LD0..LD3 expose `{heartbeat, busy, done, error}` (heartbeat moved
to LD0 so it stays visible even on boards where LD3/M14 has a physical
fault, as observed on the deployed PYNQ-Z2 unit).

## Avalon-MM -> AXI4-Lite translation summary

| DE1-SoC (Avalon-MM)                                | PYNQ-Z2 (AXI4-Lite)                              |
|----------------------------------------------------|--------------------------------------------------|
| `jtag_microgpt_bridge` master + `waitrequest`/`readdatavalid` handshakes | Standard AXI4-Lite slave on PS GP0 (`s_axi_*`).  |
| 50 MHz `CLOCK_50` host domain + 56.25 MHz core PLL | Single domain `s_axi_aclk = FCLK_CLK0 = 50 MHz`. |
| Toggle-bit triggers (`host_start_toggle_50` etc.) crossed via 2-FF synchronizers | 1-cycle `start_pulse` / `clear_pulse` / `step_pulse` decoded inline. |
| `host_toggle_reg` flips on every JTAG read or write | `host_toggle_reg` flips on every successful AXI read or write. |
| WSTRB / byte enables driven by JTAG bridge (4'b1111) | `s_axi_wstrb` accepted but ignored; aligned 32-bit writes only. |
| Resets: `~SW[1] && pll_locked`                      | `s_axi_aresetn` from `proc_sys_reset` driven by `FCLK_RESET0_N`. |
| Outputs: 10x LEDR + 6x HEX                         | 4x PL LEDs (LD0..LD3): `heartbeat`, `busy`, `done`, `error`. |
| Weights via `$readmemh("generated/...hex", ...)`    | Weights live in `hw/ip/`; build.tcl adds it to `INCLUDE_DIRS` and `rom_init.svh` references bare filenames. |

## Notes

- The unmodified core RTL lives in `hw/src/core/` and includes
  `microgpt_exact_core_params.svh`, `microgpt_exact_core_math.svh`,
  and `microgpt_exact_core_rom_init.svh`. Parameters (e.g. `EMBED_DIM`,
  `VOCAB_SIZE`, `FRAC_BITS`) are unchanged from the DE1 build.
- The build script targets `xc7z010clg400-1`; if your PYNQ-Z2 carries
  the larger XC7Z020 die, edit the `part` variable at the top of
  `hw/tcl/build.tcl`.
- All RTL uses 4-space indentation, no tabs.


## Run Build:
```bash
mkdir -p hw/build
vivado -mode batch -source hw/tcl/build.tcl \
  -log hw/build/vivado_build.log \
  -journal hw/build/vivado_build.jou \
  2>&1 | tee hw/build/build_console.log
```

