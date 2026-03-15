# Output Explanation

The current FPGA workflow is BOS-only generation.

That means:

- the run starts from the special `BOS` token
- the model samples characters one at a time
- the run stops when the model emits `BOS` again or reaches the step limit

So when you run:

```powershell
.\run_inference.bat
```

the printed lines are generated names, not continuations of a typed prompt.

Example:

```text
arrin
anann
jarjan
karibib
```

Each line is:

1. start from `BOS`
2. sample next character
3. feed that character back into the FPGA
4. stop when `BOS` is sampled again

Why the names look imperfect:

- the model is tiny
- the FPGA implementation is quantized
- it learned name-like statistics, not full language understanding

`--verbose` adds hardware status words after the generated names:

```text
sample[0] status=0x05050065 done=True error=False
```

Meaning:

- `done=True`: that sample finished normally
- `error=False`: the hardware did not report an error
- `status=...`: packed hardware state for debugging

This flow is not restricted to a few hardcoded names. It generates fresh samples from the model distribution each run, using the RNG seed and temperature.
