import argparse
from pathlib import Path

from microgpt_model import build_quantized_package, load_flat_weights, parse_flat_weights


def to_hex_lines(values, bits: int):
    mask = (1 << bits) - 1
    width = bits // 4
    return "\n".join(f"{(int(v) & mask):0{width}x}" for v in values) + "\n"


def write_hex(path: Path, values, bits: int) -> None:
    path.write_text(to_hex_lines(values, bits), encoding="ascii")


def main() -> None:
    parser = argparse.ArgumentParser(description="Export compact ROM init files for the RTL microgpt core.")
    parser.add_argument("--weights", default="model_weights.npy")
    parser.add_argument("--outdir", default="generated")
    args = parser.parse_args()

    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    weights = parse_flat_weights(load_flat_weights(Path(args.weights)))
    package = build_quantized_package(weights)

    write_hex(outdir / "wte_q.hex", package["wte_q"].reshape(-1), 16)
    write_hex(outdir / "wpe_q.hex", package["wpe_q"].reshape(-1), 16)
    write_hex(outdir / "wq_q.hex", package["wq_q"].reshape(-1), 8)
    write_hex(outdir / "wq_scale_q16.hex", package["wq_scale_q16"], 16)
    write_hex(outdir / "lm_q.hex", package["lm_q"].reshape(-1), 8)
    write_hex(outdir / "lm_scale_q16.hex", package["lm_scale_q16"], 16)

    print(f"rom_dir={outdir}")
    print("rom_files=wte_q.hex,wpe_q.hex,wq_q.hex,wq_scale_q16.hex,lm_q.hex,lm_scale_q16.hex")


if __name__ == "__main__":
    main()
