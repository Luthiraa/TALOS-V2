import argparse
from pathlib import Path

from microgpt_model import (
    build_quantized_package,
    load_flat_weights,
    parse_flat_weights,
    quant_manifest,
    write_header,
    write_manifest,
)


def main() -> None:
    parser = argparse.ArgumentParser(description="Export Karpathy microgpt weights for FPGA HLS.")
    parser.add_argument(
        "--weights",
        default="model_weights.npy",
        help="Path to the flat 4192-entry model_weights.npy file.",
    )
    parser.add_argument(
        "--header",
        default="generated/microgpt_model.h",
        help="Output C header used by the HLS build.",
    )
    parser.add_argument(
        "--manifest",
        default="generated/model_manifest.json",
        help="Output JSON manifest with tensor sizes and packing stats.",
    )
    args = parser.parse_args()

    weights_path = Path(args.weights)
    header_path = Path(args.header)
    manifest_path = Path(args.manifest)

    flat = load_flat_weights(weights_path)
    weights = parse_flat_weights(flat)
    package = build_quantized_package(weights)

    header_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.parent.mkdir(parents=True, exist_ok=True)

    write_header(header_path, package)
    write_manifest(manifest_path, quant_manifest(weights, package))

    packed_total = sum(v.nbytes for v in package.values())
    print(f"exported_header={header_path}")
    print(f"exported_manifest={manifest_path}")
    print(f"packed_bytes={packed_total}")


if __name__ == "__main__":
    main()
