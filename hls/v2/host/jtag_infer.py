import argparse
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from microgpt_regs import STATUS_DONE, STATUS_ERROR
from tools.microgpt_model import BOS_TOKEN, decode_tokens, encode_prompt


def parse_line(prefix: str, lines):
    for line in lines:
        if line.startswith(prefix):
            return line.split("=", 1)[1].strip()
    return None


def normalize_console_line(raw_line: str) -> str:
    line = raw_line.strip()
    while line.startswith("%"):
        line = line[1:].strip()
    return line


def run_inference(args: argparse.Namespace, prompt: str, stream: bool) -> int:
    prompt_tokens = encode_prompt(prompt)
    if len(prompt_tokens) >= 16:
        raise ValueError("Prompt must be shorter than 16 characters.")

    env = os.environ.copy()
    env["MGPT_PROMPT_TOKENS"] = " ".join(str(t) for t in prompt_tokens)
    env["MGPT_MAX_GEN"] = str(args.steps)
    env["MGPT_TEMP_Q8_8"] = str(int(round(args.temperature * 256.0)))
    env["MGPT_SEED"] = str(args.seed)
    env["MGPT_STREAM_TOKENS"] = "1" if stream else "0"
    env["MGPT_POLL_MS"] = str(max(args.poll_ms, 1))

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
    streamed_tokens = []
    meta_lines = []
    for raw_line in proc.stdout:
        line = normalize_console_line(raw_line)
        if not line:
            continue
        if line.startswith("STREAM_TOKEN="):
            token = int(line.split("=", 1)[1], 0) & 0xFF
            if token != BOS_TOKEN:
                streamed_tokens.append(token)
                sys.stdout.write(decode_tokens([token]))
                sys.stdout.flush()
            continue
        meta_lines.append(line)

    stderr_text = proc.stderr.read() if proc.stderr is not None else ""
    return_code = proc.wait()
    if stream and streamed_tokens:
        sys.stdout.write("\n")
        sys.stdout.flush()

    if return_code != 0:
        raise SystemExit(stderr_text or "\n".join(meta_lines))

    status_text = parse_line("STATUS", meta_lines)
    if status_text is None:
        raise SystemExit("System Console did not return STATUS.")

    status = int(status_text, 16)
    out_len = int(parse_line("OUT_LEN", meta_lines) or "0")
    token_text = parse_line("OUTPUT_TOKENS", meta_lines) or ""
    token_text = token_text.strip("{}")
    tokens = [int(piece, 0) & 0xFF for piece in token_text.split() if piece]
    tokens = [t for t in tokens[:out_len] if t != BOS_TOKEN]

    if stream:
        print(f"status=0x{status:08X}")
        print(f"done={bool(status & STATUS_DONE)} error={bool(status & STATUS_ERROR)}")
        print(f"tokens={tokens}")
        print(f"text={decode_tokens(tokens)}")
    else:
        print(f"status=0x{status:08X}")
        print(f"done={bool(status & STATUS_DONE)} error={bool(status & STATUS_ERROR)}")
        print(f"tokens={tokens}")
        print(f"text={decode_tokens(tokens)}")

    return status


def interactive_loop(args: argparse.Namespace) -> None:
    print("Interactive mode. Enter a prompt up to 15 characters. Empty input reruns the last prompt. Type 'quit' to exit.")
    last_prompt = args.prompt
    while True:
        try:
            prompt = input("prompt> ")
        except EOFError:
            print()
            break

        prompt = prompt.strip().lower()
        if prompt in {"quit", "exit"}:
            break
        if not prompt:
            if not last_prompt:
                print("No previous prompt. Enter a prompt first.")
                continue
            prompt = last_prompt
        last_prompt = prompt
        run_inference(args, prompt, stream=True)


def main() -> None:
    parser = argparse.ArgumentParser(description="Run microgpt inference over the DE1-SoC JTAG bridge.")
    parser.add_argument("--prompt", default="")
    parser.add_argument("--steps", type=int, default=8)
    parser.add_argument("--temperature", type=float, default=1.0)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--stream", action="store_true", help="Print tokens as they appear on the FPGA output buffer.")
    parser.add_argument("--interactive", action="store_true", help="Keep reading prompts from the PC console.")
    parser.add_argument("--poll-ms", type=int, default=1, help="Host polling interval while waiting for output.")
    parser.add_argument(
        "--system-console",
        default=r"C:\intelFPGA\18.1\quartus\sopc_builder\bin\system-console.exe",
    )
    args = parser.parse_args()

    if args.interactive or not args.prompt:
        interactive_loop(args)
    else:
        run_inference(args, args.prompt.lower(), stream=args.stream)


if __name__ == "__main__":
    main()
