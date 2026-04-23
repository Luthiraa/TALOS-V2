import argparse
import os
import subprocess
import sys
from pathlib import Path


ITOS = {idx: ch for idx, ch in enumerate("abcdefghijklmnopqrstuvwxyz^")}
BOS_TOKEN = 26


def parse_value(line: str) -> str:
    return line.split("=", 1)[1].strip()


def normalize_console_line(raw_line: str) -> str:
    line = raw_line.strip()
    while line.startswith("%"):
        line = line[1:].strip()
    return line


def decode_token(token: int) -> str:
    if token == BOS_TOKEN:
        return ""
    return ITOS.get(token, "?")


def parse_output_tokens(raw_value: str) -> list[int]:
    output_tokens = []
    for raw_token in raw_value.split():
        try:
            output_tokens.append(int(raw_token, 0) & 0xFF)
        except ValueError:
            pass
    return output_tokens


def run_one_sample(
    rtl_dir: Path,
    script_path: Path,
    system_console: str,
    steps: int,
    temperature: float,
    seed: int,
    poll_ms: int,
    stream_tokens: bool,
) -> dict[str, object]:
    env = os.environ.copy()
    env["MGPT_MAX_GEN"] = str(steps)
    env["MGPT_TEMP_Q8_8"] = str(int(round(temperature * 256.0)))
    env["MGPT_SEED"] = str(seed)
    env["MGPT_STREAM_TOKENS"] = "1" if stream_tokens else "0"
    env["MGPT_POLL_MS"] = str(max(poll_ms, 1))

    proc = subprocess.Popen(
        [system_console, "-cli", "-disable_readline"],
        cwd=rtl_dir,
        env=env,
        text=True,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    assert proc.stdin is not None
    assert proc.stdout is not None
    proc.stdin.write(script_path.read_text(encoding="ascii"))
    proc.stdin.close()

    meta = []
    generated = []
    for raw_line in proc.stdout:
        line = normalize_console_line(raw_line)
        if not line:
            continue
        if line.startswith("STREAM_TOKEN="):
            token = int(parse_value(line), 0) & 0xFF
            generated.append(token)
        else:
            meta.append(line)

    stderr_text = proc.stderr.read() if proc.stderr is not None else ""
    rc = proc.wait()
    if rc != 0:
        raise SystemExit(stderr_text or "\n".join(meta))

    summary: dict[str, str] = {}
    for line in meta:
        if "=" in line:
            key, value = line.split("=", 1)
            summary[key] = value

    status = int(summary.get("STATUS", "0"), 16)
    if status & 0x8:
        raise SystemExit(f"hardware reported error: status=0x{status:08X}")

    output_tokens = parse_output_tokens(summary.get("OUTPUT_TOKENS", ""))
    output_text = "".join(decode_token(token) for token in output_tokens)
    next_seed = int(summary.get("RNG_STATE", str(seed)), 0) & 0xFFFFFFFF

    return {
        "generated": generated,
        "meta": meta,
        "summary": summary,
        "status": status,
        "output_tokens": output_tokens,
        "output_text": output_text,
        "next_seed": next_seed,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Read the RTL microgpt output over JTAG.")
    parser.add_argument("--steps", type=int, default=15)
    parser.add_argument("--count", type=int, default=1)
    parser.add_argument("--temperature", type=float, default=0.5)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--poll-ms", type=int, default=5)
    parser.add_argument("--stream", action="store_true")
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument(
        "--system-console",
        default=r"C:\intelFPGA\18.1\quartus\sopc_builder\bin\system-console.exe",
    )
    args = parser.parse_args()

    if args.steps < 1 or args.steps > 15:
        raise SystemExit("--steps must be between 1 and 15")
    if args.count < 1:
        raise SystemExit("--count must be at least 1")

    rtl_dir = Path(__file__).resolve().parents[1]
    script_path = Path(__file__).with_name("system_console_rtl_infer.tcl")

    seed = args.seed
    all_texts: list[str] = []
    total_perf_cycles = 0
    total_generated_tokens = 0
    last_result: dict[str, object] | None = None

    for sample_idx in range(args.count):
        result = run_one_sample(
            rtl_dir=rtl_dir,
            script_path=script_path,
            system_console=args.system_console,
            steps=args.steps,
            temperature=args.temperature,
            seed=seed,
            poll_ms=args.poll_ms,
            stream_tokens=args.stream and args.count == 1,
        )
        last_result = result
        output_text = str(result["output_text"])
        output_tokens = list(result["output_tokens"])
        summary = dict(result["summary"])

        total_perf_cycles += int(summary.get("PERF_CYCLES", "0"), 0)
        total_generated_tokens += len(output_tokens)
        all_texts.append(output_text)

        if args.count == 1:
            if args.stream:
                sys.stdout.write(output_text)
                sys.stdout.flush()
                if output_text:
                    print()
            print()
            print("JTAG packet:")
            print(f"  output_tokens={summary.get('OUTPUT_TOKENS', '')}")
            print(f"  output_text={output_text}")
            print(f"  out_len={summary.get('OUT_LEN', '0')}")
            print(f"  perf_cycles={summary.get('PERF_CYCLES', '0')}")
            print(f"  tokens_per_sec={summary.get('TOKENS_PER_SEC', '0')}")
            print(f"  rng_state=0x{int(result['next_seed']):08X}")
            if args.verbose:
                for line in result["meta"]:
                    print(line)
        else:
            print(f"sample {sample_idx + 1:2d}: {output_text}")
            if args.verbose:
                print(f"  output_tokens={summary.get('OUTPUT_TOKENS', '')}")
                print(f"  perf_cycles={summary.get('PERF_CYCLES', '0')}")
                print(f"  tokens_per_sec={summary.get('TOKENS_PER_SEC', '0')}")
                print(f"  rng_state=0x{int(result['next_seed']):08X}")

        seed = int(result["next_seed"])

    if args.count > 1 and last_result is not None:
        aggregate_tps = 0
        if total_perf_cycles > 0:
            aggregate_tps = int(round(total_generated_tokens * 12_500_000 / total_perf_cycles))
        print()
        print("JTAG packet:")
        print(f"  samples={args.count}")
        print(f"  output_texts={all_texts}")
        print(f"  total_generated_tokens={total_generated_tokens}")
        print(f"  total_perf_cycles={total_perf_cycles}")
        print(f"  aggregate_tokens_per_sec={aggregate_tps}")
        print(f"  final_rng_state=0x{seed:08X}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
