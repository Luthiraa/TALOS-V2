import argparse
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Tuple

import numpy as np

from microgpt_model import (
    ACT_FRAC_BITS,
    ACT_SCALE,
    BOS_TOKEN,
    CONTEXT_LEN,
    EMBED_DIM,
    HEAD_DIM,
    ITOS,
    NUM_HEADS,
    STOI,
    VOCAB_SIZE,
    build_quantized_package,
    decode_tokens,
    encode_prompt,
    load_flat_weights,
    parse_flat_weights,
)


def xorshift32(state: int) -> int:
    state &= 0xFFFFFFFF
    state ^= (state << 13) & 0xFFFFFFFF
    state ^= (state >> 17) & 0xFFFFFFFF
    state ^= (state << 5) & 0xFFFFFFFF
    return state & 0xFFFFFFFF


def sample_from_logits(logits: np.ndarray, temperature: float, state: int) -> Tuple[int, int]:
    if temperature <= 0.0:
        return int(np.argmax(logits)), state
    shifted = logits - np.max(logits)
    probs = np.exp(shifted / temperature)
    probs /= np.sum(probs)
    state = xorshift32(state)
    threshold = (state & 0xFFFFFF) / float(1 << 24)
    cdf = np.cumsum(probs)
    token = int(np.searchsorted(cdf, threshold, side="right"))
    token = min(token, probs.shape[0] - 1)
    return token, state


@dataclass
class CacheFloat:
    k: np.ndarray
    v: np.ndarray


def rmsnorm(x: np.ndarray) -> np.ndarray:
    denom = np.sqrt(np.mean(x * x) + 1e-5)
    return x / denom


def sqrelu(x: np.ndarray) -> np.ndarray:
    relu = np.maximum(x, 0.0)
    return relu * relu


def attn_step_float(x: np.ndarray, pos: int, weights, cache: CacheFloat) -> np.ndarray:
    qkv = weights.c_attn_w @ x
    q = qkv[0:EMBED_DIM].reshape(NUM_HEADS, HEAD_DIM)
    k = qkv[EMBED_DIM : 2 * EMBED_DIM].reshape(NUM_HEADS, HEAD_DIM)
    v = qkv[2 * EMBED_DIM : 3 * EMBED_DIM].reshape(NUM_HEADS, HEAD_DIM)
    cache.k[pos] = k
    cache.v[pos] = v

    out = np.zeros((NUM_HEADS, HEAD_DIM), dtype=np.float32)
    scale = 1.0 / math.sqrt(HEAD_DIM)
    for head in range(NUM_HEADS):
        scores = np.zeros(pos + 1, dtype=np.float32)
        for t in range(pos + 1):
            scores[t] = np.dot(q[head], cache.k[t, head]) * scale
        scores = scores - np.max(scores)
        probs = np.exp(scores)
        probs /= np.sum(probs)
        for t in range(pos + 1):
            out[head] += probs[t] * cache.v[t, head]
    return weights.c_proj_w @ out.reshape(EMBED_DIM)


def mlp_float(x: np.ndarray, weights) -> np.ndarray:
    return weights.c_proj2_w @ sqrelu(weights.c_fc_w @ x)


def run_float(weights, prompt_tokens: List[int], steps: int, mode: str, temperature: float, seed: int):
    cache = CacheFloat(
        k=np.zeros((CONTEXT_LEN, NUM_HEADS, HEAD_DIM), dtype=np.float32),
        v=np.zeros((CONTEXT_LEN, NUM_HEADS, HEAD_DIM), dtype=np.float32),
    )
    generated: List[int] = []
    logits_last = np.zeros(VOCAB_SIZE, dtype=np.float32)

    seq = [BOS_TOKEN] + prompt_tokens
    pos = 0

    while pos < len(seq):
        token = seq[pos]
        x = rmsnorm(weights.wte[token] + weights.wpe[pos])
        x = x + attn_step_float(rmsnorm(x), pos, weights, cache)
        x = x + mlp_float(rmsnorm(x), weights)
        logits_last = weights.lm_head @ x
        pos += 1

    current = int(np.argmax(logits_last))
    if mode == "sample":
        current, seed = sample_from_logits(logits_last, temperature, seed)

    for _ in range(steps):
        if pos >= CONTEXT_LEN or current == BOS_TOKEN:
            break
        generated.append(current)
        x = rmsnorm(weights.wte[current] + weights.wpe[pos])
        x = x + attn_step_float(rmsnorm(x), pos, weights, cache)
        x = x + mlp_float(rmsnorm(x), weights)
        logits_last = weights.lm_head @ x
        current = int(np.argmax(logits_last))
        if mode == "sample":
            current, seed = sample_from_logits(logits_last, temperature, seed)
        pos += 1

    return generated, logits_last, seed


@dataclass
class CacheQuant:
    k: np.ndarray
    v: np.ndarray


def sat16(value: int) -> int:
    return max(-32768, min(32767, int(value)))


def qmul_q11(a_q11: int, b_q11: int) -> int:
    return sat16((int(a_q11) * int(b_q11) + (1 << (ACT_FRAC_BITS - 1))) >> ACT_FRAC_BITS)


def matvec_i8_i16(weight_q: np.ndarray, scale_q16: np.ndarray, x_q: np.ndarray) -> np.ndarray:
    out = np.zeros(weight_q.shape[0], dtype=np.int16)
    for row in range(weight_q.shape[0]):
        acc = int(np.dot(weight_q[row].astype(np.int32), x_q.astype(np.int32)))
        value = (acc * int(scale_q16[row]) + (1 << 15)) >> 16
        out[row] = sat16(value)
    return out


def rmsnorm_quant(x_q: np.ndarray) -> np.ndarray:
    x = x_q.astype(np.float32) / ACT_SCALE
    y = x / math.sqrt(float(np.mean(x * x) + 1e-5))
    return np.clip(np.rint(y * ACT_SCALE), -32768, 32767).astype(np.int16)


def sqrelu_quant(x_q: np.ndarray) -> np.ndarray:
    x = x_q.astype(np.float32) / ACT_SCALE
    relu = np.maximum(x, 0.0)
    y = relu * relu
    return np.clip(np.rint(y * ACT_SCALE), -32768, 32767).astype(np.int16)


def attn_step_quant(x_q: np.ndarray, pos: int, package: Dict[str, np.ndarray], cache: CacheQuant) -> np.ndarray:
    q = matvec_i8_i16(package["wq_q"], package["wq_scale_q16"], x_q).reshape(NUM_HEADS, HEAD_DIM)
    k = matvec_i8_i16(package["wk_q"], package["wk_scale_q16"], x_q).reshape(NUM_HEADS, HEAD_DIM)
    v = matvec_i8_i16(package["wv_q"], package["wv_scale_q16"], x_q).reshape(NUM_HEADS, HEAD_DIM)
    cache.k[pos] = k
    cache.v[pos] = v

    out = np.zeros((NUM_HEADS, HEAD_DIM), dtype=np.float32)
    scale = 1.0 / math.sqrt(HEAD_DIM)
    qf = q.astype(np.float32) / ACT_SCALE
    kf = cache.k[: pos + 1].astype(np.float32) / ACT_SCALE
    vf = cache.v[: pos + 1].astype(np.float32) / ACT_SCALE

    for head in range(NUM_HEADS):
        scores = np.zeros(pos + 1, dtype=np.float32)
        for t in range(pos + 1):
            scores[t] = np.dot(qf[head], kf[t, head]) * scale
        scores = scores - np.max(scores)
        probs = np.exp(scores)
        probs /= np.sum(probs)
        for t in range(pos + 1):
            out[head] += probs[t] * vf[t, head]
    out_q = np.clip(np.rint(out.reshape(EMBED_DIM) * ACT_SCALE), -32768, 32767).astype(np.int16)
    return matvec_i8_i16(package["wo_q"], package["wo_scale_q16"], out_q)


def mlp_quant(x_q: np.ndarray, package: Dict[str, np.ndarray]) -> np.ndarray:
    hidden_q = matvec_i8_i16(package["fc1_q"], package["fc1_scale_q16"], x_q)
    hidden_q = sqrelu_quant(hidden_q)
    return matvec_i8_i16(package["fc2_q"], package["fc2_scale_q16"], hidden_q)


def run_quantized(weights, package: Dict[str, np.ndarray], prompt_tokens: List[int], steps: int, mode: str, temperature: float, seed: int):
    cache = CacheQuant(
        k=np.zeros((CONTEXT_LEN, NUM_HEADS, HEAD_DIM), dtype=np.int16),
        v=np.zeros((CONTEXT_LEN, NUM_HEADS, HEAD_DIM), dtype=np.int16),
    )
    generated: List[int] = []
    logits_last = np.zeros(VOCAB_SIZE, dtype=np.int16)
    seq = [BOS_TOKEN] + prompt_tokens
    pos = 0

    while pos < len(seq):
        token = seq[pos]
        x_q = rmsnorm_quant(package["wte_q"][token] + package["wpe_q"][pos])
        x_q = np.clip(x_q + attn_step_quant(rmsnorm_quant(x_q), pos, package, cache), -32768, 32767).astype(np.int16)
        x_q = np.clip(x_q + mlp_quant(rmsnorm_quant(x_q), package), -32768, 32767).astype(np.int16)
        logits_last = matvec_i8_i16(package["lm_q"], package["lm_scale_q16"], x_q)
        pos += 1

    current = int(np.argmax(logits_last))
    if mode == "sample":
        current, seed = sample_from_logits(logits_last.astype(np.float32), temperature, seed)

    for _ in range(steps):
        if pos >= CONTEXT_LEN or current == BOS_TOKEN:
            break
        generated.append(current)
        x_q = rmsnorm_quant(package["wte_q"][current] + package["wpe_q"][pos])
        x_q = np.clip(x_q + attn_step_quant(rmsnorm_quant(x_q), pos, package, cache), -32768, 32767).astype(np.int16)
        x_q = np.clip(x_q + mlp_quant(rmsnorm_quant(x_q), package), -32768, 32767).astype(np.int16)
        logits_last = matvec_i8_i16(package["lm_q"], package["lm_scale_q16"], x_q)
        current = int(np.argmax(logits_last))
        if mode == "sample":
            current, seed = sample_from_logits(logits_last.astype(np.float32), temperature, seed)
        pos += 1

    return generated, logits_last.astype(np.float32) / ACT_SCALE, seed


def main() -> None:
    parser = argparse.ArgumentParser(description="Reference runner for Karpathy microgpt.")
    parser.add_argument("--weights", default="model_weights.npy")
    parser.add_argument("--prompt", default="")
    parser.add_argument("--steps", type=int, default=8)
    parser.add_argument("--mode", choices=["greedy", "sample"], default="greedy")
    parser.add_argument("--temperature", type=float, default=1.0)
    parser.add_argument("--seed", type=int, default=1)
    args = parser.parse_args()

    prompt_tokens = encode_prompt(args.prompt)
    if len(prompt_tokens) >= CONTEXT_LEN:
        raise ValueError("Prompt must be shorter than 16 characters.")

    weights = parse_flat_weights(load_flat_weights(Path(args.weights)))
    package = build_quantized_package(weights)

    float_tokens, float_logits, seed_after = run_float(
        weights, prompt_tokens, args.steps, args.mode, args.temperature, args.seed
    )
    quant_tokens, quant_logits, _ = run_quantized(
        weights, package, prompt_tokens, args.steps, args.mode, args.temperature, args.seed
    )

    top_float = np.argsort(-float_logits)[:5]
    top_quant = np.argsort(-quant_logits)[:5]

    print(f"prompt={args.prompt!r}")
    print(f"float_tokens={float_tokens} text={decode_tokens(float_tokens)}")
    print(f"quant_tokens={quant_tokens} text={decode_tokens(quant_tokens)}")
    print(f"top5_float={[ITOS[int(t)] for t in top_float]}")
    print(f"top5_quant={[ITOS[int(t)] for t in top_quant]}")
    print(f"seed_after={seed_after}")


if __name__ == "__main__":
    main()
