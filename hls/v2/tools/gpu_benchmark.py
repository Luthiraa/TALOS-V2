"""
gpu_benchmark.py – MicroGPT inference benchmark on GPU (RTX 3050 Ti)

Mirrors the FPGA host (jtag_infer.py) defaults exactly:
  --count       20    (number of names to generate)
  --steps       15    (max tokens per name)
  --temperature 0.5   (sampling temperature)
  --seed        1     (xorshift32 RNG seed, same as FPGA)
  mode          sample

Two backends are run and compared:
  1. NumPy CPU   – same quantized integer path as the FPGA reference
  2. PyTorch GPU – float32 forward pass on the 3050 Ti
"""

import argparse
import math
import sys
import time
from pathlib import Path
from typing import List, Tuple

import numpy as np

# ── resolve imports from the tools/ directory ──────────────────────────────
TOOLS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS_DIR))

from microgpt_model import (
    ACT_FRAC_BITS,
    ACT_SCALE,
    BOS_TOKEN,
    CONTEXT_LEN,
    EMBED_DIM,
    HEAD_DIM,
    ITOS,
    NUM_HEADS,
    VOCAB_SIZE,
    build_quantized_package,
    decode_tokens,
    load_flat_weights,
    parse_flat_weights,
)
from reference_microgpt import (
    run_float,
    run_quantized,
    xorshift32,
    sample_from_logits,
)

# ──────────────────────────────────────────────────────────────────────────
# Try to import PyTorch with CUDA
# ──────────────────────────────────────────────────────────────────────────
try:
    import torch
    import torch.nn as nn
    HAS_TORCH = True
except ImportError:
    HAS_TORCH = False

# ──────────────────────────────────────────────────────────────────────────
# PyTorch model definition (float32)
# ──────────────────────────────────────────────────────────────────────────
class MicroGPTTorch(nn.Module):
    def __init__(self, weights):
        super().__init__()
        self.wte    = nn.Parameter(torch.tensor(weights.wte,    dtype=torch.float32))
        self.wpe    = nn.Parameter(torch.tensor(weights.wpe,    dtype=torch.float32))
        self.lm_head= nn.Parameter(torch.tensor(weights.lm_head,dtype=torch.float32))
        self.c_attn = nn.Parameter(torch.tensor(weights.c_attn_w,dtype=torch.float32))
        self.c_proj = nn.Parameter(torch.tensor(weights.c_proj_w,dtype=torch.float32))
        self.c_fc   = nn.Parameter(torch.tensor(weights.c_fc_w,  dtype=torch.float32))
        self.c_proj2= nn.Parameter(torch.tensor(weights.c_proj2_w,dtype=torch.float32))

    @staticmethod
    def rmsnorm(x: torch.Tensor) -> torch.Tensor:
        return x / torch.sqrt(torch.mean(x * x) + 1e-5)

    @staticmethod
    def sqrelu(x: torch.Tensor) -> torch.Tensor:
        return torch.clamp(x, min=0.0) ** 2

    def step(self, token_id: int, pos: int,
             k_cache: torch.Tensor, v_cache: torch.Tensor) -> torch.Tensor:
        x = self.rmsnorm(self.wte[token_id] + self.wpe[pos])

        # attention
        x_a = self.rmsnorm(x)
        qkv = self.c_attn @ x_a
        q = qkv[:EMBED_DIM].view(NUM_HEADS, HEAD_DIM)
        k = qkv[EMBED_DIM:2*EMBED_DIM].view(NUM_HEADS, HEAD_DIM)
        v = qkv[2*EMBED_DIM:3*EMBED_DIM].view(NUM_HEADS, HEAD_DIM)
        k_cache[pos] = k
        v_cache[pos] = v
        scale = 1.0 / math.sqrt(HEAD_DIM)
        out = torch.zeros(NUM_HEADS, HEAD_DIM, device=x.device, dtype=x.dtype)
        for h in range(NUM_HEADS):
            scores = (k_cache[:pos+1, h] @ q[h]) * scale
            scores = scores - scores.max()
            probs  = torch.softmax(scores, dim=0)
            out[h] = probs @ v_cache[:pos+1, h]
        x = x + self.c_proj @ out.reshape(EMBED_DIM)

        # mlp
        x_m = self.rmsnorm(x)
        x = x + self.c_proj2 @ self.sqrelu(self.c_fc @ x_m)

        return self.lm_head @ x  # logits [VOCAB_SIZE]


def run_torch(model: "MicroGPTTorch", device: "torch.device",
              count: int, steps: int, temperature: float, seed: int
              ) -> Tuple[List[str], float, int]:
    """Generate `count` names; returns (names, elapsed_seconds, total_tokens)."""
    model.eval()
    names: List[str] = []
    total_tokens = 0

    with torch.no_grad():
        t0 = time.perf_counter()

        for _ in range(count):
            k_cache = torch.zeros(CONTEXT_LEN, NUM_HEADS, HEAD_DIM,
                                  device=device, dtype=torch.float32)
            v_cache = torch.zeros(CONTEXT_LEN, NUM_HEADS, HEAD_DIM,
                                  device=device, dtype=torch.float32)
            generated: List[int] = []
            current = BOS_TOKEN
            pos = 0

            logits = model.step(current, pos, k_cache, v_cache)
            pos += 1
            logits_np = logits.cpu().numpy()
            current, seed = sample_from_logits(logits_np, temperature, seed)

            for _ in range(steps):
                if pos >= CONTEXT_LEN or current == BOS_TOKEN:
                    break
                generated.append(current)
                logits = model.step(current, pos, k_cache, v_cache)
                pos += 1
                logits_np = logits.cpu().numpy()
                current, seed = sample_from_logits(logits_np, temperature, seed)

            total_tokens += len(generated)
            names.append(decode_tokens(generated))

        # ensure GPU work is done before stopping the timer
        if device.type == "cuda":
            torch.cuda.synchronize()
        t1 = time.perf_counter()

    return names, t1 - t0, total_tokens


# ──────────────────────────────────────────────────────────────────────────
# NumPy quantized CPU benchmark (mirrors FPGA logic)
# ──────────────────────────────────────────────────────────────────────────
def run_numpy_quant(weights, package, count: int, steps: int,
                    temperature: float, seed: int) -> Tuple[List[str], float, int]:
    names: List[str] = []
    total_tokens = 0
    t0 = time.perf_counter()
    for _ in range(count):
        tokens, _, seed = run_quantized(
            weights, package, [], steps, "sample", temperature, seed
        )
        total_tokens += len(tokens)
        names.append(decode_tokens(tokens))
    t1 = time.perf_counter()
    return names, t1 - t0, total_tokens


# ──────────────────────────────────────────────────────────────────────────
# Pretty printing
# ──────────────────────────────────────────────────────────────────────────
BAR = "=" * 52

def print_results(label: str, names: List[str], elapsed: float, tokens: int) -> None:
    tps = tokens / elapsed if elapsed > 0 else float("inf")
    us  = (elapsed / tokens * 1e6) if tokens > 0 else 0
    print(f"\n{BAR}")
    print(f"  {label}")
    print(BAR)
    for i, name in enumerate(names, 1):
        print(f"  sample {i:2d}: {name}")
    print(BAR)
    print(f"  Tokens generated : {tokens}")
    print(f"  Wall time        : {elapsed*1000:.2f} ms")
    print(f"  Throughput       : {tps:.2f} tok/s")
    print(f"  Latency          : {us:.2f} us/tok")
    print(BAR)


# ──────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────
def main() -> None:
    parser = argparse.ArgumentParser(
        description="MicroGPT GPU benchmark – mirrors FPGA jtag_infer.py defaults."
    )
    parser.add_argument("--weights",     default="model_weights.npy")
    parser.add_argument("--count",       type=int,   default=20,  help="Names to generate")
    parser.add_argument("--steps",       type=int,   default=15,  help="Max tokens/name (FPGA default=15)")
    parser.add_argument("--temperature", type=float, default=0.5, help="Sampling temp (FPGA default=0.5)")
    parser.add_argument("--seed",        type=int,   default=1,   help="xorshift32 seed (FPGA default=1)")
    parser.add_argument("--cpu-only",    action="store_true",      help="Skip GPU even if available")
    args = parser.parse_args()

    weights_path = Path(args.weights)
    if not weights_path.is_absolute():
        weights_path = Path(__file__).resolve().parents[1] / args.weights

    print(f"\nLoading weights from: {weights_path}")
    flat    = load_flat_weights(weights_path)
    weights = parse_flat_weights(flat)
    package = build_quantized_package(weights)
    print(f"  params={flat.shape[0]}  vocab={VOCAB_SIZE}  embed={EMBED_DIM}  "
          f"heads={NUM_HEADS}  ctx={CONTEXT_LEN}")
    print(f"\nBenchmark config:")
    print(f"  count={args.count}  steps={args.steps}  "
          f"temperature={args.temperature}  seed={args.seed}  mode=sample")

    # ── NumPy / CPU reference (quantized, mirrors FPGA) ──────────────────
    np_names, np_time, np_toks = run_numpy_quant(
        weights, package, args.count, args.steps, args.temperature, args.seed
    )
    print_results("NumPy CPU  (quantized – same path as FPGA reference)",
                  np_names, np_time, np_toks)

    # ── PyTorch GPU ───────────────────────────────────────────────────────
    if not HAS_TORCH:
        print("\n[!] PyTorch not installed – skipping GPU benchmark.")
        print("    Run:  pip install torch --index-url https://download.pytorch.org/whl/cu121")
        return

    if args.cpu_only or not torch.cuda.is_available():
        device_name = "CPU (torch)"
        device = torch.device("cpu")
    else:
        device_name = torch.cuda.get_device_name(0)
        device = torch.device("cuda")

    print(f"\nPyTorch device: {device_name}")
    model = MicroGPTTorch(weights).to(device)

    # warm-up pass (GPU JIT / kernel launch overhead)
    if device.type == "cuda":
        print("  Warming up GPU...")
        _, _, _ = run_torch(model, device, count=1, steps=5,
                            temperature=args.temperature, seed=args.seed)
        torch.cuda.synchronize()

    pt_names, pt_time, pt_toks = run_torch(
        model, device, args.count, args.steps, args.temperature, args.seed
    )
    print_results(f"PyTorch GPU  ({device_name}  float32)",
                  pt_names, pt_time, pt_toks)

    # ── Speed comparison ──────────────────────────────────────────────────
    if np_toks > 0 and pt_toks > 0 and np_time > 0:
        np_tps = np_toks / np_time
        pt_tps = pt_toks / pt_time
        ratio  = pt_tps / np_tps
        print(f"\n  GPU is {ratio:.1f}x {'faster' if ratio >= 1 else 'slower'} than NumPy CPU")
        print(f"  (Note: model is tiny – 4192 params – GPU transfer overhead dominates)\n")


if __name__ == "__main__":
    main()
