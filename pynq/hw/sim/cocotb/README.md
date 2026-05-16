# microgpt AXI4-Lite cocotb testbench

Catches AXI handshake / register-map regressions in
`hw/src/top/microgpt_pynq_top.sv` **before** paying for a 30-minute Vivado
build and a board power cycle.

The tests drive the wrapper directly (no BD, no PS7 model) using
`cocotbext-axi`. The DUT elaborates against the unmodified TALOS-V2 core
in `hw/src/core/`.

## Why this exists

A previous bitstream wedged the entire Zynq PS bus on the first AXI write.
The slave kept `AWREADY`/`WREADY` perpetually high in idle and only
latched the transaction when AW and W were valid in the *same* cycle. The
PS M_AXI_GP0 master staggers them by a cycle, considered both handshakes
complete, and then waited forever for `BVALID`. `test_03_write_completes_does_not_hang`
is the regression for that exact failure mode: it would have caught the
bug pre-bitstream and saved a power cycle.

## Dependencies

Arch / CachyOS:

```
sudo pacman -S iverilog
# OR (newer simulator with stricter SV support):
sudo pacman -S verilator     # paru -S verilator-bin if you want the AUR build

pip install cocotb cocotbext-axi
```

`cocotb` >= 1.8 and `cocotbext-axi` >= 0.1.20 are known good.

## Run all tests

```
cd hw/sim/cocotb
make
```

Default simulator is **Icarus Verilog** (`SIM=icarus`), invoked with
`-g2012` so it tolerates the SV-2012 dialect used in the TALOS-V2 core
(unpacked 2-D arrays, etc.).

To use **Verilator** instead:

```
make SIM=verilator
```

Verilator is stricter about SV but compiles much faster and traces
better; switch to it if Icarus chokes on something the core uses.

## Run one test

```
make MODULE=test_microgpt_axi TESTCASE=test_03_write_completes_does_not_hang
```

## Waveforms

```
make WAVES=1
gtkwave dump.vcd            # Icarus default; with WAVES=1 cocotb may emit cocotb.fst
```

## Test inventory

| # | Test                                          | What it proves                                                    |
|---|-----------------------------------------------|-------------------------------------------------------------------|
| 1 | `test_01_read_magic_version_bos`              | Magic / version / BOS constants read back as documented           |
| 2 | `test_02_status_register_initial`             | After reset: ready=1, busy=done=error=0                           |
| 3 | `test_03_write_completes_does_not_hang`       | **Production-bug regression.** A single write must complete BVALID |
| 4 | `test_04_write_then_read_back`                | Config write round-trips through the readable representation      |
| 5 | `test_05_host_toggle_flips_on_each_transaction` | `status[4]` flips on every successful AXI transaction             |
| 6 | `test_06_unmapped_address_does_not_hang`      | Out-of-decode writes/reads still complete the handshake           |
| 7 | `test_07_start_pulse_via_cmd`                 | Writing bit 0 of `CMD` fires `start_pulse`, FSM leaves READY      |

Every test imposes a hard cocotb timeout, so a hang in the DUT becomes a
clean test failure rather than an infinite simulation.

## Caveats

- `test_07` exercises the full DUT including the unmodified TALOS-V2
  core. If your simulator can't elaborate a core file, switch to
  Verilator (`make SIM=verilator`) before debugging the test itself.
- The `.hex` weight files under `hw/ip/` are loaded by `$readmemh` paths
  inside the core. The Makefile passes `-I$(HW_ROOT)/ip` for resolution;
  if a child changes its readmemh search expectation you may need to add
  another `-I`.
- The XDC, BD, and PS7 are intentionally NOT in the loop. Pin-level / BD
  wiring failures still need an on-board test.
