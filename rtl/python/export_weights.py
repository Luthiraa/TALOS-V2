import argparse
from pathlib import Path

import numpy as np


FRAC_BITS = 12
SCALE = 1 << FRAC_BITS


ORDER = [
    ("wte", (27, 16)),
    ("wpe", (16, 16)),
    ("lm_head", (27, 16)),
    ("layer0.attn_wq", (16, 16)),
    ("layer0.attn_wk", (16, 16)),
    ("layer0.attn_wv", (16, 16)),
    ("layer0.attn_wo", (16, 16)),
    ("layer0.mlp_fc1", (64, 16)),
    ("layer0.mlp_fc2", (16, 64)),
]


def load_state_dict(path: Path) -> dict[str, np.ndarray]:
    raw = np.load(path, allow_pickle=True)
    if raw.shape == () and isinstance(raw.item(), dict):
        state = raw.item()
        return {key: np.asarray(value, dtype=np.float32) for key, value in state.items()}

    flat = np.asarray(raw, dtype=np.float32).reshape(-1)
    if flat.shape != (4192,):
        raise ValueError(f"expected dict .npy or 4192-value flat .npy, got shape {raw.shape}")

    state = {}
    off = 0
    for name, shape in ORDER:
        count = int(np.prod(shape))
        state[name] = flat[off : off + count].reshape(shape)
        off += count
    return state


def quantize_q12(array: np.ndarray) -> np.ndarray:
    return np.clip(np.rint(array * SCALE), -32768, 32767).astype(np.int16)


def write_hex(path: Path, array: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    flat = quantize_q12(array).reshape(-1)
    lines = [f"{int(value) & 0xFFFF:04x}" for value in flat]
    path.write_text("\n".join(lines) + "\n", encoding="ascii")


def main() -> None:
    parser = argparse.ArgumentParser(description="Export microgpt state_dict weights as Q4.12 RTL ROM hex.")
    parser.add_argument("--weights", default="model_weights_init.npy")
    parser.add_argument("--outdir", default="generated")
    args = parser.parse_args()

    state = load_state_dict(Path(args.weights))
    outdir = Path(args.outdir)

    for name, shape in ORDER:
        if name not in state:
            raise KeyError(f"missing {name}")
        if tuple(state[name].shape) != shape:
            raise ValueError(f"{name}: expected {shape}, got {state[name].shape}")
        write_hex(outdir / f"{name.replace('.', '_')}_q12.hex", state[name])

    print(f"wrote {len(ORDER)} ROMs to {outdir}")


if __name__ == "__main__":
    main()
