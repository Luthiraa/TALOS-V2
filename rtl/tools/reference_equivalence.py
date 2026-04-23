import argparse
from pathlib import Path
from typing import Iterable, List, Tuple

import numpy as np

from export_weights import SCALE, load_state_dict, quantize_q12
from karpathy_exact_reference import (
    BLOCK_SIZE,
    N_LAYER,
    consume_training_rng_state,
    gpt,
    load_docs,
    sample_names,
    softmax,
)


def load_float_state(weights_path: Path) -> dict[str, np.ndarray]:
    state = load_state_dict(weights_path)
    return {key: np.asarray(value, dtype=np.float64) for key, value in state.items()}


def load_q12_dequant_state(weights_path: Path) -> dict[str, np.ndarray]:
    state = load_float_state(weights_path)
    return {
        key: quantize_q12(value).astype(np.float64) / float(SCALE)
        for key, value in state.items()
    }


def build_vocab(names_path: Path) -> tuple[dict[int, str], int, list[str]]:
    docs = load_docs(names_path)
    uchars = sorted(set("".join(docs)))
    bos_token = len(uchars)
    itos = {idx: ch for idx, ch in enumerate(uchars)}
    return itos, bos_token, docs


def count_params(state: dict[str, np.ndarray]) -> int:
    return sum(int(np.prod(value.shape)) for value in state.values())


def xorshift32(state: int) -> int:
    state &= 0xFFFFFFFF
    state ^= (state << 13) & 0xFFFFFFFF
    state ^= (state >> 17) & 0xFFFFFFFF
    state ^= (state << 5) & 0xFFFFFFFF
    return state & 0xFFFFFFFF


def sample_names_xorshift(
    state: dict[str, np.ndarray],
    itos: dict[int, str],
    bos_token: int,
    count: int,
    temperature: float,
    seed: int,
) -> Iterable[Tuple[int, str, List[int], int]]:
    rng_state = seed & 0xFFFFFFFF
    for sample_idx in range(count):
        keys = [[] for _ in range(N_LAYER)]
        values = [[] for _ in range(N_LAYER)]
        token_id = bos_token
        sample = []
        tokens = []
        for pos_id in range(BLOCK_SIZE):
            logits = gpt(state, token_id, pos_id, keys, values, bos_token)
            probs = softmax([logit / temperature for logit in logits])
            rng_state = xorshift32(rng_state)
            threshold = (rng_state & 0xFFFFFF) / float(1 << 24)
            cdf = 0.0
            token_id = len(probs) - 1
            for idx, prob in enumerate(probs):
                cdf += prob
                if threshold < cdf:
                    token_id = idx
                    break
            tokens.append(token_id)
            if token_id == bos_token:
                break
            sample.append(itos[token_id])
        yield sample_idx + 1, "".join(sample), tokens, rng_state


def collect_python_reference(
    state: dict[str, np.ndarray],
    names_path: Path,
    count: int,
    temperature: float,
) -> list[tuple[int, str, list[int]]]:
    itos, bos_token, docs = build_vocab(names_path)
    consume_training_rng_state(docs, bos_token + 1)
    return list(sample_names(state, itos, bos_token, count, temperature))


def collect_xorshift_reference(
    state: dict[str, np.ndarray],
    names_path: Path,
    count: int,
    temperature: float,
    seed: int,
) -> list[tuple[int, str, list[int], int]]:
    itos, bos_token, _ = build_vocab(names_path)
    return list(sample_names_xorshift(state, itos, bos_token, count, temperature, seed))


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Compare exact Python microGPT outputs against the exported RTL Q4.12 weights."
    )
    parser.add_argument("--weights", default="rtl/microgpt/weights_only.npy")
    parser.add_argument("--names", default="arm/training/names.txt")
    parser.add_argument("--count", type=int, default=5)
    parser.add_argument("--temperature", type=float, default=0.5)
    parser.add_argument("--xorshift-seed", type=int, default=2)
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[2]
    weights_path = Path(args.weights)
    names_path = Path(args.names)
    if not weights_path.is_absolute():
        weights_path = root / weights_path
    if not names_path.is_absolute():
        names_path = root / names_path

    float_state = load_float_state(weights_path)
    q12_state = load_q12_dequant_state(weights_path)

    print(f"param_count={count_params(float_state)}")

    float_python = collect_python_reference(float_state, names_path, args.count, args.temperature)
    q12_python = collect_python_reference(q12_state, names_path, args.count, args.temperature)
    print("python_rng_float:")
    for idx, text, tokens in float_python:
        print(f"  sample {idx:2d}: {text:<16s} tokens={tokens}")
    print("python_rng_q12_dequant:")
    for idx, text, tokens in q12_python:
        print(f"  sample {idx:2d}: {text:<16s} tokens={tokens}")

    float_xorshift = collect_xorshift_reference(
        float_state, names_path, args.count, args.temperature, args.xorshift_seed
    )
    q12_xorshift = collect_xorshift_reference(
        q12_state, names_path, args.count, args.temperature, args.xorshift_seed
    )
    print(f"xorshift_float_seed={args.xorshift_seed}:")
    for idx, text, tokens, seed_after in float_xorshift:
        print(f"  sample {idx:2d}: {text:<16s} tokens={tokens} rng=0x{seed_after:08X}")
    print(f"xorshift_q12_dequant_seed={args.xorshift_seed}:")
    for idx, text, tokens, seed_after in q12_xorshift:
        print(f"  sample {idx:2d}: {text:<16s} tokens={tokens} rng=0x{seed_after:08X}")


if __name__ == "__main__":
    main()
