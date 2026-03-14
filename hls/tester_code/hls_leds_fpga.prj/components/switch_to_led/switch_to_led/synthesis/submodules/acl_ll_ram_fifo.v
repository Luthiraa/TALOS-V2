// (C) 1992-2018 Intel Corporation.                            
// Intel, the Intel logo, Intel, MegaCore, NIOS II, Quartus and TalkBack words    
// and logos are trademarks of Intel Corporation or its subsidiaries in the U.S.  
// and/or other countries. Other marks and brands may be claimed as the property  
// of others. See Trademarks on intel.com for full list of Intel trademarks or    
// the Trademarks & Brands Names Database (if Intel) or See www.Intel.com/legal (if Altera) 
// Your use of Intel Corporation's design tools, logic functions and other        
// software and tools, and its AMPP partner logic functions, and any output       
// files any of the foregoing (including device programming or simulation         
// files), and any associated documentation or information are expressly subject  
// to the terms and conditions of the Altera Program License Subscription         
// Agreement, Intel MegaCore Function License Agreement, or other applicable      
// license agreement, including, without limitation, that your use is for the     
// sole purpose of programming logic devices manufactured by Intel and sold by    
// Intel or its authorized distributors.  Please refer to the applicable          
// agreement for further details.                                                 


//===----------------------------------------------------------------------===//
//
// Low-latency RAM-based FIFO. Uses a low-latency register-based FIFO to
// mask the latency of the RAM-based FIFO.
//
// This FIFO uses additional area beyond the FIFO capacity and
// counters in order to compensate for the latency in a normal RAM FIFO.
//
//===----------------------------------------------------------------------===//
module acl_ll_ram_fifo 
#(
    parameter integer DATA_WIDTH = 32,  // >0
    parameter integer DEPTH = 32        // >3
)
(
    input logic clock,
    input logic resetn,
    input logic [DATA_WIDTH-1:0] data_in,
    output logic [DATA_WIDTH-1:0] data_out,
    input logic valid_in,
    output logic valid_out,
    input logic stall_in,
    output logic stall_out,
    output logic empty,
    output logic full
);
    localparam SEL_RAM = 0;
    localparam SEL_LL = 1;

    // Three FIFOs:
    //  1. data - RAM FIFO (normal latency)
    //  2. data - LL REG FIFO
    //  3. selector - LL REG FIFO
    //
    // Selector determines which of the two data FIFOs to select the current
    // output from.
    //
    // TODO Implementation note:
    // It's probably possible to use a more compact storage mechanism than
    // a FIFO for the selector because the sequence of selector values
    // should be highly compressible (e.g. long sequences of SEL_RAM). The
    // selector FIFO can probably be replaced with a small number of counters.
    // A future enhancement.
    logic [DATA_WIDTH-1:0] ram_data_in, ram_data_out;
    logic ram_valid_in, ram_valid_out, ram_stall_in, ram_stall_out;
    logic [DATA_WIDTH-1:0] ll_data_in, ll_data_out;
    logic ll_valid_in, ll_valid_out, ll_stall_in, ll_stall_out;
    logic sel_data_in, sel_data_out;
    logic sel_valid_in, sel_valid_out, sel_stall_in, sel_stall_out;

    // Top-level outputs.
    assign data_out = sel_data_out == SEL_LL ? ll_data_out : ram_data_out;
    assign valid_out = sel_valid_out;   // the required ll_valid_out/ram_valid_out must also be asserted
    assign stall_out = sel_stall_out;

    // RAM FIFO.
    acl_data_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH - 3),
        .IMPL("ram")
    )
    ram_fifo (
        .clock(clock),
        .resetn(resetn),
        .data_in(ram_data_in),
        .data_out(ram_data_out),
        .valid_in(ram_valid_in),
        .valid_out(ram_valid_out),
        .stall_in(ram_stall_in),
        .stall_out(ram_stall_out)
    );

    assign ram_data_in = data_in;
    assign ram_valid_in = valid_in & ll_stall_out;  // only write to RAM FIFO if LL FIFO is stalled
    assign ram_stall_in = (sel_data_out != SEL_RAM) | stall_in;

    // Low-latency FIFO.
    acl_data_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(3),
        .IMPL("ll_reg")
    )
    ll_fifo (
        .clock(clock),
        .resetn(resetn),
        .data_in(ll_data_in),
        .data_out(ll_data_out),
        .valid_in(ll_valid_in),
        .valid_out(ll_valid_out),
        .stall_in(ll_stall_in),
        .stall_out(ll_stall_out)
    );

    assign ll_data_in = data_in;
    assign ll_valid_in = valid_in & ~ll_stall_out;  // write to LL FIFO if it is not stalled
    assign ll_stall_in = (sel_data_out != SEL_LL) | stall_in;

    // Selector FIFO.
    acl_data_fifo #(
        .DATA_WIDTH(1),
        .DEPTH(DEPTH),
        .IMPL("ll_reg")
    )
    sel_fifo (
        .clock(clock),
        .resetn(resetn),
        .data_in(sel_data_in),
        .data_out(sel_data_out),
        .valid_in(sel_valid_in),
        .valid_out(sel_valid_out),
        .stall_in(sel_stall_in),
        .stall_out(sel_stall_out),
        .empty(empty),
        .full(full)
    );

    assign sel_data_in = ll_valid_in ? SEL_LL : SEL_RAM;
    assign sel_valid_in = valid_in;
    assign sel_stall_in = stall_in;
endmodule

