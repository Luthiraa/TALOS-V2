"""Cocotb tests for the microgpt_pynq_top AXI4-Lite slave wrapper.

Built specifically to catch the production write-path bug that wedged the
Zynq PS bus on the deployed bitstream: the slave kept AWREADY/WREADY high
in idle, the Zynq M_AXI_GP0 master saw both handshakes complete on
separate cycles, but the slave never latched the address and never
asserted BVALID.

Each test imposes a hard cocotb timeout, so a hang in the DUT becomes a
clean test failure rather than an infinite simulation.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles
from cocotbext.axi import AxiLiteBus, AxiLiteMaster

# 50 MHz, matching FCLK_CLK0 on the deployed board.
CLK_PERIOD_NS = 20
RESET_CYCLES = 32
SETTLE_CYCLES = 8

# Register map -- byte offsets, mirrors hw/src/top/microgpt_pynq_top.sv.
A_MAGIC      = 0x000
A_VERSION    = 0x004
A_CMD        = 0x008
A_STATUS     = 0x00C
A_CONFIG     = 0x010
A_SEED       = 0x014
A_LOGIT_INFO = 0x018
A_BOS        = 0x01C
A_STEP_CFG   = 0x020
A_STEP_TRIG  = 0x024

# status register field positions
ST_READY_BIT  = 0
ST_BUSY_BIT   = 1
ST_DONE_BIT   = 2
ST_ERROR_BIT  = 3
ST_TOGGLE_BIT = 4


# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
async def _start_clock(dut):
    cocotb.start_soon(Clock(dut.s_axi_aclk, CLK_PERIOD_NS, units="ns").start())


async def _reset(dut):
    dut.s_axi_aresetn.value = 0
    await ClockCycles(dut.s_axi_aclk, RESET_CYCLES)
    dut.s_axi_aresetn.value = 1
    await ClockCycles(dut.s_axi_aclk, SETTLE_CYCLES)


def _make_master(dut):
    return AxiLiteMaster(
        AxiLiteBus.from_prefix(dut, "s_axi"),
        dut.s_axi_aclk,
        dut.s_axi_aresetn,
        reset_active_level=False,
    )


async def _read32(master, addr):
    resp = await master.read(addr, 4)
    return int.from_bytes(resp.data, "little")


async def _write32(master, addr, value):
    await master.write(addr, int(value).to_bytes(4, "little"))


# -----------------------------------------------------------------------------
# Tests
# -----------------------------------------------------------------------------
@cocotb.test(timeout_time=200, timeout_unit="us")
async def test_01_read_magic_version_bos(dut):
    """Constants come back as documented in the register map."""
    await _start_clock(dut)
    master = _make_master(dut)
    await _reset(dut)

    magic = await _read32(master, A_MAGIC)
    assert magic == 0x4D475254, f"magic mismatch: {magic:#010x}"

    version = await _read32(master, A_VERSION)
    assert version == 0x00020001, f"version mismatch: {version:#010x}"

    bos = await _read32(master, A_BOS)
    assert bos == 0x0000001A, f"bos mismatch: {bos:#010x}"


@cocotb.test(timeout_time=200, timeout_unit="us")
async def test_02_status_register_initial(dut):
    """After reset: ready=1, busy=0, done=0, error=0."""
    await _start_clock(dut)
    master = _make_master(dut)
    await _reset(dut)

    s = await _read32(master, A_STATUS)
    assert (s >> ST_READY_BIT) & 1 == 1, f"ready bit not set: {s:#010x}"
    assert (s >> ST_BUSY_BIT)  & 1 == 0, f"busy unexpectedly set: {s:#010x}"
    assert (s >> ST_DONE_BIT)  & 1 == 0, f"done unexpectedly set: {s:#010x}"
    assert (s >> ST_ERROR_BIT) & 1 == 0, f"error unexpectedly set: {s:#010x}"


@cocotb.test(timeout_time=50, timeout_unit="us")
async def test_03_write_completes_does_not_hang(dut):
    """THE production-bug regression test.

    A single AXI4-Lite write must complete its B-channel handshake within
    a bounded number of cycles. If the slave wedges (the bug we fixed),
    the underlying cocotbext-axi `master.write` coroutine awaits BVALID
    forever and the cocotb timeout above kills the test loudly.
    """
    await _start_clock(dut)
    master = _make_master(dut)
    await _reset(dut)

    await _write32(master, A_CONFIG, 0x01000100)


@cocotb.test(timeout_time=200, timeout_unit="us")
async def test_04_write_then_read_back(dut):
    """Config write round-trips after a CMD start_pulse commits the stage.

    The wrapper deliberately uses a stage-then-commit pattern: A_CONFIG
    writes land in `host_temperature_reg`/`host_max_gen_reg` (shadow),
    and the A_CONFIG readback returns the *committed* `temperature_reg`/
    `max_gen_reg` -- which only update when start_pulse fires (bit 0 of
    A_CMD). So a write -> immediate read returns the prior committed
    values (after reset, that's temp=0x0080, max_gen=0x0F). To verify
    the round-trip we have to commit the stage by writing A_CMD=1 first.
    """
    await _start_clock(dut)
    master = _make_master(dut)
    await _reset(dut)

    payload = 0x01000100  # temp = 0x0100, max_gen = 0x01, [7:0] reserved
    await _write32(master, A_CONFIG, payload)
    # Commit: start_pulse copies host_* shadow into the latched register set.
    await _write32(master, A_CMD, 0x00000001)
    # The latching happens on the cycle start_pulse is observed by the FSM;
    # a few cycles of margin make this read race-free.
    await ClockCycles(dut.s_axi_aclk, 4)

    readback = await _read32(master, A_CONFIG)

    # Bottom byte is reserved/zero in the spec; mask before comparing.
    assert (readback & 0xFFFFFF00) == (payload & 0xFFFFFF00), (
        f"config readback {readback:#010x} != written {payload:#010x}"
    )


@cocotb.test(timeout_time=400, timeout_unit="us")
async def test_05_host_toggle_flips_on_each_transaction(dut):
    """status[4] (host_toggle) must flip on every successful AXI transaction
    (read OR write). Drive a deliberate mix of reads and writes through the
    AXI bus, read STATUS via the bus to sample bit[4], and assert that the
    sampled toggle equals the running parity of all completed transactions.

    Why the predicted parity is the right oracle: each AXI transaction flips
    host_toggle exactly once. A STATUS read SAMPLES the toggle BEFORE the
    flip caused by that read itself, so the sampled value at the k-th
    completed STATUS read equals the parity of the k transactions that
    completed *before* it (initial toggle = 0).

    The previous test only did back-to-back STATUS reads (parity always
    alternates), which would silently miss a regression where WRITE
    transactions stop flipping the toggle. The hardware-repro pattern
    (write+read interleaved) was misleading because two flips per iter alias
    to a constant 0 either way -- this version uses a non-uniform mix of
    reads and writes so any drop in the write path's flip is loud.
    """
    await _start_clock(dut)
    master = _make_master(dut)
    await _reset(dut)

    txn_count = 0  # AXI transactions completed so far

    async def status_read_assert(label):
        nonlocal txn_count
        s = await _read32(master, A_STATUS)
        sampled = (s >> ST_TOGGLE_BIT) & 1
        expected = txn_count & 1
        assert sampled == expected, (
            f"[{label}] host_toggle sampled={sampled} expected={expected} "
            f"(prior txn_count={txn_count}, status={s:#010x}). "
            f"A WRITE that fails to flip the toggle is the most likely cause."
        )
        txn_count += 1

    async def writeable(addr, data):
        nonlocal txn_count
        await _write32(master, addr, data)
        txn_count += 1

    # Phase A: pure-read parity (regression of the original test_05 spirit).
    for i in range(5):
        await status_read_assert(f"A.{i} pure-read")

    # Phase B: interleaved reads and writes -- catches the case where writes
    # would have stopped flipping the toggle (the misdiagnosed prod bug).
    await writeable(A_CONFIG, 0xABCD0000)
    await status_read_assert("B.0 read after CONFIG write")
    await writeable(A_SEED, 0xDEADBEEF)
    await status_read_assert("B.1 read after SEED write")
    await writeable(A_STEP_CFG, 0x12340000)
    await writeable(A_CONFIG, 0x55667700)
    await status_read_assert("B.2 read after two writes")
    await status_read_assert("B.3 read-only follow-up")
    await writeable(A_SEED, 0xCAFEBABE)
    await status_read_assert("B.4 read after another write")


@cocotb.test(timeout_time=50, timeout_unit="us")
async def test_06_unmapped_address_does_not_hang(dut):
    """Unmapped offsets within the 4 KB window must still complete.

    Either OKAY (silent ignore) or SLVERR is acceptable per AXI -- what
    is NEVER acceptable is dropping the response and wedging the master.
    cocotbext-axi raises on a non-OKAY response; we accept either.
    """
    await _start_clock(dut)
    master = _make_master(dut)
    await _reset(dut)

    try:
        await _write32(master, 0xFFC, 0xDEADBEEF)
    except Exception:
        # SLVERR surfaces as an exception; that's fine -- the handshake
        # still completed (otherwise we'd time out, not raise).
        pass

    try:
        _ = await _read32(master, 0xFF8)
    except Exception:
        pass


@cocotb.test(timeout_time=2, timeout_unit="ms")
async def test_07_start_pulse_via_cmd(dut):
    """Writing bit 0 of CMD (0x008) must move the FSM out of ST_READY.

    The unmodified TALOS-V2 core may take many cycles to actually finish
    a generation; this test only verifies the pulse fires and the wrapper
    leaves the READY state. A larger window is OK because the cocotb
    timeout still bounds the run.
    """
    await _start_clock(dut)
    master = _make_master(dut)
    await _reset(dut)

    s0 = await _read32(master, A_STATUS)
    assert (s0 >> ST_READY_BIT) & 1 == 1, (
        f"DUT did not start in READY: {s0:#010x}"
    )

    await _write32(master, A_CMD, 0x00000001)

    saw_departure = False
    for _ in range(256):
        s = await _read32(master, A_STATUS)
        ready = (s >> ST_READY_BIT) & 1
        busy  = (s >> ST_BUSY_BIT)  & 1
        done  = (s >> ST_DONE_BIT)  & 1
        if (not ready) or busy or done:
            saw_departure = True
            break

    assert saw_departure, "FSM never transitioned out of ST_READY after CMD start_pulse"


@cocotb.test(timeout_time=2, timeout_unit="ms")
async def test_09_done_irq_pulses_and_clears_on_start(dut):
    """done_irq must:
       * be 0 right after reset,
       * stay 0 while the FSM is busy,
       * go to 1 once a generation completes,
       * go back to 0 when the next start_pulse fires.
    """
    await _start_clock(dut)
    master = _make_master(dut)
    await _reset(dut)

    assert int(dut.done_irq.value) == 0, "done_irq should be 0 right after reset"

    # Force a fast termination: max_gen=0 makes the FSM go straight to
    # ST_DONE with error_reg=1, which triggers irq_pending_reg <= 1.
    await _write32(master, A_CONFIG, 0x00800000)
    await _write32(master, A_CMD,    0x00000001)

    # Within a small window the irq line must come up.
    armed = False
    for _ in range(64):
        await ClockCycles(dut.s_axi_aclk, 4)
        if int(dut.done_irq.value):
            armed = True
            break
    assert armed, "done_irq never asserted after generation completed"

    # Read STATUS through the bus to confirm done=1 (this also exercises that
    # the irq line stays high across reads).
    s = await _read32(master, A_STATUS)
    assert (s >> 2) & 1, f"done bit not set in STATUS: {s:#010x}"
    assert int(dut.done_irq.value) == 1, "irq line dropped before next start_pulse fired"

    # Next start should clear the irq immediately (in the cycle the FSM sees
    # start_pulse). Allow one extra cycle for the synchronous reset.
    await _write32(master, A_CMD, 0x00000001)
    await ClockCycles(dut.s_axi_aclk, 8)
    assert int(dut.done_irq.value) == 0, "done_irq did not clear after next start_pulse"


@cocotb.test(timeout_time=80, timeout_unit="ms")
async def test_10_led_heartbeat_toggles(dut):
    """led_heartbeat must blink autonomously regardless of AXI activity.

    The Makefile overrides HEARTBEAT_BITS to a small value for sim so the
    counter MSB toggles every few microseconds; we sample the led_heartbeat
    output port over up to 70 ms simulated time and assert it took both
    values at least once. led_heartbeat is a primary output port, not an
    internal reg, so this stays consistent with the "no peeking at internal
    regs" rule the AXI tests follow.
    """
    await _start_clock(dut)
    await _reset(dut)

    seen = {int(dut.led_heartbeat.value)}
    # Poll in 1 ms chunks (50 000 cycles @ 50 MHz) for up to ~70 ms.
    for _ in range(70):
        if len(seen) >= 2:
            break
        await ClockCycles(dut.s_axi_aclk, 50_000)
        seen.add(int(dut.led_heartbeat.value))

    assert len(seen) >= 2, (
        f"led_heartbeat did not toggle within 70 ms simulated time "
        f"(only saw value(s) {seen}). Either the heartbeat counter is "
        f"stuck (held in reset / optimised away) or HEARTBEAT_BITS was "
        f"not overridden by the Makefile -- production HEARTBEAT_BITS=26 "
        f"would need ~670 ms of sim time to flip."
    )
