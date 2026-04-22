import argparse
import math
import random
from pathlib import Path

import numpy as np


N_LAYER = 1
N_EMBD = 16
BLOCK_SIZE = 16
N_HEAD = 4
HEAD_DIM = N_EMBD // N_HEAD


def load_docs(path: Path) -> list[str]:
    return [line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def consume_training_rng_state(docs: list[str], vocab_size: int) -> None:
    random.seed(42)
    random.shuffle(docs)
    shapes = [
        (vocab_size, N_EMBD),
        (BLOCK_SIZE, N_EMBD),
        (vocab_size, N_EMBD),
        (N_EMBD, N_EMBD),
        (N_EMBD, N_EMBD),
        (N_EMBD, N_EMBD),
        (N_EMBD, N_EMBD),
        (4 * N_EMBD, N_EMBD),
        (N_EMBD, 4 * N_EMBD),
    ]
    for rows, cols in shapes:
        for _ in range(rows * cols):
            random.gauss(0, 0.08)


def linear(x, w):
    return [sum(wi * xi for wi, xi in zip(wo, x)) for wo in w]


def softmax(logits):
    max_val = max(logits)
    exps = [math.exp(v - max_val) for v in logits]
    total = sum(exps)
    return [e / total for e in exps]


def rmsnorm(x):
    ms = sum(xi * xi for xi in x) / len(x)
    scale = (ms + 1e-5) ** -0.5
    return [xi * scale for xi in x]


def gpt(state, token_id, pos_id, keys, values, bos_token):
    tok_emb = state["wte"][token_id]
    pos_emb = state["wpe"][pos_id]
    x = [float(t + p) for t, p in zip(tok_emb, pos_emb)]
    x = rmsnorm(x)

    for layer_idx in range(N_LAYER):
        x_residual = x
        x = rmsnorm(x)
        q = linear(x, state[f"layer{layer_idx}.attn_wq"])
        k = linear(x, state[f"layer{layer_idx}.attn_wk"])
        v = linear(x, state[f"layer{layer_idx}.attn_wv"])
        keys[layer_idx].append(k)
        values[layer_idx].append(v)

        x_attn = []
        for head in range(N_HEAD):
            hs = head * HEAD_DIM
            q_h = q[hs : hs + HEAD_DIM]
            k_h = [ki[hs : hs + HEAD_DIM] for ki in keys[layer_idx]]
            v_h = [vi[hs : hs + HEAD_DIM] for vi in values[layer_idx]]
            attn_logits = [
                sum(q_h[j] * k_h[t][j] for j in range(HEAD_DIM)) / HEAD_DIM**0.5
                for t in range(len(k_h))
            ]
            attn_weights = softmax(attn_logits)
            head_out = [
                sum(attn_weights[t] * v_h[t][j] for t in range(len(v_h)))
                for j in range(HEAD_DIM)
            ]
            x_attn.extend(head_out)

        x = linear(x_attn, state[f"layer{layer_idx}.attn_wo"])
        x = [a + b for a, b in zip(x, x_residual)]

        x_residual = x
        x = rmsnorm(x)
        x = linear(x, state[f"layer{layer_idx}.mlp_fc1"])
        x = [max(0.0, xi) for xi in x]
        x = linear(x, state[f"layer{layer_idx}.mlp_fc2"])
        x = [a + b for a, b in zip(x, x_residual)]

    return linear(x, state["lm_head"])


def sample_names(state, itos, bos_token, count, temperature):
    for sample_idx in range(count):
        keys = [[] for _ in range(N_LAYER)]
        values = [[] for _ in range(N_LAYER)]
        token_id = bos_token
        sample = []
        tokens = []
        for pos_id in range(BLOCK_SIZE):
            logits = gpt(state, token_id, pos_id, keys, values, bos_token)
            probs = softmax([logit / temperature for logit in logits])
            token_id = random.choices(range(len(itos) + 1), weights=probs)[0]
            tokens.append(token_id)
            if token_id == bos_token:
                break
            sample.append(itos[token_id])
        yield sample_idx + 1, "".join(sample), tokens


def main() -> None:
    parser = argparse.ArgumentParser(description="Exact Karpathy microgpt inference using saved trained weights.")
    parser.add_argument("--weights", default="rtl/microgpt/weights_only.npy")
    parser.add_argument("--names", default="arm/training/names.txt")
    parser.add_argument("--count", type=int, default=20)
    parser.add_argument("--temperature", type=float, default=0.5)
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[2]
    weights_path = Path(args.weights)
    names_path = Path(args.names)
    if not weights_path.is_absolute():
        weights_path = root / weights_path
    if not names_path.is_absolute():
        names_path = root / names_path

    docs = load_docs(names_path)
    uchars = sorted(set("".join(docs)))
    bos_token = len(uchars)
    itos = {idx: ch for idx, ch in enumerate(uchars)}
    consume_training_rng_state(docs, bos_token + 1)

    state = np.load(weights_path, allow_pickle=True).item()
    state = {key: np.asarray(value, dtype=np.float64) for key, value in state.items()}

    print("--- exact Karpathy microgpt inference ---")
    for idx, text, tokens in sample_names(state, itos, bos_token, args.count, args.temperature):
        print(f"sample {idx:2d}: {text:<16s} tokens={tokens}")


if __name__ == "__main__":
    main()
