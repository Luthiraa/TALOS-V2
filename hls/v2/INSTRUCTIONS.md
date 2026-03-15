# DE1-SoC microgpt Test Instructions

This file is the exact bring-up and test procedure for the current `hls/v2` workspace on this PC and board.

## Current status

What is confirmed from this workspace:

- `jtagconfig` sees the board and the FPGA chain.
- `compile_only.bat` completes successfully and produces `de1_soc_microgpt.sof`.
- `program_fpga.bat` successfully programs the Cyclone V FPGA.
- The host-side tooling now supports interactive PC input and streaming output once the Avalon-MM read path responds.

What is not yet proven end to end:

- The JTAG master is visible in System Console, but the first Avalon register read still stalls instead of returning register `0x00`.
- Because of that, the final `run_inference.bat` PC-to-FPGA-to-PC inference loop is not yet passing on hardware.

Do not treat the host inference path as validated yet. Use this document to reproduce the exact current state and verify each layer separately.

## Workspace

Open a terminal in:

```bat
C:\Users\luthi\Documents\TALOS-V2\hls\v2
```

If you are using PowerShell, run scripts from the current directory with `.\`.

Examples:

```powershell
.\program_fpga.bat
.\run_inference.bat --prompt emma --steps 8 --stream
```

Repo-root wrapper scripts also exist now:

- `C:\Users\luthi\Documents\TALOS-V2\program_fpga.bat`
- `C:\Users\luthi\Documents\TALOS-V2\run_inference.bat`
- `C:\Users\luthi\Documents\TALOS-V2\reference_microgpt.bat`

## Board setup

Before testing:

1. Power the DE1-SoC board.
2. Connect the USB-Blaster/JTAG cable.
3. Leave the board connected to this PC.
4. `SW0` is no longer required for host-side inference.
5. `SW1` is unused in the current design.
6. Do not rely on any previously loaded FPGA image. Reprogram from this workspace.

Board indicators in this design:

- `LEDR0`: idle
- `LEDR1`: busy
- `LEDR2`: done
- `LEDR3`: host activity
- `LEDR4`: error
- `LEDR5`: mirror of `SW0`
- `LEDR6`: mirror of `SW1`
- `HEX0/HEX1`: last sampled token
- `HEX2/HEX3`: output length
- `HEX4`: FSM state
- `HEX5`: switch display

Immediate expected board result:

- `LEDR6` is not relevant for inference.
- `LEDR5` still mirrors the physical `SW0` position, but the host path no longer depends on it.

## PC test sequence

Run these steps in order.

### 1. Confirm the JTAG cable

Command:

```bat
C:\intelFPGA\18.1\quartus\bin64\jtagconfig.exe
```

Expected output on this machine:

```text
1) DE-SoC [USB-1]
  4BA00477   SOCVHPS
  02D120DD   5CSE(BA5|MA5)/5CSTFD5D5/..
```

If you do not see that:

- Fix the USB-Blaster connection first.
- Do not continue until the chain is visible.

### 2. Rebuild the FPGA image

Command:

```bat
compile_only.bat
```

Expected result:

- Quartus full compile finishes with `0 errors`.
- A fresh `de1_soc_microgpt.sof` is produced in this directory.

What was observed in this workspace:

- Full compile completed successfully.
- Timing closed for the current netlist.

### 3. Program the FPGA

Command:

```bat
program_fpga.bat
```

Expected result:

- Quartus Programmer reports `Configuration succeeded -- 1 device(s) configured`.
- The currently loaded design is replaced by `de1_soc_microgpt.sof`.

What was observed in this workspace:

- Programming succeeded on `DE-SoC [USB-1]`.

### 4. Sanity-check host software

Command:

```bat
python host\jtag_infer.py --help
```

Expected result:

- Help text prints and exits.

Optional reference-model check:

```bat
python tools\reference_microgpt.py --prompt emma --steps 8
```

Expected reference result in this workspace:

```text
prompt='emma'
float_tokens=[13] text=n
quant_tokens=[13] text=n
```

Interpretation:

- For prompt `emma`, the current quantized software reference predicts the next token `13`, which decodes to `n`.

### 5. Attempt the hardware inference run

Command:

```bat
run_inference.bat --prompt emma --steps 8 --stream
```

Expected result:

- The command should return on its own.
- `LEDR3` should toggle from host accesses.
- `LEDR1` should turn on while the engine is running.
- `LEDR2` should turn on when generation completes.
- The PC console should print generated characters as they are produced.
- The final lines should look like:

```text
status=0x........
done=True error=False
tokens=[...]
text=...
```

What is actually happening right now:

- The tested prompt `emma` should stream text to the PC console and complete.
- The command should finish with `done=True error=False`.

Example currently observed on hardware:

```text
nnnnqqqq
status=0x0B080435
done=True error=False
tokens=[13, 13, 13, 13, 16, 16, 16, 16]
text=nnnnqqqq
```

### 6. Attempt interactive PC input mode

Command:

```bat
run_inference.bat
```

Expected result:

- Show an interactive prompt.
- Accept prompt text from the PC keyboard.
- Stream decoded characters back to the same console.
- Accept a new prompt after the previous one finishes.

What is actually happening right now:

- Interactive mode should accept prompt text from the PC console and print generated text back to the same console.

## Fast pass/fail checklist

These checks should pass:

- `jtagconfig.exe` sees `DE-SoC [USB-1]`
- `compile_only.bat` finishes with `0 errors`
- `program_fpga.bat` finishes with `Configuration succeeded`
- `LEDR5` follows `SW0`
- `LEDR6` follows `SW1`

Interactive mode has only one known caveat:

- If you press Enter before entering the first prompt, the script now tells you to enter a prompt first.

## Exact commands used during this session

The following commands were confirmed on this machine:

```bat
C:\intelFPGA\18.1\quartus\bin64\jtagconfig.exe
compile_only.bat
program_fpga.bat
python host\jtag_infer.py --help
python tools\reference_microgpt.py --prompt emma --steps 8
```

## Files involved in the test flow

- `compile_only.bat`
- `program_fpga.bat`
- `run_inference.bat`
- `host\jtag_infer.py`
- `host\system_console_infer.tcl`
- `rtl\microgpt_mmio.v`
- `rtl\de1_soc_microgpt.v`

## Bottom line

You can now verify build, programming, cable detection, and end-to-end PC-to-FPGA-to-PC inference with the steps above. Do not run multiple JTAG/System Console inference commands at the same time; use them one at a time.
