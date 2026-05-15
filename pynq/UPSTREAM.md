# Upstream attribution

This repository is a **port** of the SystemVerilog inference core from
[`Luthiraa/TALOS-V2`](https://github.com/Luthiraa/TALOS-V2), an RTL
implementation of a Karpathy-style microGPT for the Intel DE1-SoC
(Cyclone V), to the **Xilinx PYNQ-Z2** (Zynq-7020 XC7Z020CLG400-1).

All credit for the inference core RTL and the underlying numerical
design (Q12 fixed-point, systolic matvec tile, processing-element
array, RMS-norm + saturating-divider engines, categorical sampler)
belongs to the upstream author(s) of TALOS-V2.

This fork's contribution is the *host-side bridge to PYNQ*: an
AXI4-Lite slave wrapper, a Vivado batch build, a cocotb regression
suite for the wrapper, and a Python (`pynq.MMIO` + UIO IRQ) driver.

## Per-subtree origin

| Subtree in this repo                | Origin                  | Modifications                                                                                                                              |
| ----------------------------------- | ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `hw/src/core/*.sv` (7 files)        | `Luthiraa/TALOS-V2/rtl/src/`         | **Unmodified, byte-identical** to upstream.                                                                                                |
| `hw/src/core/include/microgpt_exact_core_math.svh` | `Luthiraa/TALOS-V2/rtl/src/include/` | **Unmodified, byte-identical** to upstream.                                                                                                |
| `hw/src/core/include/microgpt_exact_core_params.svh` | `Luthiraa/TALOS-V2/rtl/src/include/` | **Unmodified, byte-identical** to upstream.                                                                                                |
| `hw/src/core/include/microgpt_exact_core_rom_init.svh` | `Luthiraa/TALOS-V2/rtl/src/include/` | Modified: paths updated for Vivado `INCLUDE_DIRS` and bare-filename `$readmemh` references.                                                |
| `hw/ip/*.hex` (9 weight ROMs)       | `Luthiraa/TALOS-V2/rtl/generated/`   | Unmodified Q12 fixed-point exports of the upstream-trained microGPT weights.                                                               |
| `hw/src/top/microgpt_pynq_top.sv`   | **New (this fork)**     | AXI4-Lite slave wrapper exposing the upstream core via the Zynq PS GP0.                                                                    |
| `hw/tcl/build.tcl`                  | **New (this fork)**     | Vivado batch build (Zynq + AXI Interconnect + top + constraints).                                                                          |
| `hw/sim/cocotb/`                    | **New (this fork)**     | cocotb regression suite targeting `microgpt_pynq_top` (caught a production write-path bug pre-bitstream).                                  |
| `sw/drivers/microgpt.py`            | **New (this fork)**     | Python MMIO driver, IRQ fast path via `/dev/uio<n>`.                                                                                       |
| `sw/notebooks/*.ipynb`              | **New (this fork)**     | Demo, hardware-advantage, throughput notebooks for the deployed overlay.                                                                   |
| `overlays/*.bit`, `*.hwh`           | **New (this fork)**     | Vivado-built artefacts targeting `xc7z010clg400-1` / `xc7z020clg400-1`.                                                                    |
| `demos/build.py`                    | **New (this fork)**     | Weight-tensor heatmap renderer for the companion portfolio site.                                                                           |
| `tutorials/`                        | **New (this fork)**     | Workflow walkthrough notebooks.                                                                                                            |

## Conventions adopted

- All upstream files retain their original headers, naming, parameter
  values (`EMBED_DIM`, `VOCAB_SIZE`, `FRAC_BITS`, …), and behaviour.
- The cocotb tests target only the **new** AXI wrapper (`hw/src/top/`);
  upstream core behaviour is **not** retested here — that responsibility
  remains with the upstream ModelSim testbenches.
- No upstream file in `hw/src/core/` should be edited in this repo.
  If the upstream core needs a fix, the fix belongs in upstream and
  this repo pulls it in via a fresh copy + a noted update in this
  file's modification log.
