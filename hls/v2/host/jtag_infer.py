import argparse
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from microgpt_regs import BOARD_CLOCK_HZ, STATUS_DONE, STATUS_ERROR
from tools.microgpt_model import decode_tokens


def parse_value(line: str):
    return line.split("=", 1)[1].strip()


def normalize_console_line(raw_line: str) -> str:
    line = raw_line.strip()
    while line.startswith("%"):
        line = line[1:].strip()
    return line


def run_generator(args: argparse.Namespace) -> int:
    if args.steps < 1 or args.steps > 15:
        raise SystemExit("--steps must be between 1 and 15 because the 16-token context includes the initial BOS token.")
    env = os.environ.copy()
    env["MGPT_MAX_GEN"] = str(args.steps)
    env["MGPT_TEMP_Q8_8"] = str(int(round(args.temperature * 256.0)))
    env["MGPT_SEED"] = str(args.seed)
    env["MGPT_STREAM_TOKENS"] = "1"
    env["MGPT_POLL_MS"] = str(max(args.poll_ms, 1))
    env["MGPT_SAMPLE_COUNT"] = str(max(args.count, 1))

    script_path = Path(__file__).with_name("system_console_infer.tcl")
    script_text = script_path.read_text(encoding="utf-8")
    proc = subprocess.Popen(
        [args.system_console, "-cli", "-disable_readline"],
        cwd=Path(__file__).resolve().parents[1],
        env=env,
        text=True,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    assert proc.stdin is not None
    assert proc.stdout is not None
    proc.stdin.write(script_text)
    proc.stdin.close()

    sample_index = 0
    current_tokens = []
    meta_lines = []
    sample_statuses = []
    total_tokens = 0
    total_board_cycles = 0

    for raw_line in proc.stdout:
        line = normalize_console_line(raw_line)
        if not line:
            continue
        if line.startswith("SAMPLE_BEGIN="):
            current_tokens = []
            sample_index = int(parse_value(line))
            continue
        if line.startswith("STREAM_TOKEN="):
            token = int(parse_value(line), 0) & 0xFF
            current_tokens.append(token)
            total_tokens += 1
            sys.stdout.write(decode_tokens([token]))
            sys.stdout.flush()
            continue
        if line.startswith("SAMPLE_END="):
            if current_tokens:
                sys.stdout.write("\n")
            else:
                sys.stdout.write("(empty)\n")
            sys.stdout.flush()
            continue
        meta_lines.append(line)

    stderr_text = proc.stderr.read() if proc.stderr is not None else ""
    return_code = proc.wait()
    if return_code != 0:
        raise SystemExit(stderr_text or "\n".join(meta_lines))

    for line in meta_lines:
        if line.startswith("STATUS["):
            idx_text, value_text = line.split("=", 1)
            idx = int(idx_text[idx_text.find("[") + 1 : idx_text.find("]")], 10)
            status = int(value_text, 16)
            sample_statuses.append((idx, status))
        elif line.startswith("STREAM_CYCLES["):
            total_board_cycles += int(line.split("=", 1)[1], 10)

    bad_statuses = [status for _, status in sample_statuses if (status & STATUS_ERROR) or not (status & STATUS_DONE)]
    if bad_statuses:
        raise SystemExit(f"Generation failed: statuses={sample_statuses}")

    if args.verbose:
        print(f"samples={len(sample_statuses)}")
        for idx, status in sample_statuses:
            print(f"sample[{idx}] status=0x{status:08X} done={bool(status & STATUS_DONE)} error={bool(status & STATUS_ERROR)}")

    if total_board_cycles > 0 and total_tokens > 0:
        elapsed = total_board_cycles / BOARD_CLOCK_HZ
        tks = total_tokens / elapsed if elapsed > 0 else float("inf")
        us_per_tok = (elapsed / total_tokens) * 1_000_000 if total_tokens > 0 else 0
        print()
        print("-" * 40)
        print("  Hardware Benchmark")
        print(f"  Tokens generated : {total_tokens}")
        print(f"  Board cycles     : {total_board_cycles}")
        print(f"  Core time        : {elapsed:.6f} s")
        print(f"  Throughput       : {tks:.2f} tok/s")
        print(f"  Latency          : {us_per_tok:.2f} us/tok")
        print("-" * 40)

    return 0


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate sampled names from BOS over the DE1-SoC JTAG bridge.")
    parser.add_argument("--count", type=int, default=20, help="Number of names to generate.")
    parser.add_argument("--steps", type=int, default=15, help="Maximum tokens per name.")
    parser.add_argument("--temperature", type=float, default=0.5, help="Sampling temperature.")
    parser.add_argument("--seed", type=int, default=1, help="Initial RNG seed.")
    parser.add_argument("--poll-ms", type=int, default=1, help="Host polling interval while waiting for output.")
    parser.add_argument("--verbose", action="store_true", help="Print per-sample status words after generation.")
    parser.add_argument(
        "--system-console",
        default=r"C:\intelFPGA\18.1\quartus\sopc_builder\bin\system-console.exe",
    )
    args = parser.parse_args()
    raise SystemExit(run_generator(args))


if __name__ == "__main__":
    main()
