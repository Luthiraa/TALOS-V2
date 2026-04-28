# SPDX-FileCopyrightText: © 2026 Luthiraa
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge


@cocotb.test()
async def test_sampler_probe(dut):
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0x80
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    dut.ui_in.value = 0x95
    await RisingEdge(dut.clk)
    dut.ui_in.value = 0x15

    done_seen = False
    for _ in range(200):
        await RisingEdge(dut.clk)
        if int(dut.uo_out.value) & 0x40:
            done_seen = True
            break

    assert done_seen, "sampler probe never completed"
    token = int(dut.uo_out.value) & 0x1F
    assert 0 <= token < 27, f"sampled token out of range: {token}"
