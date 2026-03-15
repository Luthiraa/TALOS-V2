# DE1-SoC microgpt Instructions

This design now runs as a BOS-only sampled-name generator.

What changed:

- There is no prompt input path in the normal workflow.
- Each sample starts from `BOS`.
- The FPGA samples characters until it emits `BOS` again or reaches the length limit.
- JTAG is used to start runs, set seed/temperature/count, and stream generated output back to the PC.

## PC commands

From the repo root in PowerShell:

```powershell
.\program_fpga.bat
.\run_inference.bat
```

Useful variants:

```powershell
.\run_inference.bat --count 10 --steps 15 --temperature 0.5
.\run_inference.bat --count 10 --steps 15 --temperature 0.5 --verbose
python .\hls\v2\host\jtag_infer.py --help
```

PowerShell requires `.\` for scripts in the current directory.

## Board setup

1. Power the DE1-SoC board.
2. Connect the USB-Blaster/JTAG cable.
3. Leave the board connected to this PC.
4. Reprogram the FPGA from this workspace before testing.

Switches and keys:

- `SW0` is not required for host generation.
- `SW1` is not used.
- `KEY0` can still request a manual start.
- `KEY1` can still request a clear.

## Expected JTAG detection

```powershell
C:\intelFPGA\18.1\quartus\bin64\jtagconfig.exe
```

Expected chain:

```text
1) DE-SoC [USB-1]
  4BA00477   SOCVHPS
  02D120DD   5CSE(BA5|MA5)/5CSTFD5D5/..
```

## Expected runtime behavior

Default command:

```powershell
.\run_inference.bat
```

Expected result:

- 20 sampled names are printed to the PC console.
- One name appears per line.
- No prompt is requested.
- `--verbose` also prints one status word per sample.

Example observed on hardware in this workspace:

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
anann
marin
anann
qpqlin
anann
anfenntqqrqqqq
qvvvaun
anwan
anxxf
anwann
```

Verbose example:

```text
arrin
anann
jarjan
...
samples=10
sample[0] status=0x05050065 done=True error=False
sample[1] status=0x05050075 done=True error=False
...
```

## Limits

- `--steps` must be between `1` and `15`.
- The context length is 16 tokens total, and one slot is used by the initial `BOS`.
- Output quality is limited by the very small model and quantized FPGA implementation.

## Board indicators

- `LEDR0`: idle
- `LEDR1`: busy
- `LEDR2`: done
- `LEDR3`: host activity
- `LEDR4`: error
- `HEX0/HEX1`: last sampled token
- `HEX2/HEX3`: current output length
- `HEX4`: FSM state

During a run you should see host activity and brief busy pulses. `LEDR4` should stay off during successful runs.
