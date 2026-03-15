# DE1-SoC microgpt JTAG Generator

This workspace runs a small microgpt-style character model on the DE1-SoC and streams sampled names back to the PC over JTAG.

## Current behavior

- Generation always starts from `BOS`.
- There is no prompt input in the normal host flow.
- The FPGA samples characters until it emits `BOS` or reaches the configured step limit.
- `run_inference.bat` prints sampled names directly to the PC console.

## Quick start

From `C:\Users\luthi\Documents\TALOS-V2` in PowerShell:

```powershell
.\program_fpga.bat
.\run_inference.bat
```

Example options:

```powershell
.\run_inference.bat --count 10 --steps 15 --temperature 0.5
.\run_inference.bat --count 10 --steps 15 --temperature 0.5 --verbose
```

## Host interface

- `--count`: number of names to generate
- `--steps`: max tokens per name, `1..15`
- `--temperature`: sampling temperature
- `--seed`: starting RNG seed
- `--verbose`: print per-sample status words

The default `.\run_inference.bat` run currently prints 20 sampled names.

## Board controls

- `SW0`: not required for host generation
- `SW1`: unused
- `KEY0`: manual start
- `KEY1`: clear

LEDs:

- `LEDR0`: idle
- `LEDR1`: busy
- `LEDR2`: done
- `LEDR3`: host activity
- `LEDR4`: error

## Verified on hardware

This exact flow was rebuilt, programmed, and tested in this workspace on March 15, 2026:

```powershell
.\program_fpga.bat
.\run_inference.bat
```

Observed sample output:

```text
arrin
anann
jarjan
anaunntbqqlil
anfin
anelekdd
anfinu
ajann
jcelf
karibib
```

## Notes

- The active FPGA kernel is still a compact quantized implementation, not a mathematically exact line-by-line reproduction of Karpathy's Python.
- The BOS-only sampled-name workflow is now the active hardware behavior.
- JTAG console bandwidth is lower than raw on-fabric token generation throughput, so visible PC print rate is not the same metric as core token rate.

## Key files

- `rtl/microgpt_step.v`
- `rtl/microgpt_mmio.v`
- `host/jtag_infer.py`
- `host/system_console_infer.tcl`
- `tools/reference_microgpt.py`
- `INSTRUCTIONS.md`
