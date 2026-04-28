## How it works

This project is a real Tiny Tapeout hardening target for a reduced slice of the TALOS V2 RTL path.

Instead of trying to cram the full microGPT core into a Tiny Tapeout tile, this wrapper hardens the
actual `microgpt_categorical_sampler` module from the TALOS V2 RTL.

The sampler receives:

- a fixed 27-token logits vector
- a fixed argmax token and top logit
- a temperature value from the `uio_in` pins
- a deterministic RNG seed derived from the `ui_in` pins

When `ui_in[7]` is asserted, the wrapper launches the sampler. The sampler then performs the same staged
weight-sum, RNG-mix, cut-scaling, and categorical-pick flow used in the RTL core.

## How to test

1. Drive `ui_in[7]` high for one clock to start a sample.
2. Put the lower 7 bits of `ui_in` at the desired seed fragment.
3. Set `uio_in` to the desired low byte of the temperature in Q8.8 format.
4. Wait for `uo_out[6]` to pulse high.
5. Read the sampled token from `uo_out[4:0]`.

Output bits:

- `uo_out[4:0]`: sampled token
- `uo_out[5]`: sampler busy
- `uo_out[6]`: sampler done
- `uo_out[7]`: argmax token LSB

## External hardware

No external hardware required beyond the normal Tiny Tapeout clock/reset and GPIO access.
