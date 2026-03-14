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


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                                                                          //
//  ACL LOW LATENCY FIFO                                                                                                                    //
//  Designed and optimized by: Jason Thong                                                                                                  //
//                                                                                                                                          //
//  DESCRIPTION                                                                                                                             //
//  ===========                                                                                                                             //
//  This fifo is fmax optimized for Stratix 10 at the expense of area. This fifo uses registers as storage and therefore it is not          //
//  recommended for large DEPTH. The low latency designation means that every input affects the output within 1 clock cycle, e.g. the       //
//  write-to-read latency is 1 clock. Stall/valid semantics are used, where upstream indicates availability through valid and downstream    //
//  applies backpressure through stall. A write into the fifo occurs when valid_in==1 && stall_out==0. A read from the fifo occurs when     //
//  valid_out==1 && stall_in==0.                                                                                                            //
//                                                                                                                                          //
//  REQUIRED FILES                                                                                                                          //
//  ==============                                                                                                                          //
//  - acl_low_latency_fifo.sv                                                                                                               //
//  - acl_reset_handler.sv                                                                                                                  //
//  - acl_fanout_pipeline.sv                                                                                                                //
//  - acl_std_synchronizer_nocut.v                                                                                                          //
//                                                                                                                                          //
//  RESET BEHAVIOR                                                                                                                          //
//  ==============                                                                                                                          //
//  During reset the fifo appears as both full and empty. One can interact with the fifo once full deasserts. The almost_full signal also   //
//  follows the same behavior as full for reset. See acl_high_speed_fifo.sv for typical values that the reset parameters should have for    //
//  various platforms.                                                                                                                      //
//                                                                                                                                          //
//  ALMOST FULL AND ALMOST EMPTY                                                                                                            //
//  ============================                                                                                                            //
//  The ALMOST_***_CUTOFF parameters refer to how much dead space would be in the fifo if one were to use almost_full as same clock cycle   //
//  backpressure (dead space in not being able to completely fill the fifo), or if one were to almost_empty as same clock cycle underflow   //
//  prevention (dead space in not being able to empty the fifo). See chart below for interpretation of values:                              //
//                                                                                                                                          //
//  Scfifo parameter                    | Our parameter             | Interpretation                                                        //
//  ------------------------------------+---------------------------+---------------------------------------------------------------        //
//  almost_empty_value = 1              | ALMOST_EMPTY_CUTOFF = 0   | almost_empty behaves the same way as empty                            //
//  almost_empty_value = 2              | ALMOST_EMPTY_CUTOFF = 1   | almost_empty asserts when read_used_words is 1 or less                //
//  ------------------------------------+---------------------------+---------------------------------------------------------------        //
//  almost_full_value = lpm_numwords    | ALMOST_FULL_CUTOFF = 0    | almost_full behaves the same way as full                              //
//  almost_full_value = lpm_numwords-1  | ALMOST_FULL_CUTOFF = 1    | almost_full asserts when write_used_words is DEPTH-1 or higher        //
//                                                                                                                                          //
//  INITIAL OCCUPANCY                                                                                                                       //
//  =================                                                                                                                       //
//  The parameter INITIAL_OCCUPANCY describes the number of words of garbage data in the fifo as it exits from reset. Typically this is 0,  //
//  e.g. we have to write into the fifo  before anything is readable. If INITIAL_OCCUPANCY > 0, then valid_out is 0 during reset, and when  //
//  it eventually asserts it is then safe for downstream to transact reads from the fifo. Exit from reset should be handled separately for  //
//  upstream and downstream. In particular, the assertion of valid_out (to downstream) and the deassertion of stall_out (to upstream) may   //
//  not happen on the same clock cycle. If INITIAL_OCCUPANCY == DEPTH, one cannot use stall_out to observe reset exit, only when at least   //
//  one item has been read from the fifo will stall_out then deasert.                                                                       //
//                                                                                                                                          //
//  VALID_AND_STALL_IN_EARLINESS                                                                                                            //
//  ============================                                                                                                            //
//  This is an fmax optimization. If valid_in and stall_in are known one clock cycle ahead of time, we compute occupancy one clock early.   //
//  This gives an extra clock cycle from the control logic (occupancy, clock enables, mux selects) to the data path logic, which helps      //
//  mitigate fmax degradation due to high fan-out (large WIDTH). Only values 0 and 1 are supported since the biggest fmax gain comes from   //
//  registering the control logic before consumption. Any excess earliness is absorbed by hld_fifo, we leave it to Quartus to retime it.    //
//                                                                                                                                          //
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

`timescale 1ps/1ps
`default_nettype none

module acl_low_latency_fifo #(
    //basic fifo configuration
    parameter int WIDTH,                        // width of the data path through the fifo
    parameter int DEPTH,                        // capacity of the fifo
    
    //almost empty and almost full configuration
    parameter int ALMOST_EMPTY_CUTOFF = 0,      // almost_empty asserts if read_used_words <= ALMOST_EMPTY_CUTOFF, read_used_words increments when writes are visible on the read side, decrements when fifo is read
    parameter int ALMOST_FULL_CUTOFF = 0,       // almost_full asserts if write_used_words >= (DEPTH-ALMOST_FULL_CUTOFF), write_used_words increments when fifo is written to, decrements when fifo is read
    
    //initial occupancy
    parameter int INITIAL_OCCUPANCY = 0,        // number of words in the fifo when it comes out of reset
    
    //reset configuration
    parameter bit ASYNC_RESET = 1,              // how do we use reset: 1 means registers are reset asynchronously, 0 means registers are reset synchronously
    parameter bit SYNCHRONIZE_RESET = 0,        // based on how reset gets to us, what do we need to do: 1 means synchronize reset before consumption (if reset arrives asynchronously), 0 means passthrough (managed externally)
    parameter bit RESET_EVERYTHING = 0,         // intended for partial reconfig debug, set to 1 to reset every register (normally async reset excludes data path and sync reset additionally excludes some control signals)
    //RESET_EXTERNALLY_HELD not needed since reset pulse stretcher is not needed
    
    //special configurations for higher fmax / lower area
    parameter int VALID_AND_STALL_IN_EARLINESS = 0, // 0 or 1, how many clock cycles early is valid_in and stall_in provided, this is an fmax optimization
    parameter int REGISTERED_DATA_OUT_COUNT = 0,// 0 to WIDTH inclusive, data_out[REGISTERED_DATA_OUT_COUNT-1:0] are registered, the remaining upper bits are unregistered
                                                // generally REGISTERED_DATA_OUT_COUNT should be 0 unless fifo output data drives control logic, in which just those bits should be registered
                                                // this parameter is ignored if DEPTH == 1 in which case data_out is always registered
    //conformance with scfifo
    parameter bit HOLD_DATA_OUT_WHEN_EMPTY = 0  // 0 means data_out can be x when fifo is empty, 1 means data_out will hold last value when fifo is empty (scfifo behavior, has fmax penalty)
)
(
    input  wire                 clock,
    input  wire                 resetn,         // see description above for different reset modes
    input  wire     [WIDTH-1:0] data_in,        // data from upstream
    output logic    [WIDTH-1:0] data_out,       // data to downstream
    input  wire                 valid_in,       // upstream advertises it has data, a write happens when valid_in & ~stall_out
    output logic                valid_out,      // advertise to downstream that we have data
    input  wire                 stall_in,       // downstream indicates it cannot accept data
    output logic                stall_out,      // inform upstream that we cannot accept data
    output logic                almost_empty,   // asserts if read_used_words <= ALMOST_EMPTY_CUTOFF
    output logic                almost_full,    // asserts if write_used_words >= (DEPTH-ALMOST_FULL_CUTOFF)
    output logic    [DEPTH-1:0] occ,            // expose occupancy tracking to the outside world, useful if one wants multiple thresholds e.g. in acl_zero_latency_fifo
    output logic    [DEPTH-1:0] occ_low_reset,  // expose occupancy tracking, this version is needed for VALID_IN_EARLINESS
    output logic    [DEPTH-1:0] occ_high_reset  // expose occupancy tracking, this version is needed for VALID_IN_EARLINESS
);
    
    
    ///////////////////////////
    //                       //
    //  Signal declarations  //
    //                       //
    ///////////////////////////
    
    logic             aclrn, sclrn, sclrn_reset_everything; //reset
    logic [DEPTH-1:0] occ_next;                             //occupancy tracking
    logic [WIDTH-1:0] data [DEPTH+1:0];                     //storage in registers, only need up to index DEPTH but over-allocate just so that data[2] isn't out of bounds
    logic [DEPTH-2:0] data_clock_en, data_clock_en_pre;     //clock enables for storage in registers
    logic [DEPTH-2:0] data_sel, data_sel_pre;
    logic             data_out_clock_en, data_out_clock_en_pre;             //control signals for output data
    logic             data_out_unreg_select, data_out_unreg_select_pre;
    logic             data_clock_en_0_hold, data_clock_en_0_hold_pre;
    logic             data_out_reg_sel_pri, data_out_reg_sel_pri_pre;
    logic             data_out_reg_sel_sec, data_out_reg_sel_sec_pre;
    logic             stall_in_prev;
    logic [WIDTH-1:0] data_out_reg, data_out_unreg;         //output data
    
    
    
    /////////////
    //         //
    //  Reset  //
    //         //
    /////////////
    
    // S10 reset specification:
    // S (clocks to enter reset "safe state"): 5 (3 for synchronizer, 2 for sclrn pipeline)
    // P (minimum duration of reset pulse):    1 (no pulse stretcher is needed)
    // D (clocks to exit reset "safe state"):  5 + VALID_AND_STALL_IN_EARLINESS (5 or 6, we need an extra clock if the previous value of valid_in needs to be flushed)
    
    acl_reset_handler
    #(
        .ASYNC_RESET            (ASYNC_RESET),
        .USE_SYNCHRONIZER       (SYNCHRONIZE_RESET),
        .SYNCHRONIZE_ACLRN      (SYNCHRONIZE_RESET),
        .PIPE_DEPTH             (2),
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
    assign sclrn_reset_everything = (RESET_EVERYTHING) ? sclrn : 1'b1;
    
    
    // guard occ against valid_in=1 and stall_in=0 during reset
    // this is needed if upstream or downstream of the fifo comes out of reset before the fifo and wants to transact as soon as possible (observed by stall_out deasserting or valid_out asserting respectively)
    // for example, suppose DEPTH=5 and INITIAL_OCCUPANCY==2, occ will reset to 5'b00011, so we only need to guard occ[1] loading 0 from occ[2], and guard occ[2] loading 1 from occ[1]
    // see table below for how the values occ of relate to the actual occupancy, there is at most one transition between 0 and 1 and this is where the reset protection is needed
    // resetn_master_mask deals with timing, and we distribute this to only the two indexes that need to be protected during reset
    logic resetn_master_mask;
    logic [DEPTH-1:0] resetn_mask;
    always_ff @(posedge clock or negedge aclrn) begin
        if (~aclrn) begin
            resetn_master_mask <= 1'b0;
        end
        else begin
            resetn_master_mask <= 1'b1;
            if (~sclrn) resetn_master_mask <= 1'b0;
        end
    end
    always_comb begin
        for (int i=0; i<DEPTH; i++) begin
            resetn_mask[i] = (i==INITIAL_OCCUPANCY || (i+1)==INITIAL_OCCUPANCY) ? resetn_master_mask : 1'b1;
        end
    end
    
    
    //////////////////////////
    //                      //
    //  Occupancy tracking  //
    //                      //
    //////////////////////////
    
    // occ[i] means that the occupancy is greater than i, e.g. occ[0] means there is 1 or more items
    // occ is retimed early like valid_in and stall_in when VALID_AND_STALL_IN_EARLINESS > 0
    //
    // The following table lists all the values that occ can take when DEPTH = 4
    //
    // value of occ     | actual occupancy
    // -----------------+-----------------
    // 4'b0000          | 0
    // 4'b0001          | 1
    // 4'b0011          | 2
    // 4'b0111          | 3
    // 4'b1111          | 4
    
    generate
    if (DEPTH == 1) begin : gen_depth_1_occ
        assign occ_next[0] = (valid_in & ~occ[0] & resetn_master_mask) ? 1'b1 : (occ[0] & ~stall_in & resetn_master_mask) ? 1'b0 : occ[0];
    end
    else begin : gen_depth_n_occ
        always_comb begin
            occ_next[0] = (valid_in & resetn_mask[0]) ? 1'b1 : (~stall_in & resetn_mask[0]) ? occ[1] : occ[0];
            for (int i=1; i<DEPTH-1; i++) begin   //middle registers have no boundary effect, used when DEPTH >= 3
                occ_next[i] = (valid_in & stall_in & resetn_mask[i]) ? occ[i-1] : (~valid_in & ~stall_in & resetn_mask[i]) ? occ[i+1] : occ[i];
            end
            occ_next[DEPTH-1] = (~stall_in & resetn_mask[DEPTH-1]) ? 1'b0 : (valid_in & resetn_mask[DEPTH-1]) ? occ[DEPTH-2] : occ[DEPTH-1];
        end
    end
    endgenerate
    
    //most of occ_low_reset and occ_high_reset will get trimmed away by Quartus, we need this to apply backpressure to upstream during reset (stall_out and almost_full)
    always_ff @(posedge clock or negedge aclrn) begin
        if (~aclrn) begin
            for (int i=0; i<DEPTH; i++) occ[i] <= (i >= INITIAL_OCCUPANCY) ? 1'b0 : 1'b1;
            occ_low_reset <= '0;
            occ_high_reset <= '1;
        end
        else begin
            occ <= occ_next;
            occ_low_reset <= occ_next;
            occ_high_reset <= occ_next;
            if (~sclrn) begin
                for (int i=0; i<DEPTH; i++) occ[i] <= (i >= INITIAL_OCCUPANCY) ? 1'b0 : 1'b1;
                occ_low_reset <= '0;
                occ_high_reset <= '1;
            end
        end
    end
    
    
    generate
    if (VALID_AND_STALL_IN_EARLINESS == 1) begin
        always_ff @(posedge clock or negedge aclrn) begin
            if (~aclrn) begin
                valid_out <= 1'b0;
                stall_out <= 1'b1;
                almost_empty <= 1'b1;
                almost_full <= 1'b1;
            end
            else begin
                valid_out <= occ_low_reset[0];
                stall_out <= occ_high_reset[DEPTH-1];
                almost_empty <= (ALMOST_EMPTY_CUTOFF >= DEPTH) ? 1'b1 : (ALMOST_EMPTY_CUTOFF < 0) ? 1'b0 : ~occ_low_reset[ALMOST_EMPTY_CUTOFF];
                almost_full <= (ALMOST_FULL_CUTOFF >= DEPTH) ? 1'b1 : (ALMOST_FULL_CUTOFF < 0) ? 1'b0 : occ_high_reset[DEPTH-ALMOST_FULL_CUTOFF-1];
                if (~sclrn) begin
                    valid_out <= 1'b0;
                    stall_out <= 1'b1;
                    almost_empty <= 1'b1;
                    almost_full <= 1'b1;
                end
            end
        end
    end
    else begin  //VALID_AND_STALL_IN_EARLINESS == 0
        assign valid_out = occ_low_reset[0];
        assign stall_out = occ_high_reset[DEPTH-1];
        assign almost_empty = (ALMOST_EMPTY_CUTOFF >= DEPTH) ? 1'b1 : (ALMOST_EMPTY_CUTOFF < 0) ? 1'b0 : ~occ_low_reset[ALMOST_EMPTY_CUTOFF];
        assign almost_full = (ALMOST_FULL_CUTOFF >= DEPTH) ? 1'b1 : (ALMOST_FULL_CUTOFF < 0) ? 1'b0 : occ_high_reset[DEPTH-ALMOST_FULL_CUTOFF-1];
    end
    endgenerate
    
    
    
    ///////////////////
    //               //
    //  Output data  //
    //               //
    ///////////////////
    
    //the ****_pre signals are retimed earlier just like valid_in, stall_in, and occ when VALID_AND_STALL_IN_EARLINESS > 0
    generate
    if (DEPTH == 1) begin : gen_depth_1_data_out
        assign data_out_clock_en_pre = (!HOLD_DATA_OUT_WHEN_EMPTY) ? (~occ[0]) : (~occ[0] & valid_in);
        if (VALID_AND_STALL_IN_EARLINESS == 1) begin
            always_ff @(posedge clock or negedge aclrn) begin
                if (~aclrn) begin
                    data_out_clock_en <= 1'b0;
                end
                else begin
                    data_out_clock_en <= data_out_clock_en_pre;
                    if (~sclrn_reset_everything) data_out_clock_en <= 1'b0;
                end
            end
        end
        else begin
            assign data_out_clock_en = data_out_clock_en_pre;
        end
        
        always_ff @(posedge clock or negedge aclrn) begin
            if (~aclrn) begin
                data_out <= (RESET_EVERYTHING) ? '0 : 'x;
            end
            else begin
                if (data_out_clock_en) data_out <= data_in;
                if (~sclrn_reset_everything) data_out <= '0;
            end
        end
    end
    else begin : gen_depth_n_data_out
        assign data_out_clock_en_pre = (!HOLD_DATA_OUT_WHEN_EMPTY) ? (~stall_in | ~occ[0]) : ((~stall_in & (occ[1] | valid_in)) | (~occ[0] & valid_in));
        assign data_out_unreg_select_pre = (!HOLD_DATA_OUT_WHEN_EMPTY) ? (~stall_in_prev) : (~stall_in_prev & occ[0]);
        assign data_clock_en_0_hold_pre = (!HOLD_DATA_OUT_WHEN_EMPTY) ? 1'b1 : (valid_in | occ[0]);
        assign data_out_reg_sel_pri_pre = ~occ[1];
        assign data_out_reg_sel_sec_pre = ~stall_in_prev;
        
        if (VALID_AND_STALL_IN_EARLINESS == 1) begin
            always_ff @(posedge clock or negedge aclrn) begin
                if (~aclrn) begin
                    data_out_clock_en <= 1'b0;
                    data_out_unreg_select <= 1'b0;
                    data_clock_en_0_hold <= 1'b0;
                    data_out_reg_sel_pri <= 1'b0;
                    data_out_reg_sel_sec <= 1'b0;
                end
                else begin
                    data_out_clock_en <= data_out_clock_en_pre;
                    data_out_unreg_select <= data_out_unreg_select_pre;
                    data_clock_en_0_hold <= data_clock_en_0_hold_pre;
                    data_out_reg_sel_pri <= data_out_reg_sel_pri_pre;
                    data_out_reg_sel_sec <= data_out_reg_sel_sec_pre;
                    if (~sclrn_reset_everything) begin
                        data_out_clock_en <= 1'b0;
                        data_out_unreg_select <= 1'b0;
                        data_clock_en_0_hold <= 1'b0;
                        data_out_reg_sel_pri <= 1'b0;
                        data_out_reg_sel_sec <= 1'b0;
                    end
                end
            end
        end
        else begin
            assign data_out_clock_en = data_out_clock_en_pre;
            assign data_out_unreg_select = data_out_unreg_select_pre;
            assign data_clock_en_0_hold = data_clock_en_0_hold_pre;
            assign data_out_reg_sel_pri = data_out_reg_sel_pri_pre;
            assign data_out_reg_sel_sec = data_out_reg_sel_sec_pre;
        end
        
        //generate both registered and unregistered versions, select which one to use (for each bit of data_out, the unused one will be pruned away)
        always_ff @(posedge clock or negedge aclrn) begin
            if (~aclrn) begin
                data_out_reg <= (RESET_EVERYTHING) ? '0 : 'x;
            end
            else begin
                if (data_out_clock_en) data_out_reg <= (data_out_reg_sel_pri) ? data_in : (data_out_reg_sel_sec) ? data[2] : data[1];
                if (~sclrn_reset_everything) data_out_reg <= '0;
            end
        end
        
        assign data_out_unreg = (data_out_unreg_select) ? data[1] : data[0];
        
        if (REGISTERED_DATA_OUT_COUNT == 0) begin : gen_registered_data_out
            assign data_out = data_out_unreg;
        end
        else if (REGISTERED_DATA_OUT_COUNT == WIDTH) begin : gen_unregistered_data_out
            assign data_out = data_out_reg;
        end
        else begin : gen_mixed_reg_data_out
            assign data_out = {data_out_unreg[WIDTH-1:REGISTERED_DATA_OUT_COUNT], data_out_reg[REGISTERED_DATA_OUT_COUNT-1:0]};
        end
    end
    endgenerate
    
    
    
    /////////////////////////////////
    //                             //
    //  Data storage in registers  //
    //                             //
    /////////////////////////////////
    
    //except for data_out the rest of the data path loads 1 clock late
    //data_out_reg can use data[2] if it hasn't yet loaded into data[1]
    //data_out_unreg means we can load everything late and then figure out after-the-fact what should have been loaded into the output data register
    generate
    if (DEPTH >= 2) begin : gen_depth_n_data_storage
        //mux selects
        assign data_sel_pre = ~occ;
        
        //clock enables
        always_ff @(posedge clock or negedge aclrn) begin
            if (~aclrn) begin
                stall_in_prev <= (RESET_EVERYTHING) ? 1'b0 : 1'bx;
                data_clock_en_pre <= (RESET_EVERYTHING) ? '0 : 'x;
            end
            else begin
                stall_in_prev <= stall_in;
                for (int i=0; i<DEPTH-1; i++) begin
                    data_clock_en_pre[i] <= ~stall_in | ~occ[i];
                end
                if (~sclrn_reset_everything) begin
                    stall_in_prev <= 1'b0;
                    data_clock_en_pre <= '0;
                end
            end
        end
        
        //retime the mux selects and clock enables
        if (VALID_AND_STALL_IN_EARLINESS == 1) begin
            always_ff @(posedge clock or negedge aclrn) begin
                if (~aclrn) begin
                    data_sel <= (RESET_EVERYTHING) ? '0 : 'x;
                    data_clock_en <= (RESET_EVERYTHING) ? '0 : 'x;
                end
                else begin
                    data_sel <= data_sel_pre;
                    data_clock_en <= data_clock_en_pre;
                    if (~sclrn_reset_everything) begin
                        data_sel <= '0;
                        data_clock_en <= '0;
                    end
                end
            end
        end
        else begin
            assign data_sel = data_sel_pre;
            assign data_clock_en = data_clock_en_pre;
        end
        
        //data path
        always_ff @(posedge clock or negedge aclrn) begin
            if (~aclrn) begin
                for (int i=0; i<DEPTH; i++) data[i] <= (RESET_EVERYTHING) ? '0 : 'x;
            end
            else begin
                //data_clock_en_0_hold is used to hold data[0] when HOLD_DATA_OUT_WHEN_EMPTY=1
                if (data_clock_en[0] & data_clock_en_0_hold) data[0] <= (data_sel[0]) ? data_in : data[1];
                
                //general case
                for (int i=1; i<DEPTH-1; i++) begin
                    if (data_clock_en[i]) data[i] <= (data_sel[i]) ? data_in : data[i+1];
                end
                
                //last data storage register only loads when not full
                if (~stall_out) data[DEPTH-1] <= data_in;
                
                if (~sclrn_reset_everything) begin
                    for (int i=0; i<DEPTH; i++) data[i] <= '0;
                end
            end
        end
    end
    endgenerate
    
endmodule

`default_nettype wire
