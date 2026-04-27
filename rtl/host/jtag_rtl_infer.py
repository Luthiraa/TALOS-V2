import argparse
import math
import os
import random
import subprocess
import sys
from pathlib import Path


N_EMBD = 16
BLOCK_SIZE = 16
BOS_TOKEN = 26
VOCAB_SIZE = 27
CORE_CLOCK_HZ = 56_250_000

ROOT_DIR = Path(__file__).resolve().parents[2]
RTL_DIR = Path(__file__).resolve().parents[1]
DEFAULT_NAMES_PATH = ROOT_DIR / "arm" / "training" / "names.txt"
DEFAULT_SYSTEM_CONSOLE = r"C:\intelFPGA\18.1\quartus\sopc_builder\bin\system-console.exe"


def parse_value(line: str) -> str:
    return line.split("=", 1)[1].strip()


def normalize_console_line(raw_line: str) -> str:
    line = raw_line.strip()
    while line.startswith("%"):
        line = line[1:].strip()
    return line


def parse_indexed_assignment(line: str, key: str) -> tuple[int, str] | None:
    prefix = f"{key}["
    if not line.startswith(prefix):
        return None
    idx_text, value = line.split("=", 1)
    idx = int(idx_text[idx_text.find("[") + 1 : idx_text.find("]")], 10)
    return idx, value.strip()


def decode_signed32(value: int) -> int:
    value &= 0xFFFFFFFF
    if value & 0x80000000:
        return value - 0x1_0000_0000
    return value


def compute_tokens_per_sec(token_count: int, perf_cycles: int) -> int:
    if perf_cycles <= 0 or token_count <= 0:
        return 0
    return int(round(token_count * CORE_CLOCK_HZ / perf_cycles))


def load_docs(path: Path) -> list[str]:
    return [line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def build_itos(docs: list[str]) -> dict[int, str]:
    uchars = sorted(set("".join(docs)))
    if len(uchars) != BOS_TOKEN:
        raise SystemExit(f"unexpected vocab size in {DEFAULT_NAMES_PATH}: expected 26 chars, got {len(uchars)}")
    return {idx: ch for idx, ch in enumerate(uchars)}


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


def softmax(logits: list[float]) -> list[float]:
    max_val = max(logits)
    exps = [math.exp(value - max_val) for value in logits]
    total = sum(exps)
    return [value / total for value in exps]


def xorshift32(state: int) -> int:
    state &= 0xFFFFFFFF
    state ^= (state << 13) & 0xFFFFFFFF
    state ^= (state >> 17) & 0xFFFFFFFF
    state ^= (state << 5) & 0xFFFFFFFF
    return state & 0xFFFFFFFF


def sample_from_logits_q12_xorshift(logits_q12: list[int], temperature: float, state: int) -> tuple[int, int]:
    if temperature <= 0.0:
        best_token = max(range(len(logits_q12)), key=lambda idx: logits_q12[idx])
        return best_token, state & 0xFFFFFFFF

    scaled = [(value / 4096.0) / temperature for value in logits_q12]
    probs = softmax(scaled)
    state = xorshift32(state)
    threshold = (state & 0xFFFFFF) / float(1 << 24)

    cdf = 0.0
    token = len(probs) - 1
    for idx, prob in enumerate(probs):
        cdf += prob
        if threshold < cdf:
            token = idx
            break
    return token, state


def sample_from_logits_python(logits_q12: list[int], temperature: float) -> int:
    scaled = [(value / 4096.0) / temperature for value in logits_q12]
    probs = softmax(scaled)
    return int(random.choices(range(len(probs)), weights=probs)[0])


def decode_token(token: int, itos: dict[int, str]) -> str:
    if token == BOS_TOKEN:
        return ""
    return itos.get(token, "?")


def parse_output_tokens(raw_value: str) -> list[int]:
    output_tokens = []
    for raw_token in raw_value.split():
        try:
            output_tokens.append(int(raw_token, 0) & 0xFF)
        except ValueError:
            pass
    return output_tokens


def finalize_rtl_sample(sample: dict[str, object], fallback_seed: int, itos: dict[int, str]) -> dict[str, object]:
    summary = dict(sample["summary"])
    output_tokens = parse_output_tokens(str(summary.get("OUTPUT_TOKENS", "")))
    if not output_tokens:
        output_tokens = list(sample["generated"])
    output_text = "".join(decode_token(token, itos) for token in output_tokens)
    status = int(str(summary.get("STATUS", "0")), 16)
    next_seed = int(str(summary.get("RNG_STATE", str(fallback_seed))), 0) & 0xFFFFFFFF
    perf_cycles = int(str(summary.get("PERF_CYCLES", "0")), 0)
    tokens_per_sec = compute_tokens_per_sec(len(output_tokens), perf_cycles)
    return {
        "index": int(sample["index"]),
        "summary": summary,
        "status": status,
        "output_tokens": output_tokens,
        "output_text": output_text,
        "next_seed": next_seed,
        "perf_cycles": perf_cycles,
        "tokens_per_sec": tokens_per_sec,
    }


def run_rtl_samples(
    script_path: Path,
    system_console: str,
    steps: int,
    count: int,
    temperature: float,
    seed: int,
    poll_ms: int,
    stream_tokens: bool,
    verbose: bool,
    itos: dict[int, str],
) -> list[dict[str, object]]:
    env = os.environ.copy()
    env["MGPT_MAX_GEN"] = str(steps)
    env["MGPT_SAMPLE_COUNT"] = str(count)
    env["MGPT_TEMP_Q8_8"] = str(int(round(temperature * 256.0)))
    env["MGPT_SEED"] = str(seed)
    env["MGPT_STREAM_TOKENS"] = "1" if stream_tokens else "0"
    env["MGPT_POLL_MS"] = str(max(poll_ms, 1))

    proc = subprocess.Popen(
        [system_console, "-cli", "-disable_readline"],
        cwd=RTL_DIR,
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

    samples: list[dict[str, object]] = []
    current_sample: dict[str, object] | None = None
    misc_meta: list[str] = []
    current_seed = seed

    for raw_line in proc.stdout:
        line = normalize_console_line(raw_line)
        if not line:
            continue

        if line.startswith("SAMPLE_BEGIN="):
            current_sample = {
                "index": int(parse_value(line), 0),
                "generated": [],
                "summary": {},
            }
            continue

        if line.startswith("STREAM_TOKEN="):
            token = int(parse_value(line), 0) & 0xFF
            if current_sample is not None:
                current_sample["generated"].append(token)
            if stream_tokens:
                sys.stdout.write(decode_token(token, itos))
                sys.stdout.flush()
            continue

        if line.startswith("SAMPLE_END="):
            if current_sample is None:
                misc_meta.append(line)
                continue
            sample_result = finalize_rtl_sample(current_sample, current_seed, itos)
            if sample_result["status"] & 0x8:
                raise SystemExit(f"hardware reported error: status=0x{sample_result['status']:08X}")
            if stream_tokens:
                sys.stdout.write("\n")
                sys.stdout.flush()
            elif count > 1:
                print(f"sample {int(sample_result['index']) + 1:2d}: {sample_result['output_text']}")
                if verbose:
                    print(f"  output_tokens={sample_result['summary'].get('OUTPUT_TOKENS', '')}")
                    print(f"  perf_cycles={int(sample_result['perf_cycles'])}")
                    print(f"  tokens_per_sec={int(sample_result['tokens_per_sec'])}")
                    print(f"  rng_state=0x{int(sample_result['next_seed']):08X}")
            samples.append(sample_result)
            current_seed = int(sample_result["next_seed"])
            current_sample = None
            continue

        matched = False
        for key in ("STATUS", "OUT_LEN", "RNG_STATE", "PERF_CYCLES", "OUTPUT_TOKENS"):
            parsed = parse_indexed_assignment(line, key)
            if parsed is not None:
                idx, value = parsed
                if current_sample is None or int(current_sample["index"]) != idx:
                    raise SystemExit(f"unexpected indexed metadata ordering: {line}")
                current_sample["summary"][key] = value
                matched = True
                break
        if matched:
            continue

        misc_meta.append(line)

    stderr_text = proc.stderr.read() if proc.stderr is not None else ""
    rc = proc.wait()
    if rc != 0:
        raise SystemExit(stderr_text or "\n".join(misc_meta))
    if current_sample is not None:
        raise SystemExit("system-console ended before SAMPLE_END was received")
    return samples


class SystemConsoleSession:
    def __init__(self, helper_path: Path, system_console: str) -> None:
        self.proc = subprocess.Popen(
            [system_console, "-cli", "-disable_readline"],
            cwd=RTL_DIR,
            text=True,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        assert self.proc.stdin is not None
        assert self.proc.stdout is not None
        self.stdin = self.proc.stdin
        self.stdout = self.proc.stdout
        self.stderr = self.proc.stderr
        self.stdin.write(helper_path.read_text(encoding="ascii"))
        self.stdin.flush()
        self._wait_for_line("SESSION_READY=1")

    def _read_line(self) -> str:
        raw_line = self.stdout.readline()
        if raw_line == "":
            stderr_text = self.stderr.read() if self.stderr is not None else ""
            raise SystemExit(stderr_text or "system-console terminated unexpectedly")
        return normalize_console_line(raw_line)

    def _wait_for_line(self, target: str) -> None:
        while True:
            line = self._read_line()
            if not line:
                continue
            if line == target:
                return

    def set_seed(self, seed: int) -> None:
        self.stdin.write(f"mgpt_seed {seed & 0xFFFFFFFF}\n")
        self.stdin.flush()
        self._wait_for_line("SEED_SET=1")

    def step(self, token: int, pos: int, clear_cache: bool, poll_ms: int) -> dict[str, object]:
        self.stdin.write(f"mgpt_step {token} {pos} {1 if clear_cache else 0} {poll_ms}\n")
        self.stdin.flush()

        result: dict[str, object] = {
            "status": 0,
            "rng_state": 0,
            "perf_cycles": 0,
            "top_arg_word": 0,
            "logits_q12": [0] * VOCAB_SIZE,
        }

        while True:
            line = self._read_line()
            if not line:
                continue
            if line == "STEP_END=1":
                return result
            if line == "STEP_TIMEOUT=1":
                raise SystemExit("direct-step JTAG session timed out")
            if line.startswith("STEP_STATUS="):
                result["status"] = int(parse_value(line), 0)
                continue
            if line.startswith("STEP_RNG_STATE="):
                result["rng_state"] = int(parse_value(line), 0) & 0xFFFFFFFF
                continue
            if line.startswith("STEP_PERF_CYCLES="):
                result["perf_cycles"] = int(parse_value(line), 0)
                continue
            if line.startswith("STEP_TOP_ARG="):
                result["top_arg_word"] = int(parse_value(line), 0) & 0xFFFFFFFF
                continue
            if line.startswith("STEP_LOGITS="):
                logits = [decode_signed32(int(value, 0)) for value in parse_value(line).split()]
                if len(logits) != VOCAB_SIZE:
                    raise SystemExit(f"unexpected logit count from system-console: {len(logits)}")
                result["logits_q12"] = logits
                continue
            parsed = parse_indexed_assignment(line, "STEP_LOGIT")
            if parsed is not None:
                idx, value = parsed
                result["logits_q12"][idx] = decode_signed32(int(value, 0))
                continue

    def close(self) -> None:
        if self.proc.poll() is None:
            self.stdin.write("mgpt_close\n")
            self.stdin.flush()
            self.stdin.close()
        stderr_text = self.stderr.read() if self.stderr is not None else ""
        rc = self.proc.wait()
        if rc != 0:
            raise SystemExit(stderr_text or f"system-console exited with code {rc}")


def run_python_samples(
    helper_path: Path,
    system_console: str,
    steps: int,
    count: int,
    temperature: float,
    poll_ms: int,
    stream_tokens: bool,
    verbose: bool,
    docs: list[str],
    itos: dict[int, str],
) -> list[dict[str, object]]:
    consume_training_rng_state(list(docs), VOCAB_SIZE)
    session = SystemConsoleSession(helper_path=helper_path, system_console=system_console)
    samples: list[dict[str, object]] = []

    try:
        for sample_idx in range(count):
            token = BOS_TOKEN
            clear_cache = True
            perf_cycles = 0
            output_tokens: list[int] = []

            for pos in range(min(steps, BLOCK_SIZE)):
                step_result = session.step(token=token, pos=pos, clear_cache=clear_cache, poll_ms=poll_ms)
                status = int(step_result["status"])
                if status & 0x8:
                    raise SystemExit(f"hardware reported error: status=0x{status:08X}")
                perf_cycles += int(step_result["perf_cycles"])

                token = sample_from_logits_python(list(step_result["logits_q12"]), temperature)
                if token == BOS_TOKEN:
                    break

                output_tokens.append(token)
                if stream_tokens:
                    sys.stdout.write(decode_token(token, itos))
                    sys.stdout.flush()
                clear_cache = False

            output_text = "".join(decode_token(token_id, itos) for token_id in output_tokens)
            sample_result = {
                "index": sample_idx,
                "status": 0x4,
                "output_tokens": output_tokens,
                "output_text": output_text,
                "perf_cycles": perf_cycles,
                "tokens_per_sec": compute_tokens_per_sec(len(output_tokens), perf_cycles),
                "next_seed": 0,
                "summary": {
                    "OUT_LEN": str(len(output_tokens)),
                    "PERF_CYCLES": str(perf_cycles),
                    "OUTPUT_TOKENS": " ".join(str(token_id) for token_id in output_tokens),
                },
            }
            if stream_tokens:
                sys.stdout.write("\n")
                sys.stdout.flush()
            elif count > 1:
                print(f"sample {sample_idx + 1:2d}: {output_text}")
                if verbose:
                    print(f"  output_tokens={sample_result['summary']['OUTPUT_TOKENS']}")
                    print(f"  perf_cycles={perf_cycles}")
                    print(f"  tokens_per_sec={sample_result['tokens_per_sec']}")
            samples.append(sample_result)
    finally:
        session.close()

    return samples


def run_python_xorshift_samples(
    helper_path: Path,
    system_console: str,
    steps: int,
    count: int,
    temperature: float,
    seed: int,
    poll_ms: int,
    stream_tokens: bool,
    verbose: bool,
    itos: dict[int, str],
) -> list[dict[str, object]]:
    session = SystemConsoleSession(helper_path=helper_path, system_console=system_console)
    samples: list[dict[str, object]] = []
    sampler_seed = seed & 0xFFFFFFFF

    try:
        for sample_idx in range(count):
            token = BOS_TOKEN
            clear_cache = True
            perf_cycles = 0
            output_tokens: list[int] = []

            for pos in range(min(steps, BLOCK_SIZE)):
                step_result = session.step(token=token, pos=pos, clear_cache=clear_cache, poll_ms=poll_ms)
                status = int(step_result["status"])
                if status & 0x8:
                    raise SystemExit(f"hardware reported error: status=0x{status:08X}")
                perf_cycles += int(step_result["perf_cycles"])

                token, sampler_seed = sample_from_logits_q12_xorshift(
                    list(step_result["logits_q12"]), temperature, sampler_seed
                )
                if token == BOS_TOKEN:
                    break

                output_tokens.append(token)
                if stream_tokens:
                    sys.stdout.write(decode_token(token, itos))
                    sys.stdout.flush()
                clear_cache = False

            output_text = "".join(decode_token(token_id, itos) for token_id in output_tokens)
            sample_result = {
                "index": sample_idx,
                "status": 0x4,
                "output_tokens": output_tokens,
                "output_text": output_text,
                "perf_cycles": perf_cycles,
                "tokens_per_sec": compute_tokens_per_sec(len(output_tokens), perf_cycles),
                "next_seed": sampler_seed,
                "summary": {
                    "OUT_LEN": str(len(output_tokens)),
                    "PERF_CYCLES": str(perf_cycles),
                    "OUTPUT_TOKENS": " ".join(str(token_id) for token_id in output_tokens),
                    "RNG_STATE": f"0x{sampler_seed:08X}",
                },
            }
            if stream_tokens:
                sys.stdout.write("\n")
                sys.stdout.flush()
            elif count > 1:
                print(f"sample {sample_idx + 1:2d}: {output_text}")
                if verbose:
                    print(f"  output_tokens={sample_result['summary']['OUTPUT_TOKENS']}")
                    print(f"  perf_cycles={perf_cycles}")
                    print(f"  tokens_per_sec={sample_result['tokens_per_sec']}")
                    print(f"  rng_state=0x{sampler_seed:08X}")
            samples.append(sample_result)
    finally:
        session.close()

    return samples


def main() -> int:
    parser = argparse.ArgumentParser(description="Read RTL microgpt output over JTAG.")
    parser.add_argument("--steps", type=int, default=15)
    parser.add_argument("--count", type=int, default=1)
    parser.add_argument("--temperature", type=float, default=0.5)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--poll-ms", type=int, default=0)
    parser.add_argument("--stream", action="store_true")
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--sampler", choices=("python", "python-xorshift", "rtl"), default="python")
    parser.add_argument("--names", default=str(DEFAULT_NAMES_PATH))
    parser.add_argument("--system-console", default=DEFAULT_SYSTEM_CONSOLE)
    args = parser.parse_args()

    if args.steps < 1 or args.steps > 15:
        raise SystemExit("--steps must be between 1 and 15")
    if args.count < 1:
        raise SystemExit("--count must be at least 1")
    if args.temperature <= 0.0:
        raise SystemExit("--temperature must be greater than 0")
    if args.poll_ms < 0:
        raise SystemExit("--poll-ms must be non-negative")

    names_path = Path(args.names)
    if not names_path.is_absolute():
        names_path = ROOT_DIR / names_path
    docs = load_docs(names_path)
    itos = build_itos(docs)

    if args.sampler == "rtl":
        samples = run_rtl_samples(
            script_path=Path(__file__).with_name("system_console_rtl_infer.tcl"),
            system_console=args.system_console,
            steps=args.steps,
            count=args.count,
            temperature=args.temperature,
            seed=args.seed,
            poll_ms=args.poll_ms,
            stream_tokens=args.stream and args.count == 1,
            verbose=args.verbose and args.count > 1,
            itos=itos,
        )
    elif args.sampler == "python":
        samples = run_python_samples(
            helper_path=Path(__file__).with_name("system_console_rtl_session.tcl"),
            system_console=args.system_console,
            steps=args.steps,
            count=args.count,
            temperature=args.temperature,
            poll_ms=args.poll_ms,
            stream_tokens=args.stream,
            verbose=args.verbose and args.count > 1,
            docs=docs,
            itos=itos,
        )
    else:
        samples = run_python_xorshift_samples(
            helper_path=Path(__file__).with_name("system_console_rtl_session.tcl"),
            system_console=args.system_console,
            steps=args.steps,
            count=args.count,
            temperature=args.temperature,
            seed=args.seed,
            poll_ms=args.poll_ms,
            stream_tokens=args.stream,
            verbose=args.verbose and args.count > 1,
            itos=itos,
        )

    if not samples:
        raise SystemExit("no samples were returned by system-console")

    total_perf_cycles = sum(int(sample["perf_cycles"]) for sample in samples)
    total_generated_tokens = sum(len(list(sample["output_tokens"])) for sample in samples)
    all_texts = [str(sample["output_text"]) for sample in samples]

    if args.count == 1:
        sample = samples[0]
        print()
        print("JTAG packet:")
        print(f"  sampler={args.sampler}")
        print(f"  output_tokens={sample['summary'].get('OUTPUT_TOKENS', '')}")
        print(f"  output_text={sample['output_text']}")
        print(f"  out_len={sample['summary'].get('OUT_LEN', '0')}")
        print(f"  perf_cycles={int(sample['perf_cycles'])}")
        print(f"  tokens_per_sec={int(sample['tokens_per_sec'])}")
        if args.sampler == "python":
            print("  rng_state=python_random")
        else:
            print(f"  rng_state=0x{int(sample['next_seed']):08X}")
        return 0

    aggregate_tps = compute_tokens_per_sec(total_generated_tokens, total_perf_cycles)
    print()
    print("JTAG packet:")
    print(f"  sampler={args.sampler}")
    print(f"  samples={args.count}")
    print(f"  output_texts={all_texts}")
    print(f"  total_generated_tokens={total_generated_tokens}")
    print(f"  total_perf_cycles={total_perf_cycles}")
    print(f"  aggregate_tokens_per_sec={aggregate_tps}")
    if args.sampler == "python":
        print("  final_rng_state=python_random")
    else:
        print(f"  final_rng_state=0x{int(samples[-1]['next_seed']):08X}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
