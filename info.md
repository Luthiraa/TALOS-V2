# TALOS-V2 Setup And Usage Information

This file documents the setup, build flow, scripts, and runtime procedure for the active DE1-SoC `microgpt` design in this repository.

The current hardware target is the HLS-backed design under `hls/v2`. The FPGA image used by the normal workflow is not a hand-written RTL-only core. The normal full rebuild flow runs Intel HLS, regenerates the generated IP collateral, compiles Quartus, optionally creates an `.rbf`, and then programs the board.

## 1. Repository Layout

Relevant entrypoints:

- `program_fpga.bat`
- `run_inference.bat`
- `reference_microgpt.bat`
- `hls\v2\run_hls_build.bat`
- `hls\v2\compile_only.bat`
- `hls\v2\generate_rbf.bat`
- `hls\v2\program_fpga.bat`
- `hls\v2\run_inference.bat`
- `hls\v2\rebuild_and_program.bat`
- `hls\v2\scripts\build_hls.ps1`
- `hls\v2\host\jtag_infer.py`
- `hls\v2\tools\reference_microgpt.py`
- `hls\v2\tools\export_microgpt_weights.py`
- `hls\v2\tools\export_microgpt_roms.py`

Top-level `.bat` files are convenience wrappers that `pushd` into `hls\v2` and call the corresponding script there.

## 2. What The Active Design Does

The active design is a small DE1-SoC FPGA name generator that:

- starts each generation from `BOS`
- samples one token at a time on the FPGA
- streams generated tokens back to the PC over JTAG
- stops a sample when `BOS` is emitted again or when the step limit is reached

The normal host flow does not accept a typed prompt. It is a BOS-only sampled-name generator.

## 3. Required Software

The scripts in this workspace assume these tools exist at the exact Windows paths shown below:

- Intel FPGA / Quartus 18.1
  - `C:\intelFPGA\18.1\quartus\bin64\quartus_sh.exe`
  - `C:\intelFPGA\18.1\quartus\bin64\quartus_pgm.exe`
  - `C:\intelFPGA\18.1\quartus\bin64\quartus_cpf.exe`
  - `C:\intelFPGA\18.1\quartus\bin64\jtagconfig.exe`
  - `C:\intelFPGA\18.1\quartus\sopc_builder\bin\qsys-generate.exe`
  - `C:\intelFPGA\18.1\quartus\sopc_builder\bin\qsys-script.exe`
  - `C:\intelFPGA\18.1\quartus\sopc_builder\bin\system-console.exe`
- Intel HLS 18.1
  - `C:\intelFPGA\18.1\hls\bin\i++.exe`
  - `C:\intelFPGA\18.1\hls\host\windows64\bin`
- Microsoft Visual Studio 2022 Community C++ environment
  - `C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat`
- Python on `PATH`
- PowerShell

## 4. Required Hardware

- Terasic DE1-SoC board
- Power connected to the board
- USB-Blaster / JTAG connection from the board to this PC

Expected JTAG chain:

```text
1) DE-SoC [USB-1]
  4BA00477   SOCVHPS
  02D120DD   5CSE(BA5|MA5)/5CSTFD5D5/..
```

You can verify that with:

```powershell
C:\intelFPGA\18.1\quartus\bin64\jtagconfig.exe
```

## 5. Hardware Controls And Indicators

Board controls:

- `SW0`: not required for host-driven generation
- `SW1`: unused
- `KEY0`: manual start
- `KEY1`: clear

LEDs:

- `LEDR0`: idle
- `LEDR1`: busy
- `LEDR2`: done
- `LEDR3`: host activity
- `LEDR4`: error

Additional displays:

- `HEX0/HEX1`: last sampled token
- `HEX2/HEX3`: current output length
- `HEX4`: FSM state

During a successful run, you should see host activity and short busy pulses. `LEDR4` should remain off.

## 6. Root-Level Convenience Scripts

### `program_fpga.bat`

Location:

- `program_fpga.bat`

Behavior:

- changes directory to `hls\v2`
- calls `hls\v2\program_fpga.bat`
- forwards any command-line arguments

Use this from the repo root when you just want to program the FPGA with the existing `.sof`.

### `run_inference.bat`

Location:

- `run_inference.bat`

Behavior:

- changes directory to `hls\v2`
- calls `hls\v2\run_inference.bat`
- forwards any command-line arguments

Use this from the repo root to run the JTAG inference host program against the board.

### `reference_microgpt.bat`

Location:

- `reference_microgpt.bat`

Behavior:

- changes directory to `hls\v2`
- runs `python tools\reference_microgpt.py %*`

Use this to run the software reference model from the repo root.

## 7. `hls\v2` Build And Runtime Scripts

### `hls\v2\run_hls_build.bat`

This is the HLS regeneration step.

What it does:

1. Calls Visual Studio `vcvars64.bat`
2. Prepends Intel HLS and Quartus tools to `PATH`
3. Runs Intel HLS:

```text
C:\intelFPGA\18.1\hls\bin\i++.exe -Isrc -march=5CSEMA5F31C6 src\microgpt_step.cpp -o microgpt_step_fpga.exe --simulator none
```

4. If HLS succeeds, runs:

```text
powershell -ExecutionPolicy Bypass -File scripts\build_hls.ps1
```

Important:

- This step regenerates the HLS output from `src\microgpt_step.cpp`.
- This is the script that makes the design "fully HLS-backed".
- If you change HLS C++ or model export inputs, this is the script you must rerun.

### `hls\v2\scripts\build_hls.ps1`

This is the HLS post-processing and collateral generation step.

What it does:

1. Runs `tools\export_microgpt_weights.py`
2. Runs `tools\export_microgpt_roms.py`
3. Runs `qsys-generate.exe` on the generated `microgpt_step.qsys`
4. Creates a direct Quartus `.qip` file for the generated HLS component
5. Runs `qsys-script.exe` to build the JTAG bridge system
6. Runs `qsys-generate.exe` for `jtag_microgpt_bridge.qsys`

This script is what ties the HLS-generated component into the Quartus project structure used by the top-level design.

### `hls\v2\compile_only.bat`

This is the Quartus compile step only.

Command:

```text
C:\intelFPGA\18.1\quartus\bin64\quartus_sh.exe --flow compile de1_soc_microgpt
```

Important:

- This does not rerun HLS.
- This only recompiles the existing generated RTL and project collateral already present in the project.
- If the HLS sources changed and you skip `run_hls_build.bat`, Quartus will compile stale generated output.

### `hls\v2\generate_rbf.bat`

This converts the `.sof` to `.rbf`.

Command:

```text
C:\intelFPGA\18.1\quartus\bin64\quartus_cpf.exe -c de1_soc_microgpt.sof de1_soc_microgpt.rbf
```

Use this if you need the raw binary file after a successful Quartus build.

### `hls\v2\program_fpga.bat`

This programs the board over JTAG using the current `.sof`.

Command:

```text
C:\intelFPGA\18.1\quartus\bin64\quartus_pgm.exe -c "DE-SoC [USB-1]" -m jtag -o "s;SOCVHPS@1" -o "p;de1_soc_microgpt.sof@2"
```

Important:

- This assumes the JTAG cable name is exactly `DE-SoC [USB-1]`.
- This does not build anything.
- It only programs whatever `de1_soc_microgpt.sof` currently exists in `hls\v2`.

### `hls\v2\run_inference.bat`

This launches the Python host-side JTAG inference program.

Command:

```text
python host\jtag_infer.py %*
```

This is the runtime script used after the FPGA is already programmed.

### `hls\v2\rebuild_and_program.bat`

This is the full end-to-end hardware rebuild flow.

What it does:

1. Calls `run_hls_build.bat`
2. Calls `compile_only.bat`
3. Calls `generate_rbf.bat`
4. Calls `program_fpga.bat`

Use this when you want to regenerate the HLS design, rebuild Quartus, create the `.rbf`, and immediately reprogram the board in one command.

## 8. HLS Integration Details

The active FPGA datapath includes a Verilog wrapper:

- `hls\v2\rtl\microgpt_step_hls_adapter.v`

That wrapper instantiates:

- `microgpt_step_internal`

The `microgpt_step_internal` module exists in the generated HLS output under:

- `hls\v2\components\microgpt_step\microgpt_step_internal.v`

That means the active design is using HLS-generated RTL output inside the Quartus project. The design is not just compiling hand-authored RTL.

The practical distinction is:

- `run_hls_build.bat` regenerates HLS RTL
- `compile_only.bat` compiles existing RTL collateral

## 9. Normal Operating Procedure

### Fast path: use the already-built bitstream

From the repo root in PowerShell:

```powershell
.\program_fpga.bat
.\run_inference.bat
```

This is the normal fast path when you already have a valid built `.sof`.

### Full rebuild path: regenerate HLS and rebuild the FPGA image

From `hls\v2`:

```powershell
.\rebuild_and_program.bat
```

Or run the steps one at a time:

```powershell
.\run_hls_build.bat
.\compile_only.bat
.\generate_rbf.bat
.\program_fpga.bat
```

Then run inference:

```powershell
.\run_inference.bat
```

## 10. How To Run Inference

From the repo root:

```powershell
.\run_inference.bat
```

From `hls\v2`:

```powershell
.\run_inference.bat
```

The root-level wrapper is easier if you are already at the repository root.

### Default behavior

Default invocation:

```powershell
.\run_inference.bat
```

Expected behavior:

- generates 20 sampled names
- prints one generated sample per line
- does not ask for a prompt
- communicates with the FPGA through JTAG

### Common options

Examples:

```powershell
.\run_inference.bat --count 10 --steps 15 --temperature 0.5
.\run_inference.bat --count 10 --steps 15 --temperature 0.5 --verbose
python .\hls\v2\host\jtag_infer.py --help
```

Supported options:

- `--count`: number of names to generate, default `20`
- `--steps`: maximum tokens per sample, default `15`
- `--temperature`: sampling temperature, default `0.5`
- `--seed`: initial RNG seed, default `1`
- `--poll-ms`: host polling interval in milliseconds, default `1`
- `--verbose`: print per-sample status words after generation
- `--system-console`: path to `system-console.exe`

### Important limits

- `--steps` must be between `1` and `15`
- the model uses a 16-token context total
- one token slot is consumed by the initial `BOS`

## 11. Expected Output

Normal output looks like generated names, for example:

```text
arrin
anann
jarjan
anaunntbqqlil
anfin
```

Verbose mode appends status information, for example:

```text
samples=10
sample[0] status=0x05050065 done=True error=False
sample[1] status=0x05050075 done=True error=False
```

The current host script also prints a benchmark summary when token streaming completes successfully, including:

- total tokens generated
- total elapsed time
- throughput in tokens/second
- latency in milliseconds/token

## 12. Software Reference Flow

The reference model can be run without the FPGA:

From the repo root:

```powershell
.\reference_microgpt.bat
```

This runs:

```text
python hls\v2\tools\reference_microgpt.py
```

Use this when comparing hardware behavior with the Python reference implementation.

## 13. Typical Command Sequences

### Program the board and run inference

```powershell
cd C:\Users\luthi\Documents\TALOS-V2
.\program_fpga.bat
.\run_inference.bat
```

### Full clean rebuild flow from the active design directory

```powershell
cd C:\Users\luthi\Documents\TALOS-V2\hls\v2
.\run_hls_build.bat
.\compile_only.bat
.\generate_rbf.bat
.\program_fpga.bat
.\run_inference.bat --count 10 --steps 15 --temperature 0.5 --verbose
```

### One-command rebuild and reprogram

```powershell
cd C:\Users\luthi\Documents\TALOS-V2\hls\v2
.\rebuild_and_program.bat
```

## 14. Troubleshooting

### `compile_only.bat` works but HLS changes do not appear

Cause:

- you compiled without rerunning HLS

Fix:

```powershell
cd C:\Users\luthi\Documents\TALOS-V2\hls\v2
.\run_hls_build.bat
.\compile_only.bat
```

### `program_fpga.bat` fails to find the cable

Cause:

- JTAG cable name does not match `DE-SoC [USB-1]`
- board is not powered
- USB-Blaster is not connected

Fix:

```powershell
C:\intelFPGA\18.1\quartus\bin64\jtagconfig.exe
```

Confirm the cable name and JTAG chain first.

### `run_inference.bat` fails

Check:

- FPGA was programmed successfully
- board is still connected
- `system-console.exe` exists at the expected Quartus 18.1 path
- Python is installed and on `PATH`

### `run_hls_build.bat` fails early

Check:

- Visual Studio 2022 Community is installed at the expected path
- Intel HLS 18.1 and Quartus 18.1 are installed at the expected paths
- Python is available

## 15. Files Most Relevant To The Active Flow

- `hls\v2\src\microgpt_step.cpp`: HLS C++ source
- `hls\v2\scripts\build_hls.ps1`: HLS collateral generation and Qsys integration
- `hls\v2\rtl\microgpt_step_hls_adapter.v`: wrapper between top-level control logic and HLS-generated module
- `hls\v2\rtl\microgpt_mmio.v`: MMIO/control wrapper
- `hls\v2\host\jtag_infer.py`: host-side JTAG runtime
- `hls\v2\host\system_console_infer.tcl`: System Console control script
- `hls\v2\tools\reference_microgpt.py`: software reference model
- `hls\v2\tools\export_microgpt_weights.py`: HLS weight export
- `hls\v2\tools\export_microgpt_roms.py`: ROM export

## 16. Summary

If you only want to use the existing bitstream:

```powershell
cd C:\Users\luthi\Documents\TALOS-V2
.\program_fpga.bat
.\run_inference.bat
```

If you changed the HLS code and need a real rebuild:

```powershell
cd C:\Users\luthi\Documents\TALOS-V2\hls\v2
.\run_hls_build.bat
.\compile_only.bat
.\program_fpga.bat
.\run_inference.bat
```

If you want the all-in-one rebuild path:

```powershell
cd C:\Users\luthi\Documents\TALOS-V2\hls\v2
.\rebuild_and_program.bat
```
