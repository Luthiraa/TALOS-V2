# Tutorials

Three short notebooks that walk the full microgpt-on-PYNQ workflow.
Read them in order; each is independent enough that you can also jump
to whichever one you need.

| # | Notebook | Runs locally? | Needs |
|---|---|---|---|
| 00 | [`00_overview.ipynb`](00_overview.ipynb) | n/a (markdown-only) | nothing |
| 01 | [`01_explore_weights.ipynb`](01_explore_weights.ipynb) | yes | `numpy`, `matplotlib` |
| 02 | [`02_register_map_and_driver.ipynb`](02_register_map_and_driver.ipynb) | yes (Python parts) — board-only for `generate()` | `numpy` |

The cocotb regression suite for the AXI4-Lite wrapper is run with
`make` rather than from a notebook; see
[`hw/sim/cocotb/README.md`](../hw/sim/cocotb/README.md).

## Editing

Notebook source is kept in plain Python in `_build.py` (much easier to
diff and review than `.ipynb` JSON). After editing, regenerate:

```bash
python3 tutorials/_build.py
```

This rewrites every `.ipynb` from scratch. Do not hand-edit the
`.ipynb` files in place; your changes will be lost on the next
regeneration.

## What each notebook is for

- **`00_overview.ipynb`** — Why microgpt is interesting (everything in
  fabric, no DRAM), the four-stage workflow loop, the AXI4-Lite
  register map, and where to look in the repo for each stage.
- **`01_explore_weights.ipynb`** — Decode the 9 Q12 weight ROMs in
  `hw/ip/*.hex` and visualise them as heatmaps + a histogram. Runs
  anywhere with `numpy` and `matplotlib`.
- **`02_register_map_and_driver.ipynb`** — Walk through the AXI4-Lite
  layout, decode a STATUS word, explain the driver hot path (cached
  `mmio.array` + burst readback) and the IRQ fast path. The final
  cell calls `MicroGPT.generate()` if you are running on the board.
