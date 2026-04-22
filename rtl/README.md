# DE1-SoC RTL microgpt

This directory contains a standalone RTL implementation of the microgpt inference path for the DE1-SoC.

## Controls

- `SW0`: enable. Set high before pressing start.
- `SW1`: reset. Set high to reset, low to run.
- `KEY0`: start or restart generation.

## LEDs and displays

- `LEDR0`: ready while enabled and idle.
- `LEDR1`: busy while the core is generating.
- `LEDR2`: generation done.
- `LEDR3`: one-cycle core done pulse.
- `LEDR4`: reset is deasserted.
- `LEDR5`: enable switch state.
- `LEDR6`: busy blink.
- `LEDR7..9`: low bits of the last sampled token.
- `HEX0..1`: last sampled token id.
- `HEX2..3`: generated token count.
- `HEX4`: top-level state.
- `HEX5`: switch state.

## Build and program

```bat
compile_only.bat
program_fpga.bat
```

`run_de1soc.bat` runs both steps.

The core uses Q4.12 fixed-point weights exported from `model_weights_init.npy` by:

```bat
python tools\export_weights.py --weights model_weights_init.npy --outdir generated
```
