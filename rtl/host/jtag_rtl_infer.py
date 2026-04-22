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


def main() -> int:
    parser = argparse.ArgumentParser(description="Read the RTL microgpt output over JTAG.")
    parser.add_argument("--steps", type=int, default=15)
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

    rtl_dir = Path(__file__).resolve().parents[1]
    script_path = Path(__file__).with_name("system_console_rtl_infer.tcl")

    env = os.environ.copy()
    env["MGPT_MAX_GEN"] = str(args.steps)
    env["MGPT_TEMP_Q8_8"] = str(int(round(args.temperature * 256.0)))
    env["MGPT_SEED"] = str(args.seed)
    env["MGPT_STREAM_TOKENS"] = "1" if args.stream else "0"
    env["MGPT_POLL_MS"] = str(max(args.poll_ms, 1))

    proc = subprocess.Popen(
        [args.system_console, "-cli", "-disable_readline"],
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
            sys.stdout.write(decode_token(token))
            sys.stdout.flush()
        else:
            meta.append(line)

    stderr_text = proc.stderr.read() if proc.stderr is not None else ""
    rc = proc.wait()
    if generated:
        print()
    if rc != 0:
        raise SystemExit(stderr_text or "\n".join(meta))

    summary = {}
    for line in meta:
        if "=" in line:
            key, value = line.split("=", 1)
            summary[key] = value

    status = int(summary.get("STATUS", "0"), 16)
    if status & 0x8:
        raise SystemExit(f"hardware reported error: status=0x{status:08X}")

    print()
    print("JTAG packet:")
    print(f"  output_tokens={summary.get('OUTPUT_TOKENS', '')}")
    output_tokens = []
    for raw_token in summary.get("OUTPUT_TOKENS", "").split():
        try:
            output_tokens.append(int(raw_token, 0) & 0xFF)
        except ValueError:
            pass
    if output_tokens:
        output_text = "".join(decode_token(token) for token in output_tokens)
        print(f"  output_text={output_text}")
    print(f"  out_len={summary.get('OUT_LEN', '0')}")
    print(f"  perf_cycles={summary.get('PERF_CYCLES', '0')}")
    print(f"  tokens_per_sec={summary.get('TOKENS_PER_SEC', '0')}")
    if args.verbose:
        for line in meta:
            print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
