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


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                                                                                                                  //
//  HLD (High Level Design) FIFO                                                                                                                                                    //
//  Designed and optimized by: Jason Thong                                                                                                                                          //
//                                                                                                                                                                                  //
//  DESCRIPTION                                                                                                                                                                     //
//  ===========                                                                                                                                                                     //
//  Wrapper utility that selects which S10-optimized FIFO to use based on STYLE parameter. One can select whether to use the legacy stall/valid interface or the new stall latency  //
//  interface, separate selection for upstream and downstream interfaces.                                                                                                           //
//                                                                                                                                                                                  //
//  REQUIRED FILES                                                                                                                                                                  //
//  ==============                                                                                                                                                                  //
//  - hld_fifo.sv                                                                                                                                                                   //
//  - acl_reset_handler.sv                                                                                                                                                          //
//  - acl_fanout_pipeline.sv                                                                                                                                                        //
//  - acl_std_synchronizer_nocut.v                                                                                                                                                  //
//  - acl_zero_latency_fifo.sv                                                                                                                                                      //
//  - acl_low_latency_fifo.sv                                                                                                                                                       //
//  - acl_high_speed_fifo.sv                                                                                                                                                        //
//  - acl_lfsr.sv                                                                                                                                                                   //
//  - acl_tessellated_incr_decr_threshold.sv                                                                                                                                        //
//  - acl_tessellated_incr_lookahead.sv                                                                                                                                             //
//                                                                                                                                                                                  //
//  WRITE TO READ LATENCY                                                                                                                                                           //
//  =====================                                                                                                                                                           //
//  FIFOs are fundamentally designed differently if one wants storage in memory versus in registers. Registers provide simple way to achieve low write to read latency. Adding      //
//  bypass logic to the prefetch of a memory-based FIFO hurts area and fmax. Conceptually, a FIFO will track two types of occupancy:                                                //
//  1. write_used_words:                                                                                                                                                            //
//      - tracks how many words have been written into the FIFO                                                                                                                     //
//      - increments one clock after write (on the next clock edge when write is asserted), decrements one clock after read ack                                                     //
//      - backpressure to upstream (o_stall and o_almost_full) are based on this value                                                                                              //
//  2. read_used_words:                                                                                                                                                             //
//      - tracks how many words are readable from the FIFO                                                                                                                          //
//      - increments WRITE_TO_READ_LATENCY clocks after write, decrements one clock after read ack                                                                                  //
//      - data availability to downstream (valid_out and almost_empty) are based on this value                                                                                      //
//  If WRITE_TO_READ_LATENCY >= 2 then write_used_words increments before read_used_words. The interpretation is that something written into the FIFO takes some time before that   //
//  same item is readable. If WRITE_TO_READ_LATENCY == 1 then write_used_words is the same as read_used_words. If WRITE_TO_READ_LATENCY == 0 then read_used_words increments        //
//  *BEFORE* write_used_words. It may sound like something is readable before it has been written to the FIFO, but the correct interpretation is that data can bypass the storage   //
//  associated with a FIFO. This happens when an empty FIFO is written to and read from on the same clock.                                                                          //
//                                                                                                                                                                                  //
//  SUPPORTED FIFO IMPLEMENTATIONS                                                                                                                                                  //
//  ==============================                                                                                                                                                  //
//  Set the STYLE parameter to choose which underlying FIFO to use:                                                                                                                 //
//  STYLE   | Implementation        | WRITE_TO_READ_LATENCY | Storage                                                                                                               //
//  --------+-----------------------+-----------------------+----------------------                                                                                                 //
//  "hs"    | acl_high_speed_fifo   | 5                     | Memory (M20K or MLAB)                                                                                                 //
//  "ll"    | acl_low_latency_fifo  | 1                     | Registers                                                                                                             //
//  "zl"    | acl_zero_latency_fifo | 0                     | Registers                                                                                                             //
//                                                                                                                                                                                  //
//  LATENCY SPECIFICATION OF ALL FIFO IMPLEMENTATIONS                                                                                                                               //
//  =================================================                                                                                                                               //
//  Category        | Latency               | Example signals    | In plain English                                                                                                 //
//  ----------------+-----------------------+--------------------+----------------------------------------------------------------                                                  //
//  write -> write  | 1                     | i_valid to o_stall | Number of clocks it takes for write request to affect fifo full status                                           //
//  write -> read   | WRITE_TO_READ_LATENCY | i_valid to o_valid | Number of clocks it takes for write request to affect fifo empty status                                          //
//  read -> write   | 1                     | i_stall to o_stall | Number of clocks it takes for read request to affect fifo full status                                            //
//  read -> read    | 1                     | i_stall to o_valid | Number of clocks it takes for read request to affect fifo empty status                                           //
//                                                                                                                                                                                  //
//  ALMOST FULL AND ALMOST EMPTY                                                                                                                                                    //
//  ============================                                                                                                                                                    //
//  The ALMOST_***_CUTOFF parameters refer to how much dead space would be in the fifo if one were to use almost_full as same clock cycle backpressure (dead space in not being     //
//  able to completely fill the fifo), or if one were to almost_empty as same clock cycle underflow prevention (dead space in not being able to empty the fifo). See chart below    //
//  for interpretation of values:                                                                                                                                                   //
//                                                                                                                                                                                  //
//  Scfifo parameter                    | Our parameter             | Interpretation                                                                                                //
//  ------------------------------------+---------------------------+---------------------------------------------------------------                                                //
//  almost_empty_value = 1              | ALMOST_EMPTY_CUTOFF = 0   | almost_empty behaves the same way as empty                                                                    //
//  almost_empty_value = 2              | ALMOST_EMPTY_CUTOFF = 1   | almost_empty asserts when read_used_words is 1 or less                                                        //
//  ------------------------------------+---------------------------+---------------------------------------------------------------                                                //
//  almost_full_value = lpm_numwords    | ALMOST_FULL_CUTOFF = 0    | almost_full behaves the same way as full                                                                      //
//  almost_full_value = lpm_numwords-1  | ALMOST_FULL_CUTOFF = 1    | almost_full asserts when write_used_words is DEPTH-1 or higher                                                //
//                                                                                                                                                                                  //
//  INITIAL OCCUPANCY                                                                                                                                                               //
//  =================                                                                                                                                                               //
//  The parameter INITIAL_OCCUPANCY describes the number of words of garbage data in the fifo as it exits from reset. Typically this is 0, e.g. we have to write into the fifo      //
//  before anything is readable. If INITIAL_OCCUPANCY > 0, then valid_out is 0 during reset, and when it eventually asserts it is then safe for downstream to transact reads from   //
//  the fifo. Exit from reset should be handled separately for upstream and downstream. In particular, the assertion of valid_out (to downstream) and the deassertion of stall_out  //
//  (to upstream) may not happen on the same clock cycle. If INITIAL_OCCUPANCY == DEPTH, one cannot use stall_out to observe reset exit, only when at least one item has been read  //
//  from the fifo will stall_out then deasert.                                                                                                                                      //
//                                                                                                                                                                                  //
//  OPTIMIZATION STRATEGIES                                                                                                                                                         //
//  =======================                                                                                                                                                         //
//  To improve fmax and reduce area, one should provide control signals earlier than the corresponding data. This is controlled by the following parameters:                        //
//  STALL_IN_EARLINESS:                                                                                                                                                             //
//      - how many clock cycles ahead of time does downstream indicate it cannot accept data                                                                                        //
//      - if downstream has capacity, then almost full from downstream can drive the stall port of the FIFO                                                                         //
//  VALID_IN_EARLINESS:                                                                                                                                                             //
//      - how many clock cycles ahead of time does upstream indicate it can provide data                                                                                            //
//      - decide on whether to accept data into the FIFO ahead of time, then the data arrives later e.g. could hide the latency of upstream reading that data out of a memory       //
//                                                                                                                                                                                  //
//  RESET CONFIGURATION                                                                                                                                                             //
//  ===================                                                                                                                                                             //
//  One may consume the reset asynchronously (ASYNC_RESET=1) or synchronously (ASYNC_RESET=0), but not both at the same time. Reset *CONSUMPTION* is separate from *DISTRIBUTION*.  //
//  For example, we could consume reset synchronously but distribute it asynchronously e.g. using a global clock line. Local synchronizers are used before reset is consumed if     //
//  SYNCHRONIZE_RESET=1, otherwise we assume one has externally managed the synchronous release of reset. RESET_EVERYTHING does as the name implies and is intended for partial     //
//  reconfiguration debug. Finally, typically in a pipeline of valids only the first and last are reset, so reset must be held to flush the pipeline. A reset pulse stretcher is    //
//  used, unless RESET_EXTERNALLY_HELD=1 in which case we assume reset will be held for sufficiently long (5 clocks for this module).                                               //
//                                                                                                                                                                                  //
//  RECOMMENDED RESET SETTINGS                                                                                                                                                      //
//  ==========================                                                                                                                                                      //
//  General usage is intended for when one is unsure about the reset. The HLD platform has specific reset properties so that we can e.g. remove the reset pulse stretcher.          //
//  Parameter             | General usage A10 | General usage S10 |   HLD A10   |   HLD S10                                                                                         //
//  ----------------------+-------------------+-------------------+-------------+-------------                                                                                      //
//  ASYNC_RESET           |        1          |         0         |     1       |      0                                                                                            //
//  SYNCHRONIZE_RESET     |        1          |         1         |     0       |      1                                                                                            //
//  RESET_EVERYTHING      |        0          |         0         |     0       |      0                                                                                            //
//  RESET_EXTERNALLY_HELD |        0          |         0         |     1       |      1                                                                                            //
//                                                                                                                                                                                  //
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

`timescale 1ps/1ps
`default_nettype none

module hld_fifo #(
    //basic fifo configuration
    parameter int WIDTH,                        // width of data path, at least 0
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
    input  wire     [WIDTH-1:0] i_data,         // data from upstream, synced with i_valid delayed by VALID_IN_EARLINESS clocks | <-- same behavior                                              | N/A
    output logic                o_stall,        // backpressure to upstream, fifo is full                                       | backpressure to upstream, fifo is almost full                  | 1
    output logic                o_almost_full,  // fifo is almost full, hint to upstream of potential future backpressure       | NOT USED, do not consume this output signal                    | 1
                                                //                                                                              |                                                                |
    //downstream interface                      // -----------------------------------------------------------------------------+----------------------------------------------------------------+------------
    output logic                o_valid,        // fifo has data, downstream IS ALLOWED to consume it                           | fifo has data, downstream MUST consume it or data will be lost | 0
    output logic    [WIDTH-1:0] o_data,         // data to downstream, synced with o_valid                                      | <-- same behavior                                              | x
    input  wire                 i_stall,        // backpressure from downstream STALL_IN_EARLINESS clocks ahead of time         | <-- same behavior                                              | N/A
    output logic                o_almost_empty, // fifo is almost empty, hint to downstream of potential future fifo emptiness  | <-- same behavior                                              | 1
    output logic                o_empty         // fifo is empty right now                                                      | <-- same behavior                                              | 1
);
    
    
    //TEMPORARY WOKAROUND FOR TO-UK SYNC LAG -- the backend is using hld_fifo with the old ALMOST_***_THRESH parameters, keep these around until the change to remove them has propagated to TO
    //if one does not override the default values, then almost_empty=empty and almost_full=0, so you really do have to set them in order for them to be useful
    localparam int ALMOST_EMPTY_CUTOFF_TEMP = (ALMOST_EMPTY_THRESH == 1) ? ALMOST_EMPTY_CUTOFF : (ALMOST_EMPTY_THRESH-1);
    localparam int ALMOST_FULL_CUTOFF_TEMP = (ALMOST_FULL_THRESH == 0) ? ALMOST_FULL_CUTOFF : (DEPTH-ALMOST_FULL_THRESH);
    
    
    
    //the underlying fifos are implemented with legacy stall/valid semantics, may need to convert to/from stall latency
    logic fifo_is_full, fifo_is_almost_full;
    logic fifo_is_not_empty, fifo_forced_read;
    
    generate
    if (USE_STALL_LATENCY_UPSTREAM) begin
        assign o_stall = fifo_is_almost_full;
        assign o_almost_full = 'x;
    end
    else begin
        assign o_stall = fifo_is_full;
        assign o_almost_full = fifo_is_almost_full;
    end
    if (USE_STALL_LATENCY_DOWNSTREAM) begin
        assign o_valid = fifo_forced_read;
        assign o_empty = ~fifo_is_not_empty;
    end
    else begin
        assign o_valid = fifo_is_not_empty;
        assign o_empty = ~fifo_is_not_empty;
    end
    endgenerate
    
    
    //STALL_IN_EARLINESS and VALID_IN_EARLINESS are not yet implemented on some underlying fifos, so do the retiming adjustment here
    //if we need a shift register, choose the signal polarity such that the registers being 0 apply the same backpressure as during reset
    //this means i_valid keeps its original polarity but i_stall will be inverted (stall=1 during reset, but shift registers reset to 0)
    
    //reset the extra pipeline stages to absorb excess STALL_IN_EARLINESS and VALID_IN_EARLINESS only if RESET_EVERYTHING is set
    logic aclrn, sclrn;
    generate
    if (RESET_EVERYTHING) begin
        acl_reset_handler
        #(
            .ASYNC_RESET            (ASYNC_RESET),
            .PIPE_DEPTH             (1),
            .NUM_COPIES             (1)
        )
        acl_reset_handler_inst
        (
            .clk                    (clock),
            .i_resetn               (resetn),
            .o_aclrn                (aclrn),
            .o_resetn_synchronized  (),
            .o_sclrn                (sclrn)
        );    
    end
    else begin
        assign aclrn = 1'b1;
        assign sclrn = 1'b1;
    end
    endgenerate
    
    
    
    generate
    if (STYLE == "zl") begin : gen_zero_latency_fifo
        localparam VALID_AND_STALL_IN_EARLINESS = (VALID_IN_EARLINESS >= 1 && STALL_IN_EARLINESS >= 1) ? 1 : 0;
        localparam UNUSED_VALID_IN_EARLINESS = (VALID_IN_EARLINESS > VALID_AND_STALL_IN_EARLINESS) ? (VALID_IN_EARLINESS-VALID_AND_STALL_IN_EARLINESS) : 0;
        localparam UNUSED_STALL_IN_EARLINESS = (STALL_IN_EARLINESS > VALID_AND_STALL_IN_EARLINESS) ? (STALL_IN_EARLINESS-VALID_AND_STALL_IN_EARLINESS) : 0;
        
        logic fifo_not_stall_in, fifo_valid_in;
        earliness_delay #( .PIPE(UNUSED_STALL_IN_EARLINESS) ) stall_in_inst ( .clock(clock), .aclrn(aclrn), .sclrn(sclrn), .i(~i_stall), .o(fifo_not_stall_in) );
        earliness_delay #( .PIPE(UNUSED_VALID_IN_EARLINESS) ) valid_in_inst ( .clock(clock), .aclrn(aclrn), .sclrn(sclrn), .i(i_valid), .o(fifo_valid_in) );
        
        acl_zero_latency_fifo
        #(
            .WIDTH                          (WIDTH),
            .DEPTH                          (DEPTH),
            .ALMOST_EMPTY_CUTOFF            (ALMOST_EMPTY_CUTOFF_TEMP), //FIXME: TEMPORARY WORKAROUND
            .ALMOST_FULL_CUTOFF             (ALMOST_FULL_CUTOFF_TEMP),  //FIXME: TEMPORARY WORKAROUND
            .INITIAL_OCCUPANCY              (INITIAL_OCCUPANCY),
            .ASYNC_RESET                    (ASYNC_RESET),
            .SYNCHRONIZE_RESET              (SYNCHRONIZE_RESET),
            .RESET_EVERYTHING               (RESET_EVERYTHING),
            //RESET_EXTERNALLY_HELD parameeter does not exist since there are no pipelines to flush with reset
            .REGISTERED_DATA_OUT_COUNT      (REGISTERED_DATA_OUT_COUNT),
            .HOLD_DATA_OUT_WHEN_EMPTY       (HOLD_DATA_OUT_WHEN_EMPTY),
            .VALID_AND_STALL_IN_EARLINESS   (VALID_AND_STALL_IN_EARLINESS)
            //todo: NEVER_OVERFLOWS
        )
        acl_zero_latency_fifo_inst
        (
            .clock                          (clock),
            .resetn                         (resetn),
            .data_in                        (i_data),
            .data_out                       (o_data),
            .valid_in                       (fifo_valid_in),
            .valid_out                      (fifo_is_not_empty),
            .stall_in                       (~fifo_not_stall_in),
            .stall_out                      (fifo_is_full),
            .almost_empty                   (o_almost_empty),
            .almost_full                    (fifo_is_almost_full)
        );
        
        logic not_stall_in_delayed;
        earliness_delay #( .PIPE(VALID_AND_STALL_IN_EARLINESS) ) stall_in_delayed_inst ( .clock(clock), .aclrn(aclrn), .sclrn(sclrn), .i(fifo_not_stall_in), .o(not_stall_in_delayed) );
        assign fifo_forced_read = fifo_is_not_empty & not_stall_in_delayed;     //TODO to come from fifo itself -- will be registered if STALL_IN_EARLINESS >= 1
    end
    if (STYLE == "ll") begin : gen_low_latency_fifo
        localparam VALID_AND_STALL_IN_EARLINESS = (VALID_IN_EARLINESS >= 1 && STALL_IN_EARLINESS >= 1) ? 1 : 0;
        localparam UNUSED_VALID_IN_EARLINESS = (VALID_IN_EARLINESS > VALID_AND_STALL_IN_EARLINESS) ? (VALID_IN_EARLINESS-VALID_AND_STALL_IN_EARLINESS) : 0;
        localparam UNUSED_STALL_IN_EARLINESS = (STALL_IN_EARLINESS > VALID_AND_STALL_IN_EARLINESS) ? (STALL_IN_EARLINESS-VALID_AND_STALL_IN_EARLINESS) : 0;
        
        logic fifo_not_stall_in, fifo_valid_in;
        earliness_delay #( .PIPE(UNUSED_STALL_IN_EARLINESS) ) stall_in_inst ( .clock(clock), .aclrn(aclrn), .sclrn(sclrn), .i(~i_stall), .o(fifo_not_stall_in) );
        earliness_delay #( .PIPE(UNUSED_VALID_IN_EARLINESS) ) valid_in_inst ( .clock(clock), .aclrn(aclrn), .sclrn(sclrn), .i(i_valid), .o(fifo_valid_in) );
        
        acl_low_latency_fifo
        #(
            .WIDTH                          (WIDTH),
            .DEPTH                          (DEPTH),
            .ALMOST_EMPTY_CUTOFF            (ALMOST_EMPTY_CUTOFF_TEMP), //FIXME: TEMPORARY WORKAROUND
            .ALMOST_FULL_CUTOFF             (ALMOST_FULL_CUTOFF_TEMP),  //FIXME: TEMPORARY WORKAROUND
            .INITIAL_OCCUPANCY              (INITIAL_OCCUPANCY),
            .ASYNC_RESET                    (ASYNC_RESET),
            .SYNCHRONIZE_RESET              (SYNCHRONIZE_RESET),
            .RESET_EVERYTHING               (RESET_EVERYTHING),
            //RESET_EXTERNALLY_HELD parameeter does not exist since there are no pipelines to flush with reset
            .REGISTERED_DATA_OUT_COUNT      (REGISTERED_DATA_OUT_COUNT),
            .HOLD_DATA_OUT_WHEN_EMPTY       (HOLD_DATA_OUT_WHEN_EMPTY),
            .VALID_AND_STALL_IN_EARLINESS   (VALID_AND_STALL_IN_EARLINESS)
            //todo: NEVER_OVERFLOWS
        )
        acl_low_latency_fifo_inst
        (
            .clock                          (clock),
            .resetn                         (resetn),
            .data_in                        (i_data),
            .data_out                       (o_data),
            .valid_in                       (fifo_valid_in),
            .valid_out                      (fifo_is_not_empty),
            .stall_in                       (~fifo_not_stall_in),
            .stall_out                      (fifo_is_full),
            .almost_empty                   (o_almost_empty),
            .almost_full                    (fifo_is_almost_full)
        );
        
        logic not_stall_in_delayed;
        earliness_delay #( .PIPE(VALID_AND_STALL_IN_EARLINESS) ) stall_in_delayed_inst ( .clock(clock), .aclrn(aclrn), .sclrn(sclrn), .i(fifo_not_stall_in), .o(not_stall_in_delayed) );
        assign fifo_forced_read = fifo_is_not_empty & not_stall_in_delayed;     //TODO to come from fifo itself -- will be registered if STALL_IN_EARLINESS >= 1
    end
    if (STYLE == "hs") begin : gen_high_speed_fifo
        localparam MAX_STALL_IN_EARLINESS = (HOLD_DATA_OUT_WHEN_EMPTY) ? 2 : 3; //if one needs o_data to hold when empty, then we cannot completely eliminate the prefetch
        localparam FIFO_STALL_IN_EARLINESS = (STALL_IN_EARLINESS > MAX_STALL_IN_EARLINESS) ? MAX_STALL_IN_EARLINESS : STALL_IN_EARLINESS;
        localparam UNUSED_STALL_IN_EARLINESS = (STALL_IN_EARLINESS > MAX_STALL_IN_EARLINESS) ? (STALL_IN_EARLINESS-MAX_STALL_IN_EARLINESS) : 0;
        
        logic fifo_not_stall_in, fifo_valid_in;
        earliness_delay #( .PIPE(UNUSED_STALL_IN_EARLINESS) ) stall_in_inst ( .clock(clock), .aclrn(aclrn), .sclrn(sclrn), .i(~i_stall), .o(fifo_not_stall_in) );
        earliness_delay #( .PIPE(VALID_IN_EARLINESS       ) ) valid_in_inst ( .clock(clock), .aclrn(aclrn), .sclrn(sclrn), .i(i_valid), .o(fifo_valid_in) );
        
        acl_high_speed_fifo
        #(
            .WIDTH                          (WIDTH),
            .DEPTH                          (DEPTH),
            .ALMOST_EMPTY_CUTOFF            (ALMOST_EMPTY_CUTOFF_TEMP), //FIXME: TEMPORARY WORKAROUND
            .ALMOST_FULL_CUTOFF             (ALMOST_FULL_CUTOFF_TEMP),  //FIXME: TEMPORARY WORKAROUND
            .INITIAL_OCCUPANCY              (INITIAL_OCCUPANCY),
            .ASYNC_RESET                    (ASYNC_RESET),
            .SYNCHRONIZE_RESET              (SYNCHRONIZE_RESET),
            .RESET_EVERYTHING               (RESET_EVERYTHING),
            .RESET_EXTERNALLY_HELD          (RESET_EXTERNALLY_HELD),
            .STALL_IN_EARLINESS             (FIFO_STALL_IN_EARLINESS),
            .REGISTERED_DATA_OUT_COUNT      (REGISTERED_DATA_OUT_COUNT),
            .HOLD_DATA_OUT_WHEN_EMPTY       (HOLD_DATA_OUT_WHEN_EMPTY)
            //todo: NEVER_OVERFLOWS, VALID_IN_EARLINESS
        )
        acl_high_speed_fifo_inst
        (
            .clock                          (clock),
            .resetn                         (resetn),
            .data_in                        (i_data),
            .data_out                       (o_data),
            .valid_in                       (fifo_valid_in),
            .valid_out                      (fifo_is_not_empty),
            .stall_in                       (~fifo_not_stall_in),
            .stall_out                      (fifo_is_full),
            .almost_empty                   (o_almost_empty),
            .almost_full                    (fifo_is_almost_full)
        );
        
        logic not_stall_in_delayed;
        earliness_delay #( .PIPE(FIFO_STALL_IN_EARLINESS) ) stall_in_delayed_inst ( .clock(clock), .aclrn(aclrn), .sclrn(sclrn), .i(fifo_not_stall_in), .o(not_stall_in_delayed) );
        assign fifo_forced_read = fifo_is_not_empty & not_stall_in_delayed;     //TODO to come from fifo itself -- will be registered if STALL_IN_EARLINESS >= 1
    end
    endgenerate
    
endmodule




module earliness_delay #(
    parameter int PIPE
) (
    input  wire  clock,
    input  wire  aclrn,
    input  wire  sclrn,
    input  wire  i,
    output logic o
);
    generate
    if (PIPE==0) begin
        assign o = i;
    end
    else begin
        logic [PIPE-1:0] pipe;
        always_ff @(posedge clock or negedge aclrn) begin
            if (~aclrn) begin
                pipe <= '0;
            end
            else begin
                pipe <= (pipe << 1) | i;
                if (~sclrn) begin
                    pipe <= '0;
                end
            end
        end
        assign o = pipe[PIPE-1];
    end
    endgenerate
endmodule


`default_nettype wire
