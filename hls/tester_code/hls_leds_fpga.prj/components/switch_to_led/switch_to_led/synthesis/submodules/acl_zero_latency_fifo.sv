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
//  ACL ZERO LATENCY FIFO                                                                                                                   //
//  Designed and optimized by: Jason Thong                                                                                                  //
//                                                                                                                                          //
//  DESCRIPTION                                                                                                                             //
//  ===========                                                                                                                             //
//  This fifo has a write to read latency of zero clock cycles. On the same clock cycle that data is written, it is also readable. This is  //
//  achieved by adding a data bypass using combinational logic. This is built on top of acl_low_latency_fifo, which is a fifo with write    //
//  to read latency of 1. The zero latency fifo has a very large fmax penalty due to the combinational logic between inputs and outputs.    //
//                                                                                                                                          //
//  REQUIRED FILES                                                                                                                          //
//  ==============                                                                                                                          //
//  - acl_zero_latency_fifo.sv                                                                                                              //
//  - acl_low_latency_fifo.sv                                                                                                               //
//  - acl_reset_handler.sv                                                                                                                  //
//  - acl_fanout_pipeline.sv                                                                                                                //
//  - acl_std_synchronizer_nocut.v                                                                                                          //
//                                                                                                                                          //
//  INTERPRETATION OF ZERO LATENCY                                                                                                          //
//  ==============================                                                                                                          //
//  Zero write to read latency can be a tricky concept. Typically in a fifo there are two occupancy trackers:                               //
//                                                                                                                                          //
//  1. write_used_words:                                                                                                                    //
//       - tracks how many words have been written into the fifo                                                                            //
//       - increments one clock after write (on the next clock edge when write is asserted), decrements one clock after read ack            //
//       - stall_out (fifo is full) and almost_full are based on this value                                                                 //
//  2. read_used_words:                                                                                                                     //
//       - tracks how many words are readable from the fifo                                                                                 //
//       - increments WRITE_TO_READ_LATENCY clocks after write, decrements one clock after read ack                                         //
//       - valid_out (fifo is not empty) and almost_empty are based on this value                                                           //
//                                                                                                                                          //
//  In a high latency fifo e.g. acl_high_speed_fifo with WRITE_TO_READ_LATENCY = 5, write_used_words increments before read_used_words.     //
//  The interpretation is that something written into the fifo takes some time before that item is readable. In acl_low_latency_fifo        //
//  we have WRITE_TO_READ_LATENCY = 1, so write_used_words has the same timing as read_used_words. In acl_zero_latency_fifo, notice that    //
//  read_used_words increments BEFORE write_used_words. It may sound like something is readable before it has been written to the fifo,     //
//  but the interpretation here is that data can bypass the storage associated with a fifo e.g. data does not need to be written to a       //
//  register or a memory in order to be readable.                                                                                           //
//                                                                                                                                          //
//  RESET BEHAVIOR                                                                                                                          //
//  ==============                                                                                                                          //
//  The fifo asserts full (stall_out) and empty (~valid_out) during reset. Refer to acl_high_speed_fifo.sv for full details.                //
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

module acl_zero_latency_fifo #(
    //parameters are mostly passed directly into acl_low_latency_fifo, see that module for detailed descriptions
    parameter int WIDTH,
    parameter int DEPTH,
    parameter int ALMOST_EMPTY_CUTOFF = 0,          // almost_empty asserts if read_used_words <= ALMOST_EMPTY_CUTOFF, note that read_used_words changes before write_used_words at zero write to read latency
    parameter int ALMOST_FULL_CUTOFF = 0,
    parameter int INITIAL_OCCUPANCY = 0,            // number of words in the fifo when it comes out of reset
    parameter bit ASYNC_RESET = 1,
    parameter bit SYNCHRONIZE_RESET = 0,
    parameter bit RESET_EVERYTHING = 0,
    parameter int REGISTERED_DATA_OUT_COUNT = 0,    // this affects fifo_data_out (the data_out inside acl_low_latency_fifo), not the output of acl_zero_latency_fifo which can never be registered due to the bypass
    parameter bit HOLD_DATA_OUT_WHEN_EMPTY = 0,     // 0 means data_out can be x when fifo is empty, 1 means data_out will hold last value when fifo is empty (scfifo behavior, has fmax penalty and area penalty)
    parameter int VALID_AND_STALL_IN_EARLINESS = 0  // 0 or 1, how many clock cycles early is valid_in and stall_in provided, this is an fmax optimization
)
(
    input  wire                 clock,
    input  wire                 resetn,
    input  wire     [WIDTH-1:0] data_in,
    output logic    [WIDTH-1:0] data_out,
    input  wire                 valid_in,
    output logic                valid_out,
    input  wire                 stall_in,
    output logic                stall_out,
    output logic                almost_empty,
    output logic                almost_full
);
    
    logic fifo_valid_in, fifo_valid_out;
    logic [WIDTH-1:0] fifo_data_out;
    logic [DEPTH-1:0] occ_low_reset, occ_high_reset;
    logic fifo_almost_empty, fifo_almost_empty2;
    logic almost_empty_pre, valid_out_pre;
    
    //reset behavior must match acl_low_latency_fifo
    logic aclrn, sclrn;
    acl_reset_handler
    #(
        .ASYNC_RESET                    (ASYNC_RESET),
        .USE_SYNCHRONIZER               (SYNCHRONIZE_RESET),
        .SYNCHRONIZE_ACLRN              (SYNCHRONIZE_RESET),
        .PIPE_DEPTH                     (2),
        .NUM_COPIES                     (1)
    )
    acl_reset_handler_inst
    (
        .clk                            (clock),
        .i_resetn                       (resetn),
        .o_aclrn                        (aclrn),
        .o_resetn_synchronized          (),
        .o_sclrn                        (sclrn)
    );
    
    
    
    //occ_***_reset and the ****_pre signals are retimed early like valid_in and stall_in when VALID_AND_STALL_IN_EARLINESS > 0
    
    acl_low_latency_fifo
    #(
        .WIDTH                          (WIDTH),
        .DEPTH                          (DEPTH),
        //ALMOST_EMPTY_CUTOFF is managed externally
        .ALMOST_FULL_CUTOFF             (ALMOST_FULL_CUTOFF),
        .ASYNC_RESET                    (ASYNC_RESET),
        .SYNCHRONIZE_RESET              (SYNCHRONIZE_RESET),
        .RESET_EVERYTHING               (RESET_EVERYTHING),
        .REGISTERED_DATA_OUT_COUNT      (REGISTERED_DATA_OUT_COUNT),
        .HOLD_DATA_OUT_WHEN_EMPTY       (0),
        .VALID_AND_STALL_IN_EARLINESS   (VALID_AND_STALL_IN_EARLINESS),
        .INITIAL_OCCUPANCY              (INITIAL_OCCUPANCY)
    )
    ll_fifo_inst
    (
        .clock                          (clock),
        .resetn                         (resetn),
        .data_in                        (data_in),
        .data_out                       (fifo_data_out),
        .valid_in                       (fifo_valid_in),
        .valid_out                      (fifo_valid_out),
        .stall_in                       (stall_in),
        .stall_out                      (stall_out),
        .almost_empty                   (),             //managed externally
        .almost_full                    (almost_full),
        .occ_low_reset                  (occ_low_reset),
        .occ_high_reset                 (occ_high_reset)
    );
    
    //write into the fifo if the zero latency bypass is not used
    assign fifo_valid_in = valid_in & (stall_in | occ_low_reset[0]);
    
    //occ tracks write_used_words, convert to read_used_words by incrementing if writing to fifo (write can bypass storage)
    //stall_out gates valid_in when the fifo is full and also during reset (during which the fifo advertises that it is full)
    assign fifo_almost_empty = (ALMOST_EMPTY_CUTOFF >= DEPTH) ? 1'b1 : (ALMOST_EMPTY_CUTOFF < 0) ? 1'b0 : ~occ_low_reset[ALMOST_EMPTY_CUTOFF];
    assign fifo_almost_empty2 = ((ALMOST_EMPTY_CUTOFF-1) >= DEPTH) ? 1'b1 : ((ALMOST_EMPTY_CUTOFF-1) < 0) ? 1'b0 : ~occ_low_reset[ALMOST_EMPTY_CUTOFF-1];
    assign almost_empty_pre = (valid_in & ~occ_high_reset[DEPTH-1]) ? fifo_almost_empty2 : fifo_almost_empty;
    
    //same conversion of write_used_words to read_used_words
    //valid_out = (read_used_words != 0), and that can only happen if there is an incoming write or if write_used_words != 0
    assign valid_out_pre = (valid_in & ~occ_high_reset[DEPTH-1]) | occ_low_reset[0];
    
    //retime almost_empty and valid_out
    generate
    if (VALID_AND_STALL_IN_EARLINESS == 1) begin
        always_ff @(posedge clock or negedge aclrn) begin
            if (~aclrn) begin
                almost_empty <= 1'b1;
                valid_out <= 1'b0;
            end
            else begin
                almost_empty <= almost_empty_pre;
                valid_out <= valid_out_pre;
                if (~sclrn) begin
                    almost_empty <= 1'b1;
                    valid_out <= 1'b0;
                end
            end
        end
    end
    else begin  //VALID_AND_STALL_IN_EARLINESS == 0
        assign almost_empty = almost_empty_pre;
        assign valid_out = valid_out_pre;
    end
    endgenerate
    
    
    //output data, take it from the low latency fifo if it has data (this keeps stuff in order), otherwise the fifo is empty so use the data bypass
    //when holding the output data, the HOLD_DATA_OUT_WHEN_EMPTY parameter to the low latency fifo does not work when data is read directly from the bypass
    //because in this case it never got written into the low latency fifo (and writing it causes lots of complications)
    generate
    if (!HOLD_DATA_OUT_WHEN_EMPTY) begin
        assign data_out = (fifo_valid_out) ? fifo_data_out : data_in;
    end
    else begin
        logic data_sel_pri_pre, data_sel_sec_pre, data_sel_pri, data_sel_sec;
        logic captured_data_clock_en_pre, captured_data_clock_en;
        logic [WIDTH-1:0] captured_data_out;
        
        assign data_sel_pri_pre = occ_low_reset[0];
        assign data_sel_sec_pre = valid_in;
        assign captured_data_clock_en_pre = valid_out_pre & ~stall_in;
        
        if (VALID_AND_STALL_IN_EARLINESS) begin
            always_ff @(posedge clock or negedge aclrn) begin
                if (~aclrn) begin
                    data_sel_pri <= (RESET_EVERYTHING) ? '0 : 'x;
                    data_sel_sec <= (RESET_EVERYTHING) ? '0 : 'x;
                    captured_data_clock_en <= (RESET_EVERYTHING) ? '0 : 'x;
                end
                else begin
                    data_sel_pri <= data_sel_pri_pre;
                    data_sel_sec <= data_sel_sec_pre;
                    captured_data_clock_en <= captured_data_clock_en_pre;
                    if (~sclrn && RESET_EVERYTHING) begin
                        data_sel_pri <= 1'b0;
                        data_sel_sec <= 1'b0;
                        captured_data_clock_en <= 1'b0;
                    end
                end
            end
        end
        else begin
            assign data_sel_pri = data_sel_pri_pre;
            assign data_sel_sec = data_sel_sec_pre;
            assign captured_data_clock_en = captured_data_clock_en_pre;
        end
        
        always_ff @(posedge clock or negedge aclrn) begin
            if (~aclrn) begin
                captured_data_out <= (RESET_EVERYTHING) ? '0 : 'x;
            end
            else begin
                if (captured_data_clock_en) captured_data_out <= data_out;
                if (~sclrn && RESET_EVERYTHING) captured_data_out <= '0;
            end
        end
        
        assign data_out = (data_sel_pri) ? fifo_data_out : (data_sel_sec) ? data_in : captured_data_out;
    end
    endgenerate
    
    
endmodule

`default_nettype wire
