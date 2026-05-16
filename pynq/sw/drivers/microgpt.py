"""microgpt.py -- PYNQ host driver for the TALOS-V2 microGPT overlay.

DE1 deviation: replaces the JTAG-master Avalon-MM bridge / Windows
`microgpt_bos_start.exe` flow with a `pynq.Overlay` + `pynq.MMIO` driver
that talks to the AXI4-Lite slave at 0x4000_0000.
"""

from __future__ import annotations

import asyncio
import os
import time
from pathlib import Path
from typing import List, Optional

import numpy as np
from pynq import Overlay, MMIO


# ---------------------------------------------------------------------------
# Register map (matches hw/src/top/microgpt_pynq_top.sv)
# ---------------------------------------------------------------------------
REG_MAGIC       = 0x000  # RO
REG_VERSION     = 0x004  # RO
REG_CMD         = 0x008  # WO  bit0=start, bit1=clear
REG_STATUS      = 0x00C  # RO
REG_CONFIG      = 0x010  # RW  {temp_q8_8[31:16], max_gen[15:8], 0[7:0]}
REG_SEED        = 0x014  # RW
REG_LOGIT_INFO  = 0x018  # RO  {top_logit_q12[31:16], argmax[15:8], last[7:0]}
REG_BOS         = 0x01C  # RO
REG_STEP_CFG    = 0x020  # RW
REG_STEP_TRIG   = 0x024  # WO  bit0
REG_OUT_BASE    = 0x060  # RO  16 x u8 tokens (one per word, LSB)
REG_PERF_CYC    = 0x0D8  # RO
REG_TPS         = 0x0DC  # RO
REG_LOGITS_BASE = 0x100  # RO  27 x s16 (sign-extended in low 16 bits)

MAGIC_EXPECTED   = 0x4D475254  # "MGRT"
VERSION_EXPECTED = 0x00020001

DEFAULT_BITFILE = (
    Path(__file__).resolve().parent.parent.parent / "overlays" / "microgpt.bit"
)

# Tiny vocab from rtl/microgpt/names.txt -- 26 letters + BOS/EOS sentinel.
TOKEN_ALPHABET = "abcdefghijklmnopqrstuvwxyz"
BOS_TOKEN_ID = 26


def _temperature_to_q8_8(temperature: float) -> int:
    """Convert a float temperature to unsigned Q8.8 used by the core."""
    if temperature <= 0.0:
        raise ValueError("temperature must be > 0")
    q = int(round(temperature * 256.0))
    if q < 1:
        q = 1
    if q > 0xFFFF:
        q = 0xFFFF
    return q


class MicroGPT:
    """Minimum-viable host driver for the microGPT overlay.

    Example:
        gpt = MicroGPT()
        name, info = gpt.generate(max_tokens=8, temperature=1.0, seed=42)
    """

    AXI_BASE = 0x40000000
    AXI_RANGE = 0x1000

    def __init__(
        self,
        bitfile: Optional[os.PathLike] = None,
        download: bool = True,
        use_irq: bool = False,
    ) -> None:
        # Why use_irq defaults to False: per-call completion is ~150-300 us
        # of RTL work. The spin-poll over the cached uint32 STATUS view
        # (introduced with the mmio.array refactor) takes <1 us per
        # iteration, so the whole wait costs <100 us of CPU. Routing that
        # through Linux uio + a context switch costs ~300 us per call here.
        # We measured both on this overlay: busy-poll is the winner. The
        # IRQ infrastructure (RTL output, BD wiring, /dev/uio<fabric>) is
        # all in place if you set use_irq=True -- valuable for future
        # workloads where each call is milliseconds (larger model,
        # async multi-stream, etc), but the sub-ms regime favours spinning.
        bit_path = Path(bitfile) if bitfile is not None else DEFAULT_BITFILE
        if not bit_path.exists():
            raise FileNotFoundError(
                f"Overlay bitstream not found: {bit_path}. "
                "Build it with `vivado -mode batch -source hw/tcl/build.tcl`."
            )
        self.overlay = Overlay(str(bit_path), download=download)
        self.mmio = MMIO(self.AXI_BASE, self.AXI_RANGE)
        # Zero-copy uint32 view of the AXI-Lite window. Indexed access goes
        # straight to the bus without per-MMIO-method Python overhead, which
        # is the per-call hot path's biggest cost. Bench shows ~1.5x on
        # `gpt.generate()` end-to-end vs the old self.mmio.read/write API.
        self._u32 = np.asarray(self.mmio.array, dtype=np.uint32)
        self._sanity_check()

        # PL->PS interrupt setup. The build.tcl wires microgpt_0/done_irq
        # straight to ps7_0/IRQ_F2P[0] through an xlconcat -- this is the
        # minimum-overhead path on Zynq-7000, but PYNQ's Interrupt class
        # only auto-discovers irqs that go through an axi_intc IP, so the
        # high-level API doesn't see ours. The uio kernel driver still
        # creates /dev/uioN with name="fabric" (covering all PL irqs); we
        # bind to that directly with os.read/os.write -- one blocking read
        # per generation instead of the busy-poll loop.
        self._uio_fd = -1
        if use_irq:
            try:
                self._uio_fd = self._open_fabric_uio()
            except Exception:
                self._uio_fd = -1

    # ---- low-level helpers -------------------------------------------------
    # _read/_write keep their old shape so external callers (and notebook
    # examples) still work, but they use the cached uint32 view internally.
    def _read(self, offset: int) -> int:
        return int(self._u32[offset >> 2])

    def _write(self, offset: int, value: int) -> None:
        self._u32[offset >> 2] = np.uint32(int(value) & 0xFFFFFFFF)

    def _sanity_check(self) -> None:
        magic = self._read(REG_MAGIC)
        version = self._read(REG_VERSION)
        if magic != MAGIC_EXPECTED:
            raise RuntimeError(
                f"Bad magic 0x{magic:08X} at 0x{REG_MAGIC:03X}; "
                f"expected 0x{MAGIC_EXPECTED:08X}."
            )
        if version != VERSION_EXPECTED:
            raise RuntimeError(
                f"Unexpected version 0x{version:08X}; expected 0x{VERSION_EXPECTED:08X}."
            )

    # ---- public API --------------------------------------------------------
    def reset(self) -> None:
        """Issue a clear pulse and wait for the core to return to ready."""
        self._write(REG_CMD, 0x2)  # bit1 = clear
        self._wait_ready()

    def status(self) -> dict:
        return self._unpack_status(int(self._u32[REG_STATUS >> 2]))

    def _wait_ready(self, timeout_s: float = 1.0) -> None:
        end = time.monotonic() + timeout_s
        u32 = self._u32
        idx = REG_STATUS >> 2
        spin = 0
        while True:
            s = int(u32[idx])
            # ready=bit0, busy=bit1
            if (s & 0x1) and not (s & 0x2):
                return
            spin += 1
            # Only check the wall clock every ~4096 spins -- saves a syscall
            # per polled iteration on the (very common) sub-millisecond path.
            if (spin & 0xFFF) == 0 and time.monotonic() > end:
                raise TimeoutError("microGPT did not return to ready in time.")

    @staticmethod
    def _open_fabric_uio() -> int:
        """Locate /dev/uioN named 'fabric' and open it for irq waits.

        Raises OSError / FileNotFoundError if no fabric uio is available.
        """
        sys_uio = "/sys/class/uio"
        for entry in sorted(os.listdir(sys_uio)):
            try:
                with open(os.path.join(sys_uio, entry, "name")) as f:
                    if f.read().strip() == "fabric":
                        fd = os.open(os.path.join("/dev", entry), os.O_RDWR)
                        # Arm the interrupt -- subsequent os.read blocks
                        # until the line transitions to active.
                        os.write(fd, (1).to_bytes(4, "little"))
                        return fd
            except OSError:
                continue
        raise FileNotFoundError("No /dev/uioN named 'fabric' found")

    def _wait_done(self, timeout_s: float = 5.0) -> dict:
        # Fast path: read /dev/uio<fabric>. The kernel blocks the read until
        # IRQ_F2P[0] (i.e. our done_irq) goes high. Spurious wake-ups can
        # happen because our irq line is level-held until the next call's
        # start_pulse clears it (so the kernel may queue an extra event when
        # it re-arms the irq with the line still high); we tolerate that by
        # reading STATUS after each wake and looping until done is actually
        # set.
        if self._uio_fd >= 0:
            import select
            u32 = self._u32
            sidx = REG_STATUS >> 2
            end  = time.monotonic() + timeout_s
            while True:
                # Block in the kernel until next irq, with a per-iteration
                # timeout so we can still surface a real hang.
                remaining = max(0.001, end - time.monotonic())
                r, _, _ = select.select([self._uio_fd], [], [], remaining)
                if not r:
                    raise TimeoutError("microGPT did not finish generation in time.")
                # Read the 4-byte event count to ack and re-arm.
                os.read(self._uio_fd, 4)
                os.write(self._uio_fd, (1).to_bytes(4, "little"))
                s = int(u32[sidx])
                if s & 0x4:
                    return self._unpack_status(s)
                if s & 0x8:
                    raise RuntimeError(f"core reported error; status=0x{s:08x}")
                # Spurious wake: line was held high from the previous call,
                # we just consumed the queued event; loop and re-block.

        # Fallback: busy-poll STATUS. Used when /dev/uio<fabric> isn't
        # available (e.g. older bitstream without IRQ wiring).
        end = time.monotonic() + timeout_s
        u32 = self._u32
        idx = REG_STATUS >> 2
        spin = 0
        while True:
            s = int(u32[idx])
            if s & 0x4:    # done
                return self._unpack_status(s)
            if s & 0x8:    # error
                raise RuntimeError(f"core reported error; status=0x{s:08x}")
            spin += 1
            if (spin & 0xFFF) == 0 and time.monotonic() > end:
                raise TimeoutError("microGPT did not finish generation in time.")

    @staticmethod
    def _unpack_status(s: int) -> dict:
        return {
            "ready":       bool(s & 0x1),
            "busy":        bool((s >> 1) & 0x1),
            "done":        bool((s >> 2) & 0x1),
            "error":       bool((s >> 3) & 0x1),
            "host_toggle": bool((s >> 4) & 0x1),
            "direct_mode": bool((s >> 5) & 0x1),
            "out_len":     (s >> 16) & 0xFF,
            "pos":         (s >> 24) & 0xFF,
        }

    def generate(
        self,
        max_tokens: int = 15,
        temperature: float = 1.0,
        seed: int = 1,
    ) -> tuple[str, dict]:
        """Run a fresh BOS-seeded generation and return (text, info).

        Args:
            max_tokens:  1..15. Hard upper bound enforced by the core.
            temperature: Q8.8 temperature applied before the categorical
                         sampler. Pass 0.5..2.0 for sensible behaviour.
            seed:        32-bit unsigned RNG seed.

        Returns:
            (decoded_string, info_dict). info_dict carries `tokens`, `cycles`,
            `tokens_per_sec`, and the final `status` snapshot.

        Note: the explicit clear-pulse that older versions issued on every
        call has been removed. The wrapper FSM accepts a `start_pulse` from
        ST_READY *or* ST_DONE and unconditionally re-initialises the result
        registers, so an extra clear is just two wasted AXI transactions.
        """
        if not 1 <= max_tokens <= 15:
            raise ValueError("max_tokens must be in [1, 15]")

        u32 = self._u32

        # Program config + seed (Q8.8 temperature, max_gen).
        cfg = ((_temperature_to_q8_8(temperature) & 0xFFFF) << 16) | \
              ((max_tokens & 0xFF) << 8)
        u32[REG_CONFIG >> 2] = np.uint32(cfg)
        u32[REG_SEED   >> 2] = np.uint32(seed & 0xFFFFFFFF)

        # Fire start pulse.
        u32[REG_CMD >> 2] = np.uint32(0x1)

        st = self._wait_done()
        out_len = st["out_len"]

        # Burst-read the token block + the perf counter as a single numpy
        # slice. Numpy reads each uint32 through the mmap'd /dev/mem region
        # in C, with no per-element Python interpreter overhead. This is the
        # single largest win once the polling loop is tight: ~10 fewer
        # Python round-trips per generation at max_tokens=15.
        if out_len:
            base = REG_OUT_BASE >> 2
            tokens = (np.asarray(u32[base : base + out_len], dtype=np.uint32) & 0xFF).tolist()
        else:
            tokens = []
        cycles = int(u32[REG_PERF_CYC >> 2])
        tps    = int(u32[REG_TPS      >> 2])

        text = "".join(
            TOKEN_ALPHABET[t] if 0 <= t < len(TOKEN_ALPHABET) else "?"
            for t in tokens
        )
        return text, {
            "tokens":         tokens,
            "cycles":         cycles,
            "tokens_per_sec": tps,
            "status":         st,
        }

    def step(
        self,
        token: int,
        pos: int,
        clear: bool = False,
        seed: Optional[int] = None,
    ) -> dict:
        """Single direct-mode step: feed (token, pos) and read back the result."""
        if not 0 <= token <= 255 or not 0 <= pos <= 15:
            raise ValueError("token must be 0..255 and pos must be 0..15")
        if seed is not None:
            self._write(REG_SEED, seed & 0xFFFFFFFF)
        cfg = ((token & 0xFF) << 16) | ((pos & 0xFF) << 8) \
              | (0x2 if clear else 0x0) | 0x1  # direct_mode=1
        self._write(REG_STEP_CFG, cfg)
        self._write(REG_STEP_TRIG, 0x1)

        st = self._wait_done()
        info = self._read(REG_LOGIT_INFO)
        return {
            "last_token":    info & 0xFF,
            "argmax_token":  (info >> 8) & 0xFF,
            "top_logit_q12": _sign_extend((info >> 16) & 0xFFFF, 16),
            "status":        st,
        }

    def logits(self) -> List[int]:
        """Read the 27 logits from the last completed step (signed Q12)."""
        return [
            _sign_extend(self._read(REG_LOGITS_BASE + 4 * i) & 0xFFFF, 16)
            for i in range(27)
        ]


def _sign_extend(value: int, bits: int) -> int:
    sign_bit = 1 << (bits - 1)
    return (value & (sign_bit - 1)) - (value & sign_bit)
