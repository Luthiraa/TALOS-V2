import json
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Tuple

import numpy as np


VOCAB = "abcdefghijklmnopqrstuvwxyz^"
STOI = {ch: idx for idx, ch in enumerate(VOCAB)}
ITOS = {idx: ch for ch, idx in STOI.items()}
BOS_TOKEN = 26

CONTEXT_LEN = 16
VOCAB_SIZE = 27
EMBED_DIM = 16
NUM_HEADS = 4
HEAD_DIM = 4
MLP_DIM = 64
ACT_FRAC_BITS = 11
ACT_SCALE = 1 << ACT_FRAC_BITS
SCALE_FRAC_BITS = 16
SCALE_SCALE = 1 << SCALE_FRAC_BITS


@dataclass
class MicroGPTWeights:
    wte: np.ndarray
    wpe: np.ndarray
    lm_head: np.ndarray
    c_attn_w: np.ndarray
    c_proj_w: np.ndarray
    c_fc_w: np.ndarray
    c_proj2_w: np.ndarray


def load_flat_weights(path: Path) -> np.ndarray:
    flat = np.load(path)
    if flat.shape != (4192,):
        raise ValueError(f"Expected 4192 weights, found {flat.shape}")
    return flat.astype(np.float32)


def parse_flat_weights(flat: np.ndarray) -> MicroGPTWeights:
    off = 0

    def take(count: int) -> np.ndarray:
        nonlocal off
        chunk = flat[off : off + count]
        off += count
        return chunk

    wte = take(VOCAB_SIZE * EMBED_DIM).reshape(VOCAB_SIZE, EMBED_DIM)
    wpe = take(CONTEXT_LEN * EMBED_DIM).reshape(CONTEXT_LEN, EMBED_DIM)
    lm_head = take(VOCAB_SIZE * EMBED_DIM).reshape(VOCAB_SIZE, EMBED_DIM)
    c_attn_w = take(3 * EMBED_DIM * EMBED_DIM).reshape(3 * EMBED_DIM, EMBED_DIM)
    c_proj_w = take(EMBED_DIM * EMBED_DIM).reshape(EMBED_DIM, EMBED_DIM)
    c_fc_w = take(MLP_DIM * EMBED_DIM).reshape(MLP_DIM, EMBED_DIM)
    c_proj2_w = take(EMBED_DIM * MLP_DIM).reshape(EMBED_DIM, MLP_DIM)

    if off != flat.shape[0]:
        raise ValueError(f"Unparsed tail: {flat.shape[0] - off} weights")

    return MicroGPTWeights(
        wte=wte,
        wpe=wpe,
        lm_head=lm_head,
        c_attn_w=c_attn_w,
        c_proj_w=c_proj_w,
        c_fc_w=c_fc_w,
        c_proj2_w=c_proj2_w,
    )


def encode_prompt(prompt: str) -> List[int]:
    prompt = prompt.strip().lower()
    bad = sorted({ch for ch in prompt if ch not in STOI or ch == "^"})
    if bad:
        raise ValueError(f"Prompt contains unsupported chars: {bad}")
    return [STOI[ch] for ch in prompt]


def decode_tokens(tokens: List[int]) -> str:
    return "".join(ITOS[t] for t in tokens if t != BOS_TOKEN)


def quantize_embedding(table: np.ndarray) -> np.ndarray:
    q = np.clip(np.rint(table * ACT_SCALE), -32768, 32767).astype(np.int16)
    return q


def quantize_weight_rows(matrix: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
    out_rows = matrix.shape[0]
    q = np.zeros_like(matrix, dtype=np.int8)
    scales = np.zeros(out_rows, dtype=np.uint16)
    for row in range(out_rows):
        max_abs = float(np.max(np.abs(matrix[row])))
        scale = max(max_abs / 127.0, 1.0 / SCALE_SCALE)
        q[row] = np.clip(np.rint(matrix[row] / scale), -127, 127).astype(np.int8)
        scales[row] = np.uint16(min(round(scale * SCALE_SCALE), 0xFFFF))
    return q, scales


def build_quantized_package(weights: MicroGPTWeights) -> Dict[str, np.ndarray]:
    q_wq, s_wq = quantize_weight_rows(weights.c_attn_w[0:EMBED_DIM])
    q_wk, s_wk = quantize_weight_rows(weights.c_attn_w[EMBED_DIM : 2 * EMBED_DIM])
    q_wv, s_wv = quantize_weight_rows(weights.c_attn_w[2 * EMBED_DIM : 3 * EMBED_DIM])
    q_wo, s_wo = quantize_weight_rows(weights.c_proj_w)
    q_fc1, s_fc1 = quantize_weight_rows(weights.c_fc_w)
    q_fc2, s_fc2 = quantize_weight_rows(weights.c_proj2_w)
    q_lm, s_lm = quantize_weight_rows(weights.lm_head)
    return {
        "wte_q": quantize_embedding(weights.wte),
        "wpe_q": quantize_embedding(weights.wpe),
        "wq_q": q_wq,
        "wq_scale_q16": s_wq,
        "wk_q": q_wk,
        "wk_scale_q16": s_wk,
        "wv_q": q_wv,
        "wv_scale_q16": s_wv,
        "wo_q": q_wo,
        "wo_scale_q16": s_wo,
        "fc1_q": q_fc1,
        "fc1_scale_q16": s_fc1,
        "fc2_q": q_fc2,
        "fc2_scale_q16": s_fc2,
        "lm_q": q_lm,
        "lm_scale_q16": s_lm,
    }


def quant_manifest(weights: MicroGPTWeights, package: Dict[str, np.ndarray]) -> Dict[str, object]:
    return {
        "source_parameter_count": 4192,
        "vocab": VOCAB,
        "token_bos_eos": BOS_TOKEN,
        "context_len": CONTEXT_LEN,
        "embed_dim": EMBED_DIM,
        "heads": NUM_HEADS,
        "head_dim": HEAD_DIM,
        "mlp_dim": MLP_DIM,
        "act_frac_bits": ACT_FRAC_BITS,
        "scale_frac_bits": SCALE_FRAC_BITS,
        "shapes": {
            "wte": list(weights.wte.shape),
            "wpe": list(weights.wpe.shape),
            "lm_head": list(weights.lm_head.shape),
            "c_attn_w": list(weights.c_attn_w.shape),
            "c_proj_w": list(weights.c_proj_w.shape),
            "c_fc_w": list(weights.c_fc_w.shape),
            "c_proj2_w": list(weights.c_proj2_w.shape),
        },
        "packed_bytes_estimate": {
            key: int(np.asarray(value).nbytes) for key, value in package.items()
        },
    }


def _format_scalar(value: int) -> str:
    return str(int(value))


def _format_1d(array: np.ndarray) -> str:
    values = array.tolist() if hasattr(array, "tolist") else array
    return ", ".join(_format_scalar(v) for v in values)


def _format_2d(array: np.ndarray) -> str:
    rows = ["    {" + _format_1d(row) + "}" for row in array.tolist()]
    return ",\n".join(rows)


def write_header(path: Path, package: Dict[str, np.ndarray]) -> None:
    lines = [
        "#ifndef MICROGPT_MODEL_H_",
        "#define MICROGPT_MODEL_H_",
        "",
        "#include <stdint.h>",
        "",
        "#define MGPT_CONTEXT_LEN 16",
        "#define MGPT_VOCAB_SIZE 27",
        "#define MGPT_EMBED_DIM 16",
        "#define MGPT_NUM_HEADS 4",
        "#define MGPT_HEAD_DIM 4",
        "#define MGPT_MLP_DIM 64",
        "#define MGPT_ACT_FRAC_BITS 11",
        "#define MGPT_ACT_SCALE (1 << MGPT_ACT_FRAC_BITS)",
        "#define MGPT_SCALE_FRAC_BITS 16",
        "",
    ]

    one_d = [
        ("uint16_t", "g_wq_scale_q16", package["wq_scale_q16"]),
        ("uint16_t", "g_wk_scale_q16", package["wk_scale_q16"]),
        ("uint16_t", "g_wv_scale_q16", package["wv_scale_q16"]),
        ("uint16_t", "g_wo_scale_q16", package["wo_scale_q16"]),
        ("uint16_t", "g_fc1_scale_q16", package["fc1_scale_q16"]),
        ("uint16_t", "g_fc2_scale_q16", package["fc2_scale_q16"]),
        ("uint16_t", "g_lm_scale_q16", package["lm_scale_q16"]),
    ]
    two_d = [
        ("int16_t", "g_wte_q", package["wte_q"]),
        ("int16_t", "g_wpe_q", package["wpe_q"]),
        ("int8_t", "g_wq_q", package["wq_q"]),
        ("int8_t", "g_wk_q", package["wk_q"]),
        ("int8_t", "g_wv_q", package["wv_q"]),
        ("int8_t", "g_wo_q", package["wo_q"]),
        ("int8_t", "g_fc1_q", package["fc1_q"]),
        ("int8_t", "g_fc2_q", package["fc2_q"]),
        ("int8_t", "g_lm_q", package["lm_q"]),
    ]

    for ctype, name, array in one_d:
        lines.append(
            f"static const {ctype} {name}[{array.shape[0]}] = {{{_format_1d(array)}}};"
        )
    lines.append("")

    for ctype, name, array in two_d:
        lines.append(
            f"static const {ctype} {name}[{array.shape[0]}][{array.shape[1]}] = {{\n{_format_2d(array)}\n}};"
        )
        lines.append("")

    lines.append("#endif")
    path.write_text("\n".join(lines), encoding="ascii")


def write_manifest(path: Path, manifest: Dict[str, object]) -> None:
    path.write_text(json.dumps(manifest, indent=2), encoding="ascii")
