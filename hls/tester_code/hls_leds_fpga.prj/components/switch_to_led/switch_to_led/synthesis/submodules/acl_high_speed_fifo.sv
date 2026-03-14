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


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                                                                                                  //
//  ACL HIGH SPEED FIFO                                                                                                                                             //
//  Designed and optimized by: Jason Thong                                                                                                                          //
//                                                                                                                                                                  //
//  DESCRIPTION                                                                                                                                                     //
//  ===========                                                                                                                                                     //
//  This fifo is fmax optimized for Stratix 10 at the expense of area and write-to-read latency. This fifo is natively showahead, e.g. fifo output data is exposed  //
//  without a read request, downstream of the fifo uses a read ack to consume it. Pipelining is added around the memory block (M20K for a deep fifo) to improve     //
//  fmax. A prefetch is used to mask this large read latency, since the fifo interface must support a single clock cycle read handshaking, e.g. read ack now means  //
//  new data as of the next clock cycle.                                                                                                                            //
//                                                                                                                                                                  //
//  REQUIRED FILES                                                                                                                                                  //
//  ==============                                                                                                                                                  //
//  - acl_high_speed_fifo.sv                                                                                                                                        //
//  - acl_lfsr.sv                                                                                                                                                   //
//  - acl_tessellated_incr_decr_threshold.sv                                                                                                                        //
//  - acl_tessellated_incr_lookahead.sv                                                                                                                             //
//  - acl_reset_handler.sv                                                                                                                                          //
//  - acl_fanout_pipeline.sv                                                                                                                                        //
//  - acl_std_synchronizer_nocut.v                                                                                                                                  //
//                                                                                                                                                                  //
//  USAGE                                                                                                                                                           //
//  =====                                                                                                                                                           //
//  This fifo is coded using stall/valid semantics. Upstream indicates it has data available for consumption by asserting valid. Downstream indicates it cannot     //
//  accept data by asserting stall. A transaction occurs when valid==1 && stall==0. A push into the fifo occurs when valid_in==1 && stall_out=0. A pop out of the   //
//  fifo occurs when valid_out==1 && stall_in==0. The data is synchronized to valid.                                                                                //
//                                                                                                                                                                  //
//  LATENCY SPECIFICATION                                                                                                                                           //
//  =====================                                                                                                                                           //
//  Category        | Latency   | Example signals                                                                                                                   //
//  ----------------+-----------+---------------------------------------                                                                                            //
//  write -> write  | 1         | valid_in to stall_out/almost_full                                                                                                 //
//  write -> read   | 5         | valid_in to valid_out/almost_empty                                                                                                //
//  read -> write   | 1         | stall_in to stall_out/almost_full                                                                                                 //
//  read -> read    | 1         | stall_in to valid_out/almost_empty                                                                                                //
//                                                                                                                                                                  //
//  COMPATIBILITY WITH SCFIFO                                                                                                                                       //
//  =========================                                                                                                                                       //
//  See the scfifo_to_acl_high_speed_fifo module at the end of this file, which maps the ports and parameters of scfifo into this fifo. There are some notable      //
//  differences however:                                                                                                                                            //
//  1.  The write to read latency of this fifo is always 5, unlike scfifo which has a different write to read latency depending on if showahead is enabled and if   //
//      the output is registered.                                                                                                                                   //
//  2.  Reset behavior is different. No support for using both asynchronous and synchronous resets at the same time. When using synchronous resets, it takes a few  //
//      clock cycles from the time the reset input is asserted until the fifo actually enters reset. Likewise when reset deasserts. When the fifo is in reset, it   //
//      asserts both full and empty (stall_out and ~valid_out respectively).                                                                                        //
//  3.  Almost_full and almost_empty have exact timing, unlike scfifo which uses slightly stale occupancy. This means there is no strangeness like draining a fifo  //
//      and having empty assert before almost_empty asserts, which can happen in scfifo but is impossible with this fifo.                                           //
//                                                                                                                                                                  //
//  ALMOST FULL AND ALMOST EMPTY                                                                                                                                    //
//  ============================                                                                                                                                    //
//  The ALMOST_***_CUTOFF parameters refer to how much dead space would be in the fifo if one were to use almost_full as same clock cycle backpressure (dead space  //
//  in not being able to completely fill the fifo), or if one were to almost_empty as same clock cycle underflow prevention (dead space in not being able to empty  //
//  the fifo). See chart below for interpretation of values:                                                                                                        //
//                                                                                                                                                                  //
//  Scfifo parameter                    | Our parameter             | Interpretation                                                                                //
//  ------------------------------------+---------------------------+---------------------------------------------------------------                                //
//  almost_empty_value = 1              | ALMOST_EMPTY_CUTOFF = 0   | almost_empty behaves the same way as empty                                                    //
//  almost_empty_value = 2              | ALMOST_EMPTY_CUTOFF = 1   | almost_empty asserts when read_used_words is 1 or less                                        //
//  ------------------------------------+---------------------------+---------------------------------------------------------------                                //
//  almost_full_value = lpm_numwords    | ALMOST_FULL_CUTOFF = 0    | almost_full behaves the same way as full                                                      //
//  almost_full_value = lpm_numwords-1  | ALMOST_FULL_CUTOFF = 1    | almost_full asserts when write_used_words is DEPTH-1 or higher                                //
//                                                                                                                                                                  //
//  INITIAL OCCUPANCY                                                                                                                                               //
//  =================                                                                                                                                               //
//  The parameter INITIAL_OCCUPANCY describes the number of words of garbage data in the fifo as it exits from reset. Typically this is 0, e.g. we have to write    //
//  into the fifo before anything is readable. If INITIAL_OCCUPANCY > 0, then valid_out is 0 during reset, and when it eventually asserts it is then safe for       //
//  downstream to transact reads from the fifo. Exit from reset should be handled separately for upstream and downstream. In particular, the assertion of           //
//  valid_out (to downstream) and the deassertion of stall_out (to upstream) may not happen on the same clock cycle. If INITIAL_OCCUPANCY == DEPTH, one cannot      //
//  use stall_out to observe reset exit, only when at least one item has been read from the fifo will stall_out then deasert.                                       //
//                                                                                                                                                                  //
//  AREA OPTIMIZATION WITH STALL_IN_EARLINESS                                                                                                                       //
//  =========================================                                                                                                                       //
//  If downstream of the fifo knows ahead of time whether it will be able to accept data, e.g. it has an almost_full that can be wired up to this fifo's stall_in,  //
//  we manually retime lots of stuff inside the fifo to remove 1 prefetch stage for each clock cycle that stall_in can be provided early. Indirectly this helps     //
//  fmax since less logic means stuff stays closer together, so less slow routing. When stall_in is 3 clock cycles early, the prefetch outright disappears.         //
//                                                                                                                                                                  //
//  RESET CONFIGURATION                                                                                                                                             //
//  ===================                                                                                                                                             //
//  One may choose whether to consume the reset asynchronously (ASYNC_RESET=1, intended for A10 or older) or synchronously (ASYNC_RESET=0, intended for S10), but   //
//  not both at the same time. Reset consumption is separate from reset distribution. For example, we could consume reset synchronously but distribute it           //
//  asynchronously e.g. using a global clock line, and SYNCHRONIZE_RESET=1 uses local synchronizers before the reset is consumed. If SYNCHRONIZE_RESET=0, it is     //
//  assumed one has externally managed the synchronous release of reset. For partial reconfiguration debug, one can set RESET_EVERYTHING=1 so that reset reaches    //
//  every register. Finally, not every control register is reset when ASYNC_RESET=0, if there is a pipeline of valids, typically only the first and last are reset  //
//  and the reset must be held many clock cycles for the reset to propagate through. A reset pulse stretcher is used, unless RESET_EXTERNALLY_HELD=1 in which case  //
//  it is assumed that reset will be held for sufficiently long (5 clocks for this module).                                                                         //
//                                                                                                                                                                  //
//  RECOMMENDED RESET SETTINGS                                                                                                                                      //
//  ==========================                                                                                                                                      //
//  General usage is intended for when one is unsure about the reset. The HLD platform has specific reset properties e.g. we can remove the reset pulse stretcher.  //
//                                                                                                                                                                  //
//  Parameter             | General usage A10 | General usage S10 |   HLD A10   |   HLD S10                                                                         //
//  ----------------------+-------------------+-------------------+-------------+-------------                                                                      //
//  ASYNC_RESET           |        1          |         0         |     1       |      0                                                                            //
//  SYNCHRONIZE_RESET     |        1          |         1         |     0       |      1                                                                            //
//  RESET_EVERYTHING      |        0          |         0         |     0       |      0                                                                            //
//  RESET_EXTERNALLY_HELD |        0          |         0         |     1       |      1                                                                            //
//                                                                                                                                                                  //
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Known issues/optimizations for future work:
// 1. manual signal replication, e.g. how many physical M20Ks can share 1 copy of our address
// 2. potentially relax the stall_in to stall_out/almost_full latency for improved fmax

// TEMPORARY FIX:
// Reset values are set to match the behavior of before reset cleanup. See FB case:457213. This is a workaround for now.
// Eventually the compiler needs to set the reset parameters correctly, at which point the default values will be set
// back to the original intent, which is for someone who knows nothing about the reset in their system.



`timescale 1ps/1ps
`default_nettype none

module acl_high_speed_fifo #(
    //basic fifo configuration
    parameter int WIDTH,                        // width of the data path through the fifo
    parameter int DEPTH,                        // capacity of the fifo, at least 1
    
    //almost empty and almost full configuration
    parameter int ALMOST_EMPTY_CUTOFF = 0,      // almost_empty asserts if read_used_words <= ALMOST_EMPTY_CUTOFF, read_used_words increments when writes are visible on the read side, decrements when fifo is read
    parameter int ALMOST_FULL_CUTOFF = 0,       // almost_full asserts if write_used_words >= (DEPTH-ALMOST_FULL_CUTOFF), write_used_words increments when fifo is written to, decrements when fifo is read
    
    
    //TEMPORARY WOKAROUND FOR TO-UK SYNC LAG -- the backend is using hld_fifo with the old ALMOST_***_THRESH parameters, keep these around until the change to remove them has propagated to TO
    parameter int ALMOST_EMPTY_THRESH = 1,
    parameter int ALMOST_FULL_THRESH = 0,
    
    
    //initial occupancy
    parameter int INITIAL_OCCUPANCY = 0,        // number of words in the fifo (write side occupancy) when it comes out of reset, note it still takes 5 clocks for this to become visible on the read side
    
    //reset configuration
    parameter bit ASYNC_RESET = 1,              // how do we use reset: 1 means registers are reset asynchronously, 0 means registers are reset synchronously
    parameter bit SYNCHRONIZE_RESET = 0,        // based on how reset gets to us, what do we need to do: 1 means synchronize reset before consumption (if reset arrives asynchronously), 0 means passthrough (managed externally)
    parameter bit RESET_EVERYTHING = 0,         // intended for partial reconfig debug, set to 1 to reset every register (normally async reset excludes data path and sync reset additionally excludes some control signals)
    parameter bit RESET_EXTERNALLY_HELD = 0,    // set to 1 if resetn will be held for at least FIVE clock cycles, otherwise we will internally pulse stretch reset before consumption
    
    //special configurations for higher fmax / lower area
    parameter int STALL_IN_EARLINESS = 0,       // 0, 1, 2 or 3, how many clock cycles early is stall_in provided, latency from ~stall_in to new data_out would be 1, 2, 3, or 4 clocks respectively
    parameter int REGISTERED_DATA_OUT_COUNT = 0,// 0 to WIDTH inclusive, data_out[REGISTERED_DATA_OUT_COUNT-1:0] are registered, the remaining upper bits are unregistered
                                                // generally REGISTERED_DATA_OUT_COUNT should be 0 unless fifo output data drives control logic, in which just those bits should be registered
    //conformance with scfifo
    parameter bit HOLD_DATA_OUT_WHEN_EMPTY = 0, // 0 means data_out can be x when fifo is empty, 1 means data_out will hold last value when fifo is empty (scfifo behavior, has fmax penalty)
                                                // HOLD_DATA_OUT_WHEN_EMPTY cannot be set to 1 when STALL_IN_EARLINESS = 3 since data_out is the hardened m20k read data registers
    //ram settings
    parameter RAM_BLOCK_TYPE = "AUTO"           // "MLAB" | "M20K" | "AUTO" -> ram_block_type parameter of altera_syncram
)
(
    input  wire                 clock,
    input  wire                 resetn,         // see description above for different reset modes
    input  wire     [WIDTH-1:0] data_in,        // data from upstream
    output logic    [WIDTH-1:0] data_out,       // data to downstream
    input  wire                 valid_in,       // upstream advertises it has data, a write happens when valid_in & ~stall_out
    output logic                valid_out,      // advertise to downstream that we have data
    input  wire                 stall_in,       // downstream indicates it cannot accept data - this needs to be early if STALL_IN_EARLINESS > 0
    output logic                stall_out,      // inform upstream that we cannot accept data
    output logic                almost_empty,   // asserts if read_used_words <= ALMOST_EMPTY_CUTOFF
    output logic                almost_full     // asserts if write_used_words >= (DEPTH-ALMOST_FULL_CUTOFF)
);
    
    //TEMPORARY WOKAROUND FOR TO-UK SYNC LAG -- the backend is using hld_fifo with the old ALMOST_***_THRESH parameters, keep these around until the change to remove them has propagated to TO
    //if one does not override the default values, then almost_empty=empty and almost_full=0, so you really do have to set them in order for them to be useful
    localparam int ALMOST_EMPTY_CUTOFF_TEMP = (ALMOST_EMPTY_THRESH == 1) ? ALMOST_EMPTY_CUTOFF : (ALMOST_EMPTY_THRESH-1);
    localparam int ALMOST_FULL_CUTOFF_TEMP = (ALMOST_FULL_THRESH == 0) ? ALMOST_FULL_CUTOFF : (DEPTH-ALMOST_FULL_THRESH);
    
    
    ///////////////////////////
    //                       //
    //  Signal declarations  //
    //                       //
    ///////////////////////////
    
    localparam int PREFETCH_STAGES_RAW  = 3-STALL_IN_EARLINESS;                         // STALL_IN_EARLINESS=0,1,2,3 makes PREFETCH_STAGESR_RAW=3,2,1,0 respectively
    localparam int PREFETCH_STAGES      = (DEPTH < PREFETCH_STAGES_RAW) ? DEPTH : PREFETCH_STAGES_RAW;  //clip based on depth since the prefetch adds capacity
    localparam int PREFETCH_BITS_RAW    = $clog2(PREFETCH_STAGES+1);                    // number of bits in prefetch counters
    localparam int PREFETCH_BITS        = (!PREFETCH_BITS_RAW) ? 1 : PREFETCH_BITS_RAW; // don't make this zero just to avoid syntax error
    localparam int USE_LFSR             = (STALL_IN_EARLINESS<=2) ? 1 : 0;              // m20k addresses is lfsr if capacity regained from at least 1 prefetch stage, else use tessellated counter which needs early increment
    localparam int ADDR_RAW             = $clog2(DEPTH+USE_LFSR-PREFETCH_STAGES);       // number of address bits for m20k, lose 1 capacity due to nonzero state of lfsr, prefetch adds PREFETCH_STAGES of capacity
    localparam int ADDR                 = (ADDR_RAW < 2) ? 2 : ADDR_RAW;                // minimum size of lfsr
    
    genvar g;
    
    //reset signals
    //all active low, aclrn is only used if ASYNC_RESET=1 otherwise sclrn_* is used, resetn_* is passed into submodules who internally decide whether to use it asynchronously or not
    logic aclrn, sclrn_before_pulse_stretch;
    logic [4:0] sclrn_chain /* synthesis dont_merge */;
    logic sclrn_pulse_stretched, sclrn_base, sclrn_internal, sclrn_pref_received, sclrn_reset_everything /* synthesis dont_merge */;
    logic resetn_wraddr, resetn_rdaddr /* synthesis dont_merge */;
    logic resetn_addr_match, resetn_full, resetn_almost_full, resetn_almost_empty /* synthesis dont_merge */;
    
    //signals that interface directly to the memory block
    logic m20k_wren, m20k_wren_for_others /* synthesis dont_merge */;
    logic [ADDR-1:0] m20k_wraddr, m20k_rdaddr;
    logic [WIDTH-1:0] m20k_wrdata, m20k_rddata;
    
    //signals to determine whether to initiate transfer from memory block into prefetch
    logic try_feed_prefetch, feed_prefetch;
    logic wr_addr_ahead_of_rd_addr;
    logic m20k_hardened_rdaddr_valid, m20k_hardened_rddata_valid;
    
    //signals to track occupancy in prefetch
    logic decr_pref_requsted, pref_loading;
    logic [1:0] pref_requested, pref_received;
    logic pref_insertion_lo, pref_insertion_hi;
    logic prefetch_full, prefetch_valid, prefetch_valid_pre;
    
    //data path of prefetch signals
    logic data_out_clock_en_reg, data_out_clock_en_comb;
    logic data1_clock_en, data2_clock_en, data3_clock_en /* synthesis dont_merge */;
    logic [WIDTH-1:0] data1, data2, data3, data_out_reg, data_out_unreg;
    
    //signals to track fifo occupancy as seen by outside world
    logic valid_out_early_by_two, read_from_fifo_early_by_two;
    logic valid_out_early, read_from_fifo_early;
    logic try_read_from_fifo, read_from_fifo;
    logic [2:0] m20k_wren_delayed;
    logic not_almost_empty;
    
    
    
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //                                                                                                        //
    //  Retiming summary                                                                                      //
    //                                                                                                        //
    //  IMPORTANT: read the comments in each section so that you know what each signal means BEFORE reading   //
    //  this table.                                                                                           //
    //                                                                                                        //
    //  If stall_in is known ahead of time, we can reduce the number of prefetch stages to save area.         //
    //  Anything that depends on stall_in can be computed earlier, which means we know ahead of time when     //
    //  data will exit from the prefetch.                                                                     //
    //                                                                                                        //
    //  Timing sensitive paths at large data widths tend to be from the following:                            //
    //  1. stall_in to read address register inside M20K (assume FIFO is deep)                                //
    //  2. stall_in through control logic of prefetch data path to data_out (unregistering data_out helps)    //
    //                                                                                                        //
    //  If stall_in can be known at least 3 clocks early, we can outright eliminate the prefetch. In this     //
    //  configuration, the fifo output data is the M20K read data registers. Also the high fan-out problem    //
    //  is now pushed into hardened logic (the address decoder inside the M20K). Typically one still needs    //
    //  another register after the M20K output before consuming the data to allow for routing delay.          //
    //                                                                                                        //
    //  To reach high fmax, we need extra registers on the path feeding stall_in that can get retimed into    //
    //  the fifo. For example, if downstream can advertise an almost full which is 10 items lower than its    //
    //  capacity, this almost full could be sent through 7 registers before feeding stall_in of this fifo,    //
    //  and this fifo could use STALL_IN_EARLINESS = 3.                                                       //
    //                                                                                                        //
    //  As a general guideline when optimizing for fmax, if one can provide stall_in one clock cycle early    //
    //  it generally better to register it outside of the FIFO and use STALL_IN_EARLINESS = 3. This will get  //
    //  retimed into the FIFO and it usually provides more fmax benefit than removing a prefetch stage. Once  //
    //  one register is added to stall_in, typically it is then more beneficial to fmax to remove prefetch    //
    //  stages, as less logic means it gets placed physically closer together (less wire delay and probably   //
    //  less routing congestion). Once the prefetch disappears, one can only add registers on stall_in        //
    //  outside of the FIFO. In summary:                                                                      //
    //                                                                                                        //
    //  Functional  |       Recommended FIFO configuration for highest fmax                                   //
    //  earliness   +--------------------+-------------------------------------------                         //
    //  of stall_in | STALL_IN_EARLINESS | Registers before stall_in outside of FIFO                          //
    //  ------------+--------------------+-------------------------------------------                         //
    //      0       |          0         |                   0                                                //
    //      1       |          0         |                   1                                                //
    //      2       |          1         |                   1                                                //
    //      3       |          2         |                   1                                                //
    //      4       |          3         |                   1                                                //
    //      5       |          3         |                   2                                                //
    //                                                                                                        //
    //  For a given FIFO configuration, the following summarizes the latency from stall_in to various         //
    //  internals of the FIFO (more latency is better for fmax) and the manual retiming that is done:         //
    //                                                                                                        //
    //                                          Base case |    Area -1    |    Area -2     |    Area -3       //
    //  --------------------------------------------------+---------------+----------------+----------------  //
    //  Configuration:                                    |               |                |                  //
    //    STALL_IN_EARLINESS                        0     |        1      |        2       |        3         //
    //    PREFETCH_STAGES                           3     |        2      |        1       |        0         //
    //  --------------------------------------------------+---------------+----------------+----------------  //
    //  Clock cycles of latency from stall_in to xxx:     |               |                |                  //
    //    stall_in to m20k_rdaddr                   1     |        1      |        1       |        2         //
    //    stall_in to wr_addr_ahead_of_rd_addr      1     |        1      |        1       |        1         //
    //    stall_in to pref_requested                1     |        1      |        1       |       N/A        //
    //    stall_in to pref_received                 1     |        1      |        1       |       N/A        //
    //    stall_in to data_out_clock_en             0     |        1      |       N/A      |       N/A        //
    //    stall_in to pref_insertion_{hi,lo}        1     |        2      |       N/A      |       N/A        //
    //  --------------------------------------------------+---------------+----------------+----------------  //
    //  Manual retiming due to early stall_in:            |               |                |                  //
    //    wr_addr_ahead_of_rd_addr retimed          0     |        0      |        0       |        0         //
    //    pref_requested retimed                    0     | 1 clock early | 2 clocks early |       N/A        //
    //    pref_received retimed                     0     | 1 clock early | 2 clocks early |       N/A        //
    //                                                                                                        //
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    
    
    
    ////////////////////////
    //                    //
    //  Reset sequencing  //
    //                    //
    ////////////////////////
    
    // The tessellated incr/decr/threshold detector requires at least 5 clock cycles of holding reset to let it flush
    // through the tessellated adder. We also don't want something like e.g. an LFSR (M20K address) coming out of reset
    // before the incr/decr/threshold is stable. So everyone gets a 5 clock cycle pulse stretched reset. This is then
    // put through another 2 registers after pulse stretching to facilitate retiming.
    //
    // If the reset is asynchronous, every register is reset. The assumption is either async reset is on a global clock
    // or we are debugging something related to initial conditions.
    //
    // Reset dependence          | Module                   | Fanout (not including duplicates that Quartus makes on its own)
    // --------------------------+--------------------------+----------------------------------------------------------------
    // m20k_wraddr               | lfsr or tess incr        | approx 10 - has its own reset
    // m20k_rdaddr               | lfsr or tess incr        | approx 10 - has its own reset
    // wr_addr_ahead_of_rd_addr  | tess incr decr threshold | approx 10 - has its own reset
    // m20k_wren                 | this module              | 1
    // pref_requested            | this module              | 1 or 2
    // valid_out                 | this module              | 1
    // pref_received             | this module              | 1 or 2, this probably gets replicated many times at large WIDTH
    // prefetch_valid            | this module              | 1 - has its own together with pref_received
    // stall_out                 | tess incr decr threshold | approx 10 - has its own reset
    // almost_full               | tess incr decr threshold | approx 10 - has its own reset
    // almost_empty              | tess incr decr threshold | approx 10 - has its own reset
    //
    // S10 reset specification:
    // S (clocks to enter reset "safe state"): 5 (resetn -> chain[0] -> pulse_stretched -> base -> internal -> actual register)
    // P (minimum duration of reset pulse):    1 (but internally we pulse stretch to 5 clocks)
    // D (clocks to exit reset "safe state"):  9 (resetn -> chain[0] -> ... -> chain[4] -> pulse_stretched -> base -> internal -> actual register)
    
    acl_reset_handler
    #(
        .ASYNC_RESET            (ASYNC_RESET),
        .USE_SYNCHRONIZER       (SYNCHRONIZE_RESET),
        .SYNCHRONIZE_ACLRN      (SYNCHRONIZE_RESET),
        .PIPE_DEPTH             (0),
        .NUM_COPIES             (1)
    )
    acl_reset_handler_inst
    (
        .clk                    (clock),
        .i_resetn               (resetn),
        .o_aclrn                (aclrn),
        .o_resetn_synchronized  (),
        .o_sclrn                (sclrn_before_pulse_stretch)
    );
    
    generate
    if (ASYNC_RESET) begin : async_reset
        assign sclrn_internal = 1'b1;
        assign sclrn_pref_received = 1'b1;
        assign sclrn_reset_everything = 1'b1;
        assign resetn_wraddr = aclrn;
        assign resetn_rdaddr = aclrn;
        assign resetn_addr_match = aclrn;
        assign resetn_full = aclrn;
        assign resetn_almost_full = aclrn;
        assign resetn_almost_empty = aclrn;
    end
    else begin : sync_reset
        always_ff @(posedge clock) begin
            sclrn_chain <= (sclrn_chain << 1) | sclrn_before_pulse_stretch;
            sclrn_pulse_stretched <= (RESET_EXTERNALLY_HELD) ? sclrn_before_pulse_stretch : (&sclrn_chain);
            sclrn_base <= sclrn_pulse_stretched;
            sclrn_internal <= sclrn_base;
            sclrn_reset_everything <= (RESET_EVERYTHING) ? sclrn_base : 1'b1;
            sclrn_pref_received <= sclrn_base;
            resetn_wraddr <= sclrn_base;
            resetn_rdaddr <= sclrn_base;
            resetn_addr_match <= sclrn_base;
            resetn_full <= sclrn_base;
            resetn_almost_full <= sclrn_base;
            resetn_almost_empty <= sclrn_base;
        end
    end
    endgenerate
    
    
    
    ////////////////////
    //                //
    //  Memory block  //
    //                //
    ////////////////////
    
    generate
    if (WIDTH > 0) begin : gen_ram
        altera_syncram #(   //modelsim library: altera_lnsim
            .numwords_a (2**ADDR),
            .numwords_b (2**ADDR),
            .address_aclr_b ("NONE"),
            .address_reg_b ("CLOCK0"),
            .clock_enable_input_a ("BYPASS"),
            .clock_enable_input_b ("BYPASS"),
            .clock_enable_output_b ("BYPASS"),
            .enable_ecc ("FALSE"),
            .intended_device_family ("Stratix 10"), //quartus will correct this automatically to whatever your project actually uses
            .lpm_type ("altera_syncram"),
            .operation_mode ("DUAL_PORT"),
            .outdata_aclr_b ("NONE"),
            .outdata_sclr_b ("NONE"),
            .outdata_reg_b ("CLOCK0"),
            .power_up_uninitialized ("TRUE"),
            .ram_block_type (RAM_BLOCK_TYPE),   //"MLAB" | "M20K" | "AUTO"
            .read_during_write_mode_mixed_ports ("DONT_CARE"),
            .widthad_a (ADDR),
            .widthad_b (ADDR),
            .width_a (WIDTH),
            .width_b (WIDTH),
            .width_byteena_a (1)
        )
        altera_syncram
        (
            //clock, no reset
            .clock0     (clock),
            
            //write port
            .wren_a     (m20k_wren),
            .address_a  (m20k_wraddr),
            .data_a     (m20k_wrdata),
            
            //read port
            .address_b  (m20k_rdaddr),
            .q_b        (m20k_rddata),
            
            //unused
            .aclr0 (1'b0),
            .aclr1 (1'b0),
            .address2_a (1'b1),
            .address2_b (1'b1),
            .addressstall_a (1'b0),
            .addressstall_b (1'b0),
            .byteena_a (1'b1),
            .byteena_b (1'b1),
            .clock1 (1'b1),
            .clocken0 (1'b1),
            .clocken1 (1'b1),
            .clocken2 (1'b1),
            .clocken3 (1'b1),
            .data_b ({WIDTH{1'b1}}),
            .eccencbypass (1'b0),
            .eccencparity (8'b0),
            .eccstatus (),
            .q_a (),
            .rden_a (1'b1),
            .rden_b (1'b1),
            .sclr (1'b0),
            .wren_b (1'b0)
        );
    end
    endgenerate
    
    
    ///////////////////////////////////////////
    //                                       //
    //  Write side control of memory block   //
    //                                       //
    ///////////////////////////////////////////
    
    // There is one pipeline stage before incoming data is written into m20k. If write enable is high then address
    // changes on the next clock, so address stays at next available place to write.
    //
    // Except for STALL_IN_EARLINESS=3, addresses use LFSRs (linear feedback shift registers) instead of counters
    // since the next state logic is simpler (probably easier to retime). The read address must follow the same
    // sequence as the write address, but the sequence itself does not matter.
    //
    // We lose one capacity from the M20K when using LFSRs since the all zeros state is illegal. We can recover this
    // capacity from the prefetch, unless STALL_IN_EARLINESS=3 in which case there is no prefetch. In this case, we
    // use a tessellated adder for the addresses since the increment is known one clock cycle early.
    
    always_ff @(posedge clock or negedge aclrn) begin
        if (~aclrn) begin
            m20k_wren <= 1'b0;
            m20k_wren_for_others <= 1'b0;
            m20k_wrdata <= (RESET_EVERYTHING) ? '0 : 'x;
        end
        else begin
            m20k_wren <= valid_in & ~stall_out;
            m20k_wren_for_others <= valid_in & ~stall_out;  //copy of m20k_wren, logic not related to m20k won't be pulled in close to m20k
            m20k_wrdata <= data_in;
            if (~sclrn_internal) begin
                m20k_wren <= 1'b0;
                m20k_wren_for_others <= 1'b0;
            end
            if (~sclrn_reset_everything) m20k_wrdata <= '0;
        end
    end
    
    generate
    if (USE_LFSR) begin : wraddr_lfsr
        acl_lfsr #(
            .WIDTH                  (ADDR),
            .ASYNC_RESET            (ASYNC_RESET),
            .SYNCHRONIZE_RESET      (0),
            .INITIAL_OCCUPANCY      (INITIAL_OCCUPANCY)
        )
        m20k_wraddr_inst
        (
            .clock                  (clock),
            .resetn                 (resetn_wraddr),
            .enable                 (m20k_wren_for_others),
            .state                  (m20k_wraddr)
        );
    end
    else begin : wraddr_tess
        acl_tessellated_incr_lookahead #(
            .WIDTH                  (ADDR),
            .ASYNC_RESET            (ASYNC_RESET),
            .SYNCHRONIZE_RESET      (0),
            .RESET_EVERYTHING       (RESET_EVERYTHING),
            .RESET_EXTERNALLY_HELD  (1),
            .INITIAL_OCCUPANCY      (INITIAL_OCCUPANCY)
        )
        m20k_wraddr_inst
        (
            .clock                  (clock),
            .resetn                 (resetn_wraddr),
            .incr                   (valid_in & ~stall_out),
            .count                  (m20k_wraddr)
        );
    end
    endgenerate
    
    
    
    //////////////////////////////////////////
    //                                      //
    //  Read side control of memory block   //
    //                                      //
    //////////////////////////////////////////
    
    // If there is a prefetch, the read port is kept in a +1 state. Bascially we leave read data dangling on the read port of the memory
    // tblock. Assume read latency through the memory block including pipeline registers is N clock cycles (in this case N = 3), Once there
    // will be space available in the prefetch, ask for new data now and pick up the existing read data in N-1 clocks from now.
    //
    // If there is no prefetch, we cannot use the dangling data optimization. However stall_in is now sufficiently early that we
    // can use stall_in to update the read address, and even with the latency through the memory, the output data will udpate in time.
    
    assign try_feed_prefetch = ~prefetch_full | ~stall_in;
    assign feed_prefetch = wr_addr_ahead_of_rd_addr & try_feed_prefetch;    //there is data available in memory and prefetch will have space
    
    always_ff @(posedge clock or negedge aclrn) begin
        if (~aclrn) begin
            m20k_hardened_rdaddr_valid <= 1'b0;
            m20k_hardened_rddata_valid <= 1'b0;
        end
        else begin
            m20k_hardened_rdaddr_valid <= feed_prefetch;                    //track the read valid through the memory
            m20k_hardened_rddata_valid <= m20k_hardened_rdaddr_valid;
            if (~sclrn_reset_everything) begin
                m20k_hardened_rdaddr_valid <= 1'b0;
                m20k_hardened_rddata_valid <= 1'b0;
            end
        end
    end
    
    generate
    if (USE_LFSR) begin : rdaddr_lfsr
        acl_lfsr #(
            .WIDTH                  (ADDR),
            .ASYNC_RESET            (ASYNC_RESET),
            .SYNCHRONIZE_RESET      (0),
            .INITIAL_OCCUPANCY      (0)
        )
        m20k_rdaddr_inst
        (
            .clock                  (clock),
            .resetn                 (resetn_rdaddr),
            .enable                 (feed_prefetch),
            .state                  (m20k_rdaddr)
        );
    end
    else begin : rdaddr_tess
        acl_tessellated_incr_lookahead #(
            .WIDTH                  (ADDR),
            .ASYNC_RESET            (ASYNC_RESET),
            .SYNCHRONIZE_RESET      (0),
            .RESET_EVERYTHING       (RESET_EVERYTHING),
            .RESET_EXTERNALLY_HELD  (1),
            .INITIAL_OCCUPANCY      (0)
        )
        m20k_rdaddr_inst
        (
            .clock                  (clock),
            .resetn                 (resetn_rdaddr),
            .incr                   (feed_prefetch),
            .count                  (m20k_rdaddr)
        );
    end
    endgenerate
    
    
    
    /////////////////////////////////////
    //                                 //
    //  Address match lookahead logic  //
    //                                 //
    /////////////////////////////////////
    
    // The memory block is configured so that reading and writing from the same address returns X. Therefore a read is valid
    // only once the write address has advanced past the read address. The signal wr_addr_ahead_of_rd_addr is functionally
    // equivalent to using combinational logic to check if m20k_wraddr != m20k_rdaddr. We look at ways of getting into
    // this state so that we can register wr_addr_ahead_of_rd_addr.
    
    acl_tessellated_incr_decr_threshold #(
        .CAPACITY                   (DEPTH),
        .THRESHOLD                  (1),
        .INITIAL_OCCUPANCY          (INITIAL_OCCUPANCY),
        .RESET_RELEASE_DELAY        (1),        //incr is 1 clock behind valid_in, so release initial occupancy to downstream control logic 1 clock after already out of reset
        .THRESHOLD_REACHED_AT_RESET (0),
        .ASYNC_RESET                (ASYNC_RESET),
        .SYNCHRONIZE_RESET          (0),
        .RESET_EVERYTHING           (RESET_EVERYTHING),
        .RESET_EXTERNALLY_HELD      (1)
    )
    addr_match_inst
    (
        .clock                      (clock),
        .resetn                     (resetn_addr_match),
        .incr_no_overflow           (m20k_wren_for_others),
        .incr_raw                   (m20k_wren_for_others),
        .decr_no_underflow          (feed_prefetch),
        .decr_raw                   (try_feed_prefetch),
        .threshold_reached          (wr_addr_ahead_of_rd_addr)
    );
    
    
    
    ////////////////////////////////
    //                            //
    //  Prefetch request control  //
    //                            //
    ////////////////////////////////
    
    // The signal pref_requested tracks the occupancy that has been reserved inside the prefetch. It increases when we ask for
    // data from the M20K, it decreases when data is read from the fifo, no change to value if both or neither event occurs.
    // If STALL_IN_EARLINESS > 0, pref_requested is retimed earlier since we know ahead of time when data exits the prefetch.
    // prefetch_full is functionally equivalent to using combinational logic to check if pref_requested == PREFETCH_STAGES,
    // but this is retimed to be registered by looking at how we enter and exit this state.
    
    generate
    if (PREFETCH_STAGES == 0) begin : pref_req_0                //area -3
        assign prefetch_full = 1'b1;
    end
    else begin : pref_req
        if (PREFETCH_STAGES == 1) begin : pref_req_1            //area -2
            assign prefetch_full = pref_requested[0];           //pref_requested == 1
        end
        if (PREFETCH_STAGES == 2) begin : pref_req_2            //area -1
            assign prefetch_full = pref_requested[1];           //pref_requested == 2, use msb since count cannot reach 3
        end
        if (PREFETCH_STAGES == 3) begin : pref_req_3            //base case
            always_ff @(posedge clock or negedge aclrn) begin   //lookahead to check pref_requested == 3, we could be 2 and increasing or 3 and not decreasing
                if (~aclrn) prefetch_full <= 1'b0;
                else begin
                    prefetch_full <= (pref_requested==2'h2 & wr_addr_ahead_of_rd_addr & ~decr_pref_requsted) | (pref_requested==2'h3 & (wr_addr_ahead_of_rd_addr | ~decr_pref_requsted));
                    if (~sclrn_reset_everything) prefetch_full <= 1'b0;
                end
            end
        end
        assign decr_pref_requsted = prefetch_valid & ~stall_in;
        
        always_ff @(posedge clock or negedge aclrn) begin
            if (~aclrn) begin
                pref_requested <= 'h0;
            end
            else begin
                if (wr_addr_ahead_of_rd_addr & ~decr_pref_requsted & (pref_requested[PREFETCH_BITS-1:0]<PREFETCH_STAGES)) pref_requested <= pref_requested + 1'b1;
                if (~wr_addr_ahead_of_rd_addr & decr_pref_requsted) pref_requested <= pref_requested - 1'b1;
                if (~sclrn_internal) pref_requested <= 'h0;
            end
        end
    end
    endgenerate
    
    
    
    ////////////////////////////////
    //                            //
    //  Prefetch receive control  //
    //                            //
    ////////////////////////////////
    
    // It takes time from when we request read data from the M20K until it arrives, so we need a separate counter instead of
    // pref_requested to know where to slot in the data into the prefetch. The signal pref_received tracks this: it increases
    // when read data arrives from the M20K, it decreases when data is read from the fifo, no change to value if both or
    // neither event occurs. If STALL_IN_EARLINESS > 0, pref_received is retimed earlier since we know ahead of time when data
    // will exit the prefetch. In this case pref_received changes *BEFORE* data gets loaded into the prefetch due to the retiming
    // so we need to keep this data alive until the read data is actually ready to be loaded (pref_insertion tracks this).
    // The same retiming trick as prefetch_full is done to prefetch_valid, which is functionally equiavalent to using
    // combinational to check if pref_received != 0.
    
    // TODO: knowing stall_in N clocks ahead of time then we also know valid_out N clocks ahead of time. Currently we don't
    // expose this outside of the fifo, but we could...
    
    generate
    if (STALL_IN_EARLINESS <= 2) begin : pref_rec
        if (STALL_IN_EARLINESS == 0) begin : pref_rec0
            assign pref_loading = m20k_hardened_rddata_valid;
            assign prefetch_valid = prefetch_valid_pre;
        end
        if (STALL_IN_EARLINESS == 1) begin : pref_rec1
            assign pref_loading = m20k_hardened_rdaddr_valid;
            assign prefetch_valid = prefetch_valid_pre;
        end
        if (STALL_IN_EARLINESS == 2) begin : pref_rec2
            assign pref_loading = feed_prefetch;
            assign prefetch_valid = pref_received[0];
        end
        //STALL_IN_EARLINESS == 3 does not use prefetch_valid
        
        always_ff @(posedge clock or negedge aclrn) begin
            if (~aclrn) begin
                pref_received <= 'h0;
                prefetch_valid_pre <= 1'b0;
            end
            else begin
                if (pref_loading & ((pref_received[PREFETCH_BITS-1:0]=='0) | stall_in)) pref_received <= pref_received + 1'b1;
                if (~pref_loading & (pref_received[PREFETCH_BITS-1:0]!='0) & ~stall_in) pref_received <= pref_received - 1'b1;
                prefetch_valid_pre <= pref_loading | ~(pref_received==2'h0 | (pref_received==2'h1 & ~stall_in));
                if (~sclrn_pref_received) begin
                    pref_received <= 'h0;
                    prefetch_valid_pre <= 1'b0;
                end
            end
        end
    end
    endgenerate
    
    
    
    //////////////////////////
    //                      //
    //  Prefetch data path  //
    //                      //
    //////////////////////////
    
    // If STALL_IN_EARLINESS > 0 then pref_received changes before data arrives at the prefetch. To know where in the
    // prefetch to load data arriving from M20K, we keep pref_received live for longer and call it pref_insertion_{hi,lo}.
    
    // Sizing of the prefetch: if STALL_IN_EARLINESS = 0 we only have 3 prefetch stages even through there are 4 signals
    // -- if output data is registered, it depends on m20k_rddata, data1, or data2,
    // -- if output data is unregistered, it depends on data1, data2, or data3.
    // Different bits of the data path may use different settings, but in all cases there are still 3 registers per output bit.
    // If STALL_IN_EARLINESS == 0, do not register too many bits of output data since data_out_clock_en is combinational
    // logic and high fan-out will lower fmax.
    
    always_ff @(posedge clock or negedge aclrn) begin    //not all of this will get used, let quartus trim it away
        if (~aclrn) begin
            data1_clock_en <= 1'b0;
            data2_clock_en <= 1'b0;
            data3_clock_en <= 1'b0;
            data1 <= (RESET_EVERYTHING) ? '0 : 'x;
            data2 <= (RESET_EVERYTHING) ? '0 : 'x;
            data3 <= (RESET_EVERYTHING) ? '0 : 'x;
        end
        else begin
            data1_clock_en <= m20k_hardened_rdaddr_valid;   //copies of m20k_hardened_rddata_valid to reduce fan-out
            data2_clock_en <= m20k_hardened_rdaddr_valid;
            data3_clock_en <= m20k_hardened_rdaddr_valid;
            if (data1_clock_en) data1 <= m20k_rddata;
            if (data2_clock_en) data2 <= data1;
            if (data3_clock_en) data3 <= data2;
            if (~sclrn_reset_everything) begin
                data1_clock_en <= 1'b0;
                data2_clock_en <= 1'b0;
                data3_clock_en <= 1'b0;
                data1 <= '0;
                data2 <= '0;
                data3 <= '0;
            end
        end
    end
    
    //clock enable is combinational logic if there is no earliness for stall_in, otherwise it is registered
    assign data_out_clock_en_comb = (!HOLD_DATA_OUT_WHEN_EMPTY) ? (~prefetch_valid | ~stall_in) : ((~prefetch_valid & pref_loading) | (~stall_in & (pref_loading | pref_received>=2'h2)));
    
    generate
    if (STALL_IN_EARLINESS == 0) begin : gen_pref3  //base case
        assign {pref_insertion_hi, pref_insertion_lo} = pref_received;  //if PREFETCH_BITS==1, the pref_received extends to {1'b0,pref_received[0]}
        always_ff @(posedge clock or negedge aclrn) begin
            if (~aclrn) begin
                data_out_reg <= (RESET_EVERYTHING) ? '0 : 'x;
            end
            else begin
                if (data_out_clock_en_comb) data_out_reg <= (~pref_insertion_hi) ? m20k_rddata : (~pref_insertion_lo) ? data1 : data2;
                if (~sclrn_reset_everything) data_out_reg <= '0;
            end
        end
        assign data_out_unreg = (~pref_insertion_hi) ? data1 : (~pref_insertion_lo) ? data2 : data3;
    end
    if (STALL_IN_EARLINESS == 1) begin : gen_pref2  //area -1 -> 3:1 mux above reduces to 2:1
        always_ff @(posedge clock or negedge aclrn) begin
            if (~aclrn) begin
                data_out_clock_en_reg <= 1'b0;
                pref_insertion_hi <= 1'b0;
            end
            else begin
                data_out_clock_en_reg <= data_out_clock_en_comb;
                pref_insertion_hi <= (pref_received >= 2'h2);   //same as pref_received[1], but need to have pref_insertion_hi = 0 when PREFETCH_BITS==1
                if (~sclrn_reset_everything) begin
                    data_out_clock_en_reg <= 1'b0;
                    pref_insertion_hi <= 1'b0;
                end
            end
        end
        always_ff @(posedge clock or negedge aclrn) begin
            if (~aclrn) begin
                data_out_reg <= (RESET_EVERYTHING) ? '0 : 'x;
            end
            else begin
                if (data_out_clock_en_reg) data_out_reg <= (~pref_insertion_hi) ? m20k_rddata : data1;
                if (~sclrn_reset_everything) data_out_reg <= '0;
            end
        end
        assign data_out_unreg = (~pref_insertion_hi) ? data1 : data2;
    end
    if (STALL_IN_EARLINESS == 2) begin : gen_pref1  //area -2 -> mux completely collapses
        assign data_out_unreg = data1;
        assign data_out_reg = data1;
    end
    if (STALL_IN_EARLINESS == 3) begin : gen_pref0  //area -3 -> prefetch completely disappears
        assign data_out_unreg = m20k_rddata;
        assign data_out_reg = m20k_rddata;
    end
    
    //select whether to use registered or unregistered data_out
    if (REGISTERED_DATA_OUT_COUNT == 0) begin : gen_registered_data_out
        assign data_out = data_out_unreg;
    end
    else if (REGISTERED_DATA_OUT_COUNT == WIDTH) begin : gen_unregistered_data_out
        assign data_out = data_out_reg;
    end
    else begin : gen_mixed_reg_data_out
        assign data_out = {data_out_unreg[WIDTH-1:REGISTERED_DATA_OUT_COUNT], data_out_reg[REGISTERED_DATA_OUT_COUNT-1:0]};
    end
    endgenerate
    
    
    
    //////////////////////////////////////
    //                                  //
    //  Read valid retiming resolution  //
    //                                  //
    //////////////////////////////////////
    
    // The fifo is empty if the prefetch is empty, but prefetch_valid is retimed earlier if STALL_IN_EARLINESS > 0
    
    generate
    if (STALL_IN_EARLINESS == 0) begin : valid_out0
        assign valid_out = prefetch_valid;
        assign read_from_fifo = prefetch_valid & ~stall_in;
        assign try_read_from_fifo = ~stall_in;
    end
    if (STALL_IN_EARLINESS == 1) begin : valid_out1
        always_ff @(posedge clock or negedge aclrn) begin
            if (~aclrn) begin
                valid_out <= 1'b0;
                read_from_fifo <= 1'b0;
            end
            else begin
                valid_out <= prefetch_valid;
                read_from_fifo <= prefetch_valid & ~stall_in;
                if (~sclrn_internal) valid_out <= 1'b0;
                if (~sclrn_reset_everything) read_from_fifo <= 1'b0;
            end
        end
        assign try_read_from_fifo = read_from_fifo;
    end
    if (STALL_IN_EARLINESS == 2) begin : valid_out2
        always_ff @(posedge clock or negedge aclrn) begin
            if (~aclrn) begin
                valid_out_early <= 1'b0;
                valid_out <= 1'b0;
                read_from_fifo_early <= 1'b0;
                read_from_fifo <= 1'b0;
            end
            else begin
                valid_out_early <= prefetch_valid;
                valid_out <= valid_out_early;
                read_from_fifo_early <= prefetch_valid & ~stall_in;
                read_from_fifo <= read_from_fifo_early;
                if (~sclrn_internal) valid_out <= 1'b0;
                if (~sclrn_reset_everything) begin
                    valid_out_early <= 1'b0;
                    read_from_fifo_early <= 1'b0;
                    read_from_fifo <= 1'b0;
                end
            end
        end
        assign try_read_from_fifo = read_from_fifo;
    end
    if (STALL_IN_EARLINESS == 3) begin : valid_out3
        always_ff @(posedge clock or negedge aclrn) begin
            if (~aclrn) begin
                valid_out_early_by_two <= 1'b0;
                valid_out_early <= 1'b0;
                valid_out <= 1'b0;
                read_from_fifo_early_by_two <= 1'b0;
                read_from_fifo_early <= 1'b0;
                read_from_fifo <= 1'b0;
            end
            else begin
                valid_out_early_by_two <= wr_addr_ahead_of_rd_addr;
                valid_out_early <= valid_out_early_by_two;
                valid_out <= valid_out_early;
                read_from_fifo_early_by_two <= wr_addr_ahead_of_rd_addr & ~stall_in;
                read_from_fifo_early <= read_from_fifo_early_by_two;
                read_from_fifo <= read_from_fifo_early;
                if (~sclrn_internal) valid_out <= 1'b0;
                if (~sclrn_reset_everything) begin
                    valid_out_early_by_two <= 1'b0;
                    valid_out_early <= 1'b0;
                    read_from_fifo_early_by_two <= 1'b0;
                    read_from_fifo_early <= 1'b0;
                    read_from_fifo <= 1'b0;
                end
            end
        end
        assign try_read_from_fifo = read_from_fifo;
    end
    endgenerate
    
    
    
    /////////////////
    //             //
    //  Fifo full  //
    //             //
    /////////////////
    
    // Let us track whether incrementing and decrementing has caused a threshold to be reached. Generally an increment
    // is composed of two parts: 1. we want to increment (valid_in), and 2. we are allowed to increment (~stall_out).
    // The same two part composition applies to decrement.
    //
    // Suppose we are trying to detect a threshold of N. We reach the threshold when the occupancy is N-1 and we are
    // increasing, and we have no longer reached the threshold when the occupancy is N and we are decreasing.
    // The occupancy has to be tracked using the guarded increment and decrement (incr_no_overflow and decr_no_underflow),
    // but the increasing or decreasing used to change the state of threshold_reached does not need to be guarded if
    // the threshold N is far away from overflow or underflow.
    //
    // This fifo has a 5 clock latency from write to read, so it is possible that write_used_words can be at fifo capacity
    // (fifo is full) while stall_in is off (downstream wants to read) and valid_out is off (no data to provide to downstream).
    // For a threshold of 5 or lower, we are not sufficiently far from underflow to use an unguarded decrement.
    //
    // Likewise if the initial occupancy is close to the threshold, unguarded increment and decrement can cause similar problems.
    // However in the case of stall_out, valid_in=1 during reset will simply be masked by reset. Once stall_out deasserts, we
    // have to guard against decr_raw until valid_out asserts from initial occupancy, there is a gap of 4 clocks here (write to
    // read latency minus 1). If the initial occupancy is within 4 of the capacity (DEPTH), we must use decr_no_underflow instead.
    
    acl_tessellated_incr_decr_threshold #(
        .CAPACITY                   (DEPTH),
        .THRESHOLD                  (DEPTH),
        .INITIAL_OCCUPANCY          (INITIAL_OCCUPANCY),
        .THRESHOLD_REACHED_AT_RESET (1),
        .ASYNC_RESET                (ASYNC_RESET),
        .SYNCHRONIZE_RESET          (0),
        .RESET_EVERYTHING           (RESET_EVERYTHING),
        .RESET_EXTERNALLY_HELD      (1)
    )
    stall_out_inst
    (
        .clock                      (clock),
        .resetn                     (resetn_full),
        .incr_no_overflow           (valid_in & ~stall_out),
        .incr_raw                   (valid_in),
        .decr_no_underflow          (read_from_fifo),
        .decr_raw                   ((DEPTH<=5 || (DEPTH-INITIAL_OCCUPANCY)<=4) ? read_from_fifo : try_read_from_fifo),
        .threshold_reached          (stall_out)
    );
    
    
    
    ///////////////////
    //               //
    //  Almost full  //
    //               //
    ///////////////////
    
    generate
    if (ALMOST_FULL_CUTOFF_TEMP == 0) begin : full_almost_full  //FIXME: TEMPORARY WORKAROUND
        assign almost_full = stall_out;
    end
    else begin : real_almost_full
        localparam ALMOST_FULL_INIT_OCC_DIFF = ((DEPTH-ALMOST_FULL_CUTOFF_TEMP) > INITIAL_OCCUPANCY) ? (DEPTH-ALMOST_FULL_CUTOFF_TEMP-INITIAL_OCCUPANCY) : INITIAL_OCCUPANCY-(DEPTH-ALMOST_FULL_CUTOFF_TEMP);
        acl_tessellated_incr_decr_threshold #(
            .CAPACITY                   (DEPTH),
            .THRESHOLD                  (DEPTH - ALMOST_FULL_CUTOFF_TEMP),  //FIXME: TEMPORARY WORKAROUND
            .INITIAL_OCCUPANCY          (INITIAL_OCCUPANCY),
            .THRESHOLD_REACHED_AT_RESET (1),
            .ASYNC_RESET                (ASYNC_RESET),
            .SYNCHRONIZE_RESET          (0),
            .RESET_EVERYTHING           (RESET_EVERYTHING),
            .RESET_EXTERNALLY_HELD      (1)
        )
        almost_full_inst
        (
            .clock                      (clock),
            .resetn                     (resetn_almost_full),
            .incr_no_overflow           (valid_in & ~stall_out),
            .incr_raw                   (valid_in),
            .decr_no_underflow          (read_from_fifo),
            .decr_raw                   (((DEPTH-ALMOST_FULL_CUTOFF_TEMP)<=5 || ALMOST_FULL_INIT_OCC_DIFF<=4) ? read_from_fifo : try_read_from_fifo),    //same protection as for stall_out //FIXME: TEMPORARY WORKAROUND
            .threshold_reached          (almost_full)
        );
    end
    endgenerate
    
    
    
    ////////////////////
    //                //
    //  Almost empty  //
    //                //
    ////////////////////
    
    generate
    if (ALMOST_EMPTY_CUTOFF_TEMP == 0) begin : empty_almost_empty   //FIXME: TEMPORARY WORKAROUND
        assign almost_empty = ~valid_out;
    end
    else begin : real_almost_empty
        always_ff @(posedge clock or negedge aclrn) begin
            if (~aclrn) m20k_wren_delayed <= 3'h0;
            else begin
                m20k_wren_delayed <= {m20k_wren_delayed[1:0], m20k_wren_for_others};
                if (~sclrn_reset_everything) m20k_wren_delayed <= 3'h0;
            end
        end
        
        acl_tessellated_incr_decr_threshold #(
            .CAPACITY                   (DEPTH),
            .THRESHOLD                  (ALMOST_EMPTY_CUTOFF_TEMP + 1), //FIXME: TEMPORARY WORKAROUND
            .INITIAL_OCCUPANCY          (INITIAL_OCCUPANCY),
            .RESET_RELEASE_DELAY        (4),    //INITIAL_OCCUPANCY affects write-side occupancy, it takes 4 clocks (write to read latency minus 1) for this to propagate to read-side occupancy
            .THRESHOLD_REACHED_AT_RESET (0),
            .ASYNC_RESET                (ASYNC_RESET),
            .SYNCHRONIZE_RESET          (0),
            .RESET_EVERYTHING           (RESET_EVERYTHING),
            .RESET_EXTERNALLY_HELD      (1)
        )
        almost_empty_inst
        (
            .clock                      (clock),
            .resetn                     (resetn_almost_empty),
            .incr_no_overflow           (m20k_wren_delayed[2]),
            .incr_raw                   (m20k_wren_delayed[2]),
            .decr_no_underflow          (read_from_fifo),
            .decr_raw                   (try_read_from_fifo),
            .threshold_reached          (not_almost_empty)
        );
        
        assign almost_empty = ~not_almost_empty;
    end
    endgenerate
    
endmodule
//end acl_high_speed_fifo














module scfifo_to_acl_high_speed_fifo #(
    //parameters from scfifo that you CAN set
    parameter lpm_width,                        //YOU MUST SET THIS, data width
    parameter lpm_numwords,                     //YOU MUST SET THIS, unlike scfifo, this doesn't need to be a power of 2    
    parameter almost_empty_value = 1,           //almost_empty asserts if usedw < almost_empty_value
    parameter almost_full_value = 0,            //almost_full asserts if usedw >= almost_full_value
    parameter add_ram_output_register = "OFF",  //"ON" | "OFF" whether to register the output data, default of scfifo is unreg
    parameter lpm_showahead = "ON",             //"ON" | "OFF", on is how the fifo natively works, off requires an adapter which has an area penalty and potentially a fmax penalty
    parameter ram_block_type = "AUTO",          //"MLAB" | "M20K" | "AUTO" -> ram_block_type parameter of altera_syncram
    
    //parameters from scfifo that you CANNOT set, i.e. we ignore these
    //default values are set so that when you instantiate this, you don't have to override them
    parameter lpm_widthu = $clog2(lpm_width),   //width of usedw, we just look at lpm_numwords
    parameter enable_ecc = "FALSE", 
    parameter lpm_type = "scfifo",
    parameter overflow_checking = "ON",         //it is okay if you had set this to off, that just means you are already guarding against wrreq when full
    parameter underflow_checking = "ON",        //it is okay if you had set this to off, that just means you are already guarding against rdreq when empty
    parameter use_eab = "ON",                   //off means use logic elements only instead of ram
    parameter intended_device_family = "Stratix 10",
    
    //parameters that don't exist in scfifo but are exposed to introduce new functionality
    parameter INITIAL_OCCUPANCY = 0,            //number of words in the fifo (write side occupancy) when it comes out of reset, note it still takes 5 clocks for this to become visible on the read side
    parameter REGISTERED_DATA_OUT_COUNT = (add_ram_output_register=="ON") ? lpm_width : 0,  //ideally one registers the output bits used in control logic, unregister everything else, this reduces high-fan out of stall_in
    parameter HOLD_DATA_OUT_WHEN_EMPTY = 0,     //scfifo holds last value when empty, high speed fifo may show x when empty but can be made to behave like scfifo (set parameter to 1, this has an fmax penalty)
    parameter ASYNC_RESET = 1,                  //how do we use reset: 1 means registers are reset asynchronously, 0 means registers are reset synchronously
    parameter SYNCHRONIZE_RESET = 0,            //based on how reset gets to us, what do we need to do: 1 means synchronize reset before consumption (if reset arrives asynchronously), 0 means passthrough (managed externally)
    parameter RESET_EVERYTHING = 0,             //intended for partial reconfig debug, set to 1 to reset every register (normally async reset excludes data path and sync reset additionally excludes some control signals)
    parameter RESET_EXTERNALLY_HELD = 0         //set to 1 if resetn will be held for at least FIVE clock cycles, otherwise we will internally pulse stretch reset before consumption
) (
    input  wire                     clock,
    input  wire                     aclr,       //IMPORTANT: this is IGNORED if ASYNC_RESET = 0
    input  wire                     sclr,       //IMPORTANT: this is IGNORED unless you override ASYNC_RESET to 0 at instantiation
    input  wire     [lpm_width-1:0] data,
    output logic    [lpm_width-1:0] q,
    input  wire                     wrreq,
    output logic                    empty,
    input  wire                     rdreq,
    output logic                    full,
    output logic                    almost_empty,
    output logic                    almost_full,
    output logic   [lpm_widthu-1:0] usedw       //WARNING: this signal is NOT connected
);
    
    logic internal_resetn, internal_aclrn, internal_sclrn;
    logic valid_out, stall_in;
    logic [lpm_width-1:0] q_reg, q_unreg, data_out, data_out_prev, data_out_late;
    logic data_out_clock_en;
    assign empty = ~valid_out;
    assign stall_in = ~rdreq;
    assign usedw = 'x;
    
    generate
    if (ASYNC_RESET) begin
        assign internal_resetn = ~aclr;
        assign internal_aclrn = ~aclr;
        assign internal_sclrn = 1'b1;
    end
    else begin
        assign internal_resetn = ~sclr;
        assign internal_aclrn = 1'b1;
        assign internal_sclrn = ~sclr;
    end
    endgenerate
    
    acl_high_speed_fifo
    #(
        //basic fifo configuration
        .WIDTH                          (lpm_width),
        .DEPTH                          (lpm_numwords),
        .ALMOST_EMPTY_CUTOFF            (almost_empty_value - 1),
        .ALMOST_FULL_CUTOFF             (lpm_numwords - almost_full_value),
        .INITIAL_OCCUPANCY              (INITIAL_OCCUPANCY),
        
        //reset configuration
        .ASYNC_RESET                    (ASYNC_RESET),
        .SYNCHRONIZE_RESET              (SYNCHRONIZE_RESET),
        .RESET_EVERYTHING               (RESET_EVERYTHING),
        .RESET_EXTERNALLY_HELD          (RESET_EXTERNALLY_HELD),
        
        //special configurations for higher fmax / lower area
        .STALL_IN_EARLINESS             (0),
        .REGISTERED_DATA_OUT_COUNT      (REGISTERED_DATA_OUT_COUNT),
        
        //conformance with scfifo
        .HOLD_DATA_OUT_WHEN_EMPTY       (HOLD_DATA_OUT_WHEN_EMPTY),
        
        //ram settings
        .RAM_BLOCK_TYPE                 (ram_block_type)
    )
    acl_high_speed_fifo_inst
    (
        .clock                          (clock),
        .resetn                         (internal_resetn),
        .data_in                        (data),
        .data_out                       (data_out),
        .valid_in                       (wrreq),
        .valid_out                      (valid_out),
        .stall_in                       (stall_in),
        .stall_out                      (full),
        .almost_empty                   (almost_empty),
        .almost_full                    (almost_full)
    );
    
    //adapter for converting from showahead on (native fifo) to showahead off (for usage of instances of scfifo with this)
    genvar g;
    generate
    if (lpm_showahead == "OFF") begin
        always_ff @(posedge clock or negedge internal_aclrn) begin
            if (~internal_aclrn) begin
                data_out_clock_en <= 1'b0;
                q_reg <= '0;                //normally data path should not need to be reset, this is to conform with scfifo behavior that before the first write, the read data is 0
                data_out_prev <= '0;
                data_out_late <= '0;
            end
            else begin
                data_out_clock_en <= valid_out & rdreq;                         //register first to reduce high fan-out severity
                if (valid_out & rdreq) q_reg <= data_out;
                data_out_prev <= data_out;
                if (data_out_clock_en) data_out_late <= data_out_prev;          //this loads one clock cycle late
                if (~internal_sclrn) begin
                    data_out_clock_en <= 1'b0;
                    q_reg <= '0;
                    data_out_prev <= '0;
                    data_out_late <= '0;
                end
            end
        end
        assign q_unreg = (data_out_clock_en) ? data_out_prev : data_out_late;   //resolve what was supposed to load after the fact
        
        //select whether to use registered or unregistered q
        if (REGISTERED_DATA_OUT_COUNT == 0) begin : gen_registered_q
            assign q = q_unreg;
        end
        else if (REGISTERED_DATA_OUT_COUNT == lpm_width) begin : gen_unregistered_q
            assign q = q_reg;
        end
        else begin : gen_mixed_reg_q
            assign q = {q_unreg[lpm_width-1:REGISTERED_DATA_OUT_COUNT], q_reg[REGISTERED_DATA_OUT_COUNT-1:0]};
        end
    end
    else begin  //lpm_showahead == "ON"
        assign q = data_out;
    end
    endgenerate
    
endmodule
//end scfifo_to_acl_high_speed_fifo

`default_nettype wire
