"""Generator for the tutorial notebooks.

Notebook source is kept in plain Python in this file (easy to diff and
review) and rendered to `.ipynb` files alongside it. Re-run after any
edit:

    python3 tutorials/_build.py
"""

from __future__ import annotations

import json
from pathlib import Path

OUT = Path(__file__).parent


def md(*lines: str) -> dict:
    return {
        "cell_type": "markdown",
        "metadata": {},
        "source": [l + "\n" for l in "\n".join(lines).splitlines()],
    }


def code(*lines: str) -> dict:
    return {
        "cell_type": "code",
        "execution_count": None,
        "metadata": {},
        "outputs": [],
        "source": [l + "\n" for l in "\n".join(lines).splitlines()],
    }


def notebook(*cells: dict) -> dict:
    cells_with_ids = []
    for i, c in enumerate(cells):
        # Stable per-position ids satisfy nbformat ≥ 4.5 without random churn.
        cells_with_ids.append({**c, "id": f"c{i:02d}"})
    return {
        "cells": cells_with_ids,
        "metadata": {
            "kernelspec": {
                "display_name": "Python 3",
                "language": "python",
                "name": "python3",
            },
            "language_info": {"name": "python", "version": "3.x"},
        },
        "nbformat": 4,
        "nbformat_minor": 5,
    }


# -----------------------------------------------------------------------------
# 00 — Overview
# -----------------------------------------------------------------------------

n00 = notebook(
    md(
        "# 00 — Overview",
        "",
        "**microgpt on PYNQ-Z2: a char-level GPT baked entirely into PL fabric.**",
        "",
        "This tutorial set walks the workflow end-to-end: from looking at the",
        "weights, to running the AXI wrapper in cocotb, to using the deployed",
        "overlay from Python over `pynq.MMIO`.",
        "",
        "## What is special about this overlay",
        "",
        "Most embedded transformer inference paths trade fabric for DRAM",
        "streaming: weights live off-chip in DDR, and the FPGA runs one matmul",
        "at a time. That gives flexibility at the cost of latency and host",
        "orchestration complexity.",
        "",
        "microgpt takes the opposite extreme: every one of the **4,192 INT16",
        "(Q12) parameters** is hardcoded into LUTRAM / BRAM / constants at",
        "**synthesis time**. There is no DDR, no DMA, no host-side inference",
        "loop. The PS pushes a prompt token through a single AXI4-Lite slave,",
        "the PL runs the full forward pass in fabric, and the PS reads the",
        "generated tokens back through the same slave.",
        "",
        "The exact-arithmetic GPT core is a port of",
        "[`Luthiraa/TALOS-V2`](https://github.com/Luthiraa/TALOS-V2);",
        "see [`UPSTREAM.md`](../UPSTREAM.md) for per-file attribution.",
        "",
        "## The four-stage loop",
        "",
        "```",
        "    .hex weights   →   Vivado build   →   AXI4-Lite slave   →   PS driver",
        "   (hw/ip/*.hex)      (hw/tcl/build       (microgpt_pynq_      (sw/drivers/",
        "                       .tcl)               top.sv)              microgpt.py)",
        "        │                  │                    │                    │",
        "        ▼                  ▼                    ▼                    ▼",
        "   visualise          synthesise          simulate &            generate",
        "   (this notebook,    (Vivado 2024.1)     verify handshakes     tokens",
        "    `01_…`)                                with cocotb           (notebook `03_…`",
        "                                          (notebook `02_…`)      runs on PYNQ)",
        "```",
        "",
        "## Tutorials in this set",
        "",
        "| # | Notebook | Runs locally? | Needs |",
        "|---|---|---|---|",
        "| 00 | This overview | n/a | nothing |",
        "| 01 | `01_explore_weights.ipynb` | yes | `numpy`, `matplotlib` |",
        "| 02 | `02_register_map_and_driver.ipynb` | yes (Python parts) | `numpy` |",
        "| 03 | Cocotb simulation of the AXI wrapper | yes | `cocotb`, `verilator` (or `iverilog`) |",
        "",
        "(03 is documented in [`hw/sim/cocotb/README.md`](../hw/sim/cocotb/README.md) and",
        "run directly with `make` rather than from a notebook.)",
        "",
        "## Reproducing the bitstream",
        "",
        "```bash",
        "source ~/tools/Xilinx/Vivado/2024.1/settings64.sh",
        "rm -rf hw/build && mkdir hw/build",
        "vivado -mode batch -source hw/tcl/build.tcl",
        "```",
        "",
        "Produces `overlays/microgpt.bit` and `.hwh` targeting",
        "`xc7z010clg400-1`. Edit the `part` variable at the top of",
        "`hw/tcl/build.tcl` to retarget for a `xc7z020` PYNQ-Z2 unit.",
        "",
        "## Register map (4 KB AXI4-Lite BAR)",
        "",
        "| Offset | Reg          | RW | Purpose                                          |",
        "|--------|--------------|----|--------------------------------------------------|",
        "| 0x000  | MAGIC        | RO | `'MGRT'` = 0x4D475254                            |",
        "| 0x004  | VERSION      | RO | 0x00020001                                       |",
        "| 0x008  | CMD          | WO | bit0=start pulse, bit1=clear pulse               |",
        "| 0x00C  | STATUS       | RO | ready / busy / done / error / toggle / pos / out_len |",
        "| 0x010  | CONFIG       | RW | temperature Q8.8 (hi 16b), max_gen (next 8b)      |",
        "| 0x014  | SEED         | RW | RNG seed for the categorical sampler             |",
        "| 0x018  | LOGIT_INFO   | RO | argmax token + last-sampled token + top-logit Q12 |",
        "| 0x01C  | BOS          | RO | BOS_TOKEN (= 26)                                 |",
        "| 0x060+ | OUTPUT_MEM   | RO | 16 generated tokens (low byte of each u32)        |",
        "| 0x100+ | LOGITS       | RO | 27 sign-extended Q12 logits                       |",
        "",
        "(Full register map and bitfield notes live in",
        "[`README.md`](../README.md#register-map).)",
        "",
        "## Going further",
        "",
        "- The current build targets `xc7z010clg400-1` to fit the smaller",
        "  PYNQ-Z2 die. The model fits comfortably; a larger model could",
        "  potentially run on the `xc7z020` die without restructuring.",
        "- `sw/notebooks/throughput.ipynb` measures per-token latency on the",
        "  deployed board and shows the ~1.7× speedup from the burst-readback",
        "  + UIO IRQ driver optimisations.",
        "- The categorical sampler uses `xorshift32` for reproducibility:",
        "  `gpt.generate(seed=0xC0FFEE)` returns deterministic text.",
    ),
)


# -----------------------------------------------------------------------------
# 01 — Explore weights
# -----------------------------------------------------------------------------

n01 = notebook(
    md(
        "# 01 — Explore the Q12 weights",
        "",
        "All 4,192 parameters of microgpt are baked into PL fabric at",
        "synthesis time. They live as 16-bit fixed-point (Q12) values in",
        "`hw/ip/*.hex` and are pulled into BRAM/LUTRAM via `$readmemh` in",
        "`microgpt_exact_core_rom_init.svh`.",
        "",
        "This notebook loads the hex files, decodes them as Q12 fixed-point,",
        "and renders each weight tensor so you can see the structure of the",
        "**actual** model that ends up in the gates.",
    ),
    code(
        "from pathlib import Path",
        "import numpy as np",
        "import matplotlib.pyplot as plt",
        "",
        "IP_DIR = Path('../hw/ip').resolve()",
        "",
        "FRAC_BITS = 12   # Q12: 1 sign + 3 integer + 12 fractional bits → range [-8, 8)",
        "",
        "WEIGHTS = [",
        "    ('wte_q12.hex',            'WTE — token embedding',        (27, 16)),",
        "    ('wpe_q12.hex',            'WPE — positional embedding',   (16, 16)),",
        "    ('layer0_attn_wq_q12.hex', 'W_Q — attention query',        (16, 16)),",
        "    ('layer0_attn_wk_q12.hex', 'W_K — attention key',          (16, 16)),",
        "    ('layer0_attn_wv_q12.hex', 'W_V — attention value',        (16, 16)),",
        "    ('layer0_attn_wo_q12.hex', 'W_O — attention output',       (16, 16)),",
        "    ('layer0_mlp_fc1_q12.hex', 'FC1 — MLP up-projection',      (16, 64)),",
        "    ('layer0_mlp_fc2_q12.hex', 'FC2 — MLP down-projection',    (64, 16)),",
        "    ('lm_head_q12.hex',        'LM head — logits projection',  (16, 27)),",
        "]",
    ),
    md(
        "## Decoder",
        "",
        "Each `.hex` line is a 16-bit two's-complement word. We convert to a",
        "Python `int`, take the signed value, and divide by `2**FRAC_BITS` to",
        "get the real-valued weight.",
    ),
    code(
        "def load_q12_hex(path, shape):",
        "    raw = np.array([int(l.strip(), 16) for l in path.read_text().splitlines() if l.strip()], dtype=np.uint16)",
        "    signed = raw.astype(np.int32)",
        "    signed[signed >= 0x8000] -= 0x10000   # two's-complement → signed",
        "    fp = signed.astype(np.float64) / (1 << FRAC_BITS)",
        "    assert fp.size == shape[0] * shape[1], f'{path.name}: expected {shape}, got {fp.size}'",
        "    return fp.reshape(shape)",
        "",
        "tensors = {label: load_q12_hex(IP_DIR / fname, shape) for fname, label, shape in WEIGHTS}",
        "total_params = sum(t.size for t in tensors.values())",
        "print(f'Loaded {len(tensors)} tensors · {total_params} parameters total')",
    ),
    md("## Visualise", "", "Heatmap each tensor with a diverging colormap centred at zero."),
    code(
        "fig, axes = plt.subplots(3, 3, figsize=(12, 11), constrained_layout=True)",
        "for ax, (label, w) in zip(axes.flat, tensors.items()):",
        "    vmax = float(np.abs(w).max()) or 1e-9",
        "    ax.imshow(w, cmap='RdBu_r', vmin=-vmax, vmax=vmax, aspect='auto', interpolation='nearest')",
        "    ax.set_title(f'{label}\\n{w.shape} · |w|≤{vmax:.2f} · σ={w.std():.3f}', fontsize=9)",
        "    ax.set_axis_off()",
        "plt.show()",
    ),
    md(
        "## What you should see",
        "",
        "- **WTE / WPE** have visible per-token / per-position structure.",
        "- **W_Q, W_K, W_V** are 16×16 matrices that the systolic matvec",
        "  tile multiplies the embedded token by, every step.",
        "- **FC1 (16→64)** and **FC2 (64→16)** are the MLP block.",
        "- **LM head (16→27)** projects to vocabulary logits.",
        "",
        "Every one of these values is baked into LUTRAM / BRAM at synth time —",
        "there is no DRAM behind any of it. If you change a weight, you have",
        "to rebuild the bitstream.",
        "",
        "## Sanity check vs the build artefacts",
    ),
    code(
        "# Histogram of the LM-head weights — should be roughly centred",
        "import numpy as np",
        "lm = tensors['LM head — logits projection']",
        "fig, ax = plt.subplots(figsize=(6, 3))",
        "ax.hist(lm.flatten(), bins=40, color='steelblue', edgecolor='black')",
        "ax.set_xlabel('Q12 weight value'); ax.set_ylabel('count')",
        "ax.set_title(f'lm_head weights · n={lm.size} · σ={lm.std():.3f}')",
        "plt.show()",
    ),
)


# -----------------------------------------------------------------------------
# 02 — Register map and driver
# -----------------------------------------------------------------------------

n02 = notebook(
    md(
        "# 02 — Register map and driver",
        "",
        "This notebook is mostly informational: it walks through the",
        "AXI4-Lite register map, decodes a STATUS word, and shows the",
        "driver's hot path. The actual `MicroGPT` driver requires PYNQ +",
        "the bitstream loaded on a real PYNQ-Z2 board, so the generate()",
        "calls are guarded — they will work on the board, not on a dev",
        "laptop.",
    ),
    md(
        "## STATUS register decoder",
        "",
        "The STATUS register at offset `0x00C` packs several fields into a",
        "single 32-bit word. The exact layout lives in",
        "`hw/src/top/microgpt_pynq_top.sv`. Here is a small decoder you can",
        "run on the raw u32 value to see the meaning at a glance.",
    ),
    code(
        "def decode_status(u32):",
        "    return {",
        "        'ready':       bool(u32 & (1 << 0)),",
        "        'busy':        bool(u32 & (1 << 1)),",
        "        'done':        bool(u32 & (1 << 2)),",
        "        'error':       bool(u32 & (1 << 3)),",
        "        'toggle':      bool(u32 & (1 << 4)),",
        "        'direct_mode': bool(u32 & (1 << 5)),",
        "        'out_len':     (u32 >> 16) & 0xFF,",
        "        'pos':         (u32 >> 24) & 0xFF,",
        "    }",
        "",
        "# Example: an idle, post-reset status",
        "decode_status(0x0000_0001)",
    ),
    code(
        "# Example: 'busy and generating, position 3, no errors yet'",
        "decode_status(0x0300_0002)",
    ),
    md(
        "## Driver hot path",
        "",
        "The deployed driver caches a `uint32` view over the MMIO array once",
        "per instance, then does direct burst reads. Here is the relevant",
        "snippet from `sw/drivers/microgpt.py`:",
        "",
        "```python",
        "self._u32 = np.asarray(self.mmio.array, dtype=np.uint32)",
        "...",
        "# tight wait loop, time-check every 4096 spins (not every spin)",
        "spins = 0",
        "while True:",
        "    if self._u32[A_STATUS >> 2] & (1 << ST_DONE_BIT):",
        "        break",
        "    spins += 1",
        "    if spins & 0xFFF == 0 and time.perf_counter() - t0 > self._timeout_s:",
        "        raise TimeoutError('done bit never set')",
        "",
        "# burst-read 16 generated tokens with one numpy view",
        "tokens = (self._u32[A_OUTPUT_MEM >> 2 : (A_OUTPUT_MEM >> 2) + n] & 0xFF).tolist()",
        "```",
        "",
        "The `mmio.array` view + masking pattern is roughly **1.7× faster**",
        "than the obvious `[mmio.read(addr + i*4) for i in range(n)]` loop",
        "because each `mmio.read()` does a fresh attribute lookup and a",
        "Python-level branch. See `sw/notebooks/throughput.ipynb` for the",
        "measurement on the deployed board.",
    ),
    md(
        "## IRQ fast path",
        "",
        "An optional `use_irq=True` flag opens `/dev/uio<n>` (PL fabric IRQ)",
        "and replaces the spin loop with a blocking `os.read`:",
        "",
        "```python",
        "import os, struct",
        "self._uio_fd = os.open(f'/dev/uio{fabric_uio_index}', os.O_RDWR)",
        "...",
        "# enable the IRQ once",
        "os.write(self._uio_fd, struct.pack('<I', 1))",
        "# block until the PL pulses done_irq",
        "_ = os.read(self._uio_fd, 4)",
        "```",
        "",
        "On the deployed board this lands the same latency without burning",
        "a core in the spin loop. The UIO index discovery is the small",
        "`_open_fabric_uio()` helper in the driver (it walks",
        "`/sys/class/uio/*/maps/map0/name` looking for a fabric match).",
    ),
    md(
        "## Generate tokens (board-only)",
        "",
        "If you are running this notebook on the PYNQ-Z2 with the overlay",
        "deployed under `/home/xilinx/jupyter_notebooks/microgpt/`, the",
        "cell below will produce text. On a dev laptop it will raise",
        "(`pynq` is not importable). That is expected.",
    ),
    code(
        "import sys",
        "from pathlib import Path",
        "drivers = (Path('../sw/drivers')).resolve()",
        "if str(drivers) not in sys.path:",
        "    sys.path.insert(0, str(drivers))",
        "",
        "try:",
        "    from microgpt import MicroGPT",
        "    gpt = MicroGPT()",
        "    text, info = gpt.generate(max_tokens=8, temperature=1.0, seed=42)",
        "    print(f'text   = {text!r}')",
        "    print(f'cycles = {info[\"cycles\"]}')",
        "    print(f'tokens = {info[\"tokens\"]}')",
        "except ImportError as e:",
        "    print('Skipped (board-only):', e)",
        "except Exception as e:",
        "    print('Skipped (no overlay loaded):', type(e).__name__, e)",
    ),
)


# -----------------------------------------------------------------------------
# Write
# -----------------------------------------------------------------------------

def main() -> None:
    pairs = [
        ("00_overview.ipynb", n00),
        ("01_explore_weights.ipynb", n01),
        ("02_register_map_and_driver.ipynb", n02),
    ]
    for name, nb in pairs:
        (OUT / name).write_text(json.dumps(nb, indent=1))
        print(f"wrote {name}")


if __name__ == "__main__":
    main()
