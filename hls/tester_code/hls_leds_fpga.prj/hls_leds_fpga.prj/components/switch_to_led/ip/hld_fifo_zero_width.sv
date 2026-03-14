//// (C) 1992-2018 Intel Corporation.                            
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


// this is a wrapper around hld_fifo using WIDTH=0 and without i_data and o_data ports (so that backend doesn't complain about unused ports)
// this is intended for occupancy tracking, beware that low latency version uses 1-hot encoding for occupancy tracking so avoid using this for large DPETH
// setting the STYLE parameter will affect write-to-read latency, and this affects e.g. how soon almost empty deasserts due to a write

`timescale 1ps/1ps
`default_nettype none

module hld_fifo_zero_width #(
    //basic fifo configuration
    parameter int DEPTH,                        // capacity of the fifo, at least 1
    
    //almost empty and almost full configuration
    parameter int ALMOST_EMPTY_CUTOFF = 0,      // o_almost_empty asserts if read_used_words <= ALMOST_EMPTY_CUTOFF
    parameter int ALMOST_FULL_CUTOFF = 0,       // o_almost_full/o_stall asserts if write_used_words >= (DEPTH-ALMOST_FULL_CUTOFF), applies to o_almost_full if USE_STALL_LATENCY_UPSTREAM = 0, otherwise applies to o_stall
    
    
    //TEMPORARY WOKAROUND FOR TO-UK SYNC LAG -- the backend is using hld_fifo with the old ALMOST_***_THRESH parameters, keep these around until the change to remove them has propagated to TO
    parameter int ALMOST_EMPTY_THRESH = 1,
    parameter int ALMOST_FULL_THRESH = 0,
    
    
    //initial occupancy
    parameter int INITIAL_OCCUPANCY = 0,        // number of words in the fifo (write side occupancy) when it comes out of reset, note it still takes WRITE_TO_READ_LATENCY clocks for this to become visible on the read side
    
    //reset configuration
    parameter bit ASYNC_RESET = 0,              // how do we use reset: 1 means registers are reset asynchronously, 0 means registers are reset synchronously
    parameter bit SYNCHRONIZE_RESET = 1,        // based on how reset gets to us, what do we need to do: 1 means synchronize reset before consumption (if reset arrives asynchronously), 0 means passthrough (managed externally)
    parameter bit RESET_EVERYTHING = 0,         // intended for partial reconfig debug, set to 1 to reset every register (normally async reset excludes data path and sync reset additionally excludes some control signals)
    parameter bit RESET_EXTERNALLY_HELD = 1,    // set to 1 if resetn will be held for at least FIVE clock cycles, otherwise we will internally pulse stretch reset before consumption
    
    //special configurations for higher fmax / lower area
    parameter int STALL_IN_EARLINESS = 0,       // how many clock cycles ahead i_stall is, enables internal manual retiming
    parameter int VALID_IN_EARLINESS = 0,       // how many clock cycles ahead i_valid is, enables internal manual retiming
    parameter int REGISTERED_DATA_OUT_COUNT = 0,// how many lower bits of o_data are registered (upper bits are unregistered)
    parameter bit NEVER_OVERFLOWS = 0,          // set to 1 to disable fifo's internal overflow protection
    parameter bit HOLD_DATA_OUT_WHEN_EMPTY = 0, // 0 means o_data can be x when fifo is empty, 1 means o_data will hold last value when fifo is empty (scfifo behavior, has fmax penalty)
    
    //interface selection
    parameter bit USE_STALL_LATENCY_UPSTREAM = 0,   // 0 means use legacy stall/valid, 1 means use new stall latency, applies to upstream interface: i_valid, i_data, o_stall, o_almost_full
    parameter bit USE_STALL_LATENCY_DOWNSTREAM = 0, // 0 means use legacy stall/valid, 1 means use new stall latency, applies to downstream interface: o_valid, o_data, i_stall, o_almost_empty, o_empty
    
    //fifo selection
    parameter string STYLE = "hs"               // "hs" = acl_high_speed_fifo, "ll" = acl_low_latency_fifo, "zl" = acl_zero_latency_fifo
)
(
    input  wire                 clock,          
    input  wire                 resetn,         // reset is ACTIVE LOW, see description above for different reset modes
    
                                                // Legacy stall/valid behavior                                                  | New stall latency behavior                                     | Reset value
    //upstream interface                        // -----------------------------------------------------------------------------+----------------------------------------------------------------+------------
    input  wire                 i_valid,        // upstream has data, fifo IS ALLOWED to consume it                             | upstream has data, fifo MUST consume it or data will be lost   | N/A
    output logic                o_stall,        // backpressure to upstream, fifo is full                                       | backpressure to upstream, fifo is almost full                  | 1
    output logic                o_almost_full,  // fifo is almost full, hint to upstream of potential future backpressure       | NOT USED, do not consume this output signal                    | 1
                                                //                                                                              |                                                                |
    //downstream interface                      // -----------------------------------------------------------------------------+----------------------------------------------------------------+------------
    output logic                o_valid,        // fifo has data, downstream IS ALLOWED to consume it                           | fifo has data, downstream MUST consume it or data will be lost | 0
    input  wire                 i_stall,        // backpressure from downstream STALL_IN_EARLINESS clocks ahead of time         | <-- same behavior                                              | N/A
    output logic                o_almost_empty, // fifo is almost empty, hint to downstream of potential future fifo emptiness  | <-- same behavior                                              | 1
    output logic                o_empty         // fifo is empty right now                                                      | <-- same behavior                                              | 1
);
    
    
    hld_fifo
    #(
        //basic fifo config
        .WIDTH                      (0),
        .DEPTH                      (DEPTH),
        
        //almost empty and almost full config
        .ALMOST_EMPTY_CUTOFF        (ALMOST_EMPTY_CUTOFF),
        .ALMOST_FULL_CUTOFF         (ALMOST_FULL_CUTOFF),
        
        
        
        //TEMPORARY WOKAROUND FOR TO-UK SYNC LAG -- the backend is using hld_fifo with the old ALMOST_***_THRESH parameters, keep these around until the change to remove them has propagated to TO
        .ALMOST_EMPTY_THRESH        (ALMOST_EMPTY_THRESH),
        .ALMOST_FULL_THRESH         (ALMOST_FULL_THRESH),
        
        //initial occupancy
        .INITIAL_OCCUPANCY          (INITIAL_OCCUPANCY),
        
        //reset config
        .ASYNC_RESET                (ASYNC_RESET),
        .SYNCHRONIZE_RESET          (SYNCHRONIZE_RESET),
        .RESET_EVERYTHING           (RESET_EVERYTHING),
        .RESET_EXTERNALLY_HELD      (RESET_EXTERNALLY_HELD),
        
        //special config
        .REGISTERED_DATA_OUT_COUNT  (REGISTERED_DATA_OUT_COUNT),
        .NEVER_OVERFLOWS            (NEVER_OVERFLOWS),
        .STALL_IN_EARLINESS         (STALL_IN_EARLINESS),
        .VALID_IN_EARLINESS         (VALID_IN_EARLINESS),
        .HOLD_DATA_OUT_WHEN_EMPTY   (HOLD_DATA_OUT_WHEN_EMPTY),
        
        //interface selection
        .USE_STALL_LATENCY_UPSTREAM (USE_STALL_LATENCY_UPSTREAM),
        .USE_STALL_LATENCY_DOWNSTREAM (USE_STALL_LATENCY_DOWNSTREAM),
        
        //fifo selection
        .STYLE                      (STYLE)
    )
    hld_fifo_inst
    (
        .clock                      (clock),
        .resetn                     (resetn),
        
        .i_valid                    (i_valid),
        .i_data                     (), //unused
        .o_stall                    (o_stall),
        .o_almost_full              (o_almost_full),
        
        .o_valid                    (o_valid),
        .o_data                     (), //unused
        .i_stall                    (i_stall),
        .o_almost_empty             (o_almost_empty),
        .o_empty                    (o_empty)
    );
    
endmodule


`default_nettype wire
