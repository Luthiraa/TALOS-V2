import argparse
import math
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Tuple

import numpy as np

TOOLS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS_DIR))

from microgpt_model import (
    BOS_TOKEN,
    CONTEXT_LEN,
    EMBED_DIM,
    VOCAB_SIZE,
    build_quantized_package,
    decode_tokens,
    encode_prompt,
    load_flat_weights,
    parse_flat_weights,
)


BOARD_CLOCK_HZ = 50_000_000
DEFAULT_DOT_LANES = 4
DEFAULT_HIDDEN_ROW_PAR = 2
DEFAULT_LOGIT_ROW_PAR = 2
DEFAULT_X_PAR = 16
DEFAULT_FINISH_OVERHEAD = 6


def xorshift32(value: int) -> int:
    value &= 0xFFFFFFFF
    value ^= (value << 13) & 0xFFFFFFFF
    value ^= (value >> 17) & 0xFFFFFFFF
    value ^= (value << 5) & 0xFFFFFFFF
    return value & 0xFFFFFFFF


def sat16(value: int) -> int:
    return max(-32768, min(32767, int(value)))


def scale_q16(acc: int, scale: int) -> int:
    prod = int(acc) * int(scale)
    rounded = prod + 32768 if prod >= 0 else prod - 32768
    return sat16(rounded >> 16)


def exp_weight_from_delta(delta_q10: int) -> int:
    if delta_q10 >= 0:
        return 256
    idx = (-delta_q10) >> 7
    idx = min(idx, 15)
    lut = [256, 181, 128, 91, 64, 45, 32, 23, 16, 11, 8, 6, 4, 3, 2, 1]
    return lut[idx]


def kernel_step(
    package: Dict[str, np.ndarray],
    token: int,
    pos: int,
    hidden_state: np.ndarray,
    temperature_q8_8: int,
    sample_mode: bool,
    rng_state: int,
) -> Tuple[int, int, np.ndarray, np.ndarray]:
    x_vec = np.clip(
        package["wte_q"][token].astype(np.int32)
        + package["wpe_q"][pos].astype(np.int32)
        + (hidden_state.astype(np.int32) >> 1),
        -32768,
        32767,
    ).astype(np.int16)

    hidden_next = np.zeros(EMBED_DIM, dtype=np.int16)
    for row in range(EMBED_DIM):
        acc = int(np.dot(package["wq_q"][row].astype(np.int32), x_vec.astype(np.int32)))
        hidden_next[row] = scale_q16(acc, int(package["wq_scale_q16"][row]))

    logits = np.zeros(VOCAB_SIZE, dtype=np.int16)
    best_idx = 0
    second_idx = 1
    best_logit = -32768
    second_logit = -32768
    for row in range(VOCAB_SIZE):
        acc = int(np.dot(package["lm_q"][row].astype(np.int32), x_vec.astype(np.int32)))
        logit = scale_q16(acc, int(package["lm_scale_q16"][row]))
        logits[row] = logit
        if logit > best_logit:
            second_logit = best_logit
            second_idx = best_idx
            best_logit = logit
            best_idx = row
        elif logit > second_logit:
            second_logit = logit
            second_idx = row

    rng_state = xorshift32(rng_state)
    sample_choice = best_idx
    sample_found = False
    sample_rng = rng_state
    sample_shift = 0
    if temperature_q8_8 <= 128:
        sample_shift = 1
    elif temperature_q8_8 > 512:
        sample_shift = -2
    elif temperature_q8_8 > 256:
        sample_shift = -1

    for _ in range(4):
        sample_candidate = sample_rng & 31
        if sample_candidate >= VOCAB_SIZE:
            sample_candidate -= VOCAB_SIZE
        sample_delta = int(logits[sample_candidate]) - int(best_logit)
        if sample_shift > 0:
            sample_delta <<= sample_shift
        elif sample_shift < 0:
            sample_delta >>= -sample_shift
        sample_weight = exp_weight_from_delta(sample_delta)
        if not sample_found and ((sample_rng >> 8) & 0xFF) < sample_weight:
            sample_choice = sample_candidate
            sample_found = True
        sample_rng = xorshift32(sample_rng)

    next_token = sample_choice if sample_mode else best_idx
    return next_token, rng_state, hidden_next, logits


def run_kernel(
    package: Dict[str, np.ndarray],
    prompt_tokens: List[int],
    steps: int,
    temperature: float,
    seed: int,
    sample_mode: bool,
) -> Tuple[List[int], int]:
    hidden_state = np.zeros(EMBED_DIM, dtype=np.int16)
    generated: List[int] = []
    seq = [BOS_TOKEN] + prompt_tokens
    pos = 0
    next_token = BOS_TOKEN
    temperature_q8_8 = int(round(temperature * 256.0))

    while pos < len(seq):
        token = seq[pos]
        next_token, seed, hidden_state, _ = kernel_step(
            package, token, pos, hidden_state, temperature_q8_8, sample_mode, seed
        )
        pos += 1

    for _ in range(steps):
        if pos >= CONTEXT_LEN or next_token == BOS_TOKEN:
            break
        generated.append(next_token)
        next_token, seed, hidden_state, _ = kernel_step(
            package, next_token, pos, hidden_state, temperature_q8_8, sample_mode, seed
        )
        pos += 1

    return generated, seed


@dataclass
class ThroughputEstimate:
    x_cycles: int
    hidden_cycles: int
    logit_cycles: int
    finish_cycles: int
    total_cycles: int
    tok_per_sec: float


def estimate_cycles(
    dot_lanes: int,
    hidden_row_par: int,
    logit_row_par: int,
    x_par: int,
    finish_overhead: int,
    clock_hz: int,
) -> ThroughputEstimate:
    dot_cycles = math.ceil(EMBED_DIM / dot_lanes)
    x_cycles = math.ceil(EMBED_DIM / x_par)
    hidden_cycles = math.ceil(EMBED_DIM / hidden_row_par) * dot_cycles
    logit_cycles = math.ceil(VOCAB_SIZE / logit_row_par) * dot_cycles
    total_cycles = x_cycles + hidden_cycles + logit_cycles + finish_overhead
    tok_per_sec = clock_hz / total_cycles
    return ThroughputEstimate(
        x_cycles=x_cycles,
        hidden_cycles=hidden_cycles,
        logit_cycles=logit_cycles,
        finish_cycles=finish_overhead,
        total_cycles=total_cycles,
        tok_per_sec=tok_per_sec,
    )


def print_estimate(label: str, estimate: ThroughputEstimate) -> None:
    print(f"{label}")
    print(f"  x/load cycles    : {estimate.x_cycles}")
    print(f"  hidden cycles    : {estimate.hidden_cycles}")
    print(f"  logit cycles     : {estimate.logit_cycles}")
    print(f"  finish cycles    : {estimate.finish_cycles}")
    print(f"  total cycles/tok : {estimate.total_cycles}")
    print(f"  est throughput   : {estimate.tok_per_sec:.2f} tok/s")


def main() -> None:
    parser = argparse.ArgumentParser(description="Simulate the active HLS kernel and estimate parallelization throughput.")
    parser.add_argument("--weights", default="model_weights.npy")
    parser.add_argument("--prompt", default="")
    parser.add_argument("--count", type=int, default=20)
    parser.add_argument("--steps", type=int, default=15)
    parser.add_argument("--temperature", type=float, default=0.5)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--mode", choices=["sample", "greedy"], default="sample")
    parser.add_argument("--clock-hz", type=int, default=BOARD_CLOCK_HZ)
    parser.add_argument("--dot-lanes", type=int, default=DEFAULT_DOT_LANES)
    parser.add_argument("--hidden-row-par", type=int, default=DEFAULT_HIDDEN_ROW_PAR)
    parser.add_argument("--logit-row-par", type=int, default=DEFAULT_LOGIT_ROW_PAR)
    parser.add_argument("--x-par", type=int, default=DEFAULT_X_PAR)
    parser.add_argument("--finish-overhead", type=int, default=DEFAULT_FINISH_OVERHEAD)
    parser.add_argument("--target-tps", type=float, default=350000.0)
    args = parser.parse_args()

    prompt_tokens = encode_prompt(args.prompt)
    if len(prompt_tokens) >= CONTEXT_LEN:
        raise ValueError("Prompt must be shorter than 16 characters.")

    weights_path = Path(args.weights)
    if not weights_path.is_absolute():
        weights_path = Path(__file__).resolve().parents[1] / args.weights

    weights = parse_flat_weights(load_flat_weights(weights_path))
    package = build_quantized_package(weights)

    t0 = time.perf_counter()
    total_tokens = 0
    names: List[str] = []
    seed = args.seed
    sample_mode = args.mode == "sample"
    for _ in range(args.count):
        tokens, seed = run_kernel(
            package, prompt_tokens, args.steps, args.temperature, seed, sample_mode
        )
        total_tokens += len(tokens)
        names.append(decode_tokens(tokens))
    t1 = time.perf_counter()

    estimate = estimate_cycles(
        args.dot_lanes,
        args.hidden_row_par,
        args.logit_row_par,
        args.x_par,
        args.finish_overhead,
        args.clock_hz,
    )
    target_cycles = args.clock_hz / args.target_tps

    print("Kernel simulation")
    print(f"  prompt={args.prompt!r} count={args.count} steps={args.steps} mode={args.mode}")
    print(f"  wall time        : {(t1 - t0) * 1000.0:.2f} ms")
    print(f"  generated tokens : {total_tokens}")
    if total_tokens > 0:
        print(f"  python throughput: {total_tokens / (t1 - t0):.2f} tok/s")
    print("")
    for idx, name in enumerate(names[:10], 1):
        print(f"  sample {idx:2d}: {name}")
    if len(names) > 10:
        print(f"  ... {len(names) - 10} more")
    print("")
    print_estimate("Configured estimate", estimate)
    print(f"  target cycles/tok: {target_cycles:.2f} for {args.target_tps:.0f} tok/s at {args.clock_hz} Hz")

    print("")
    print("Sweep around current settings")
    for dot_lanes in (2, 4, 8, 16):
        for logit_row_par in (1, 2, 3, 4):
            sweep = estimate_cycles(
                dot_lanes,
                args.hidden_row_par,
                logit_row_par,
                args.x_par,
                args.finish_overhead,
                args.clock_hz,
            )
            marker = "*" if sweep.tok_per_sec >= args.target_tps else " "
            print(
                f"{marker} dot={dot_lanes:2d} hidden_par={args.hidden_row_par:2d} "
                f"logit_par={logit_row_par:2d} cycles={sweep.total_cycles:3d} "
                f"tps={sweep.tok_per_sec:9.2f}"
            )


if __name__ == "__main__":
    main()
