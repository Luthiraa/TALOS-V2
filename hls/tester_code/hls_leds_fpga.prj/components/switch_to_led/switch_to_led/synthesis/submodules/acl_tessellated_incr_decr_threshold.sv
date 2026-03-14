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


// This module tracks whether FIFO occupancy is above a predefined threshold. Since the occupancy can only change by +1, 0, or -1,
// only the lower bits of the used_words counter need to be timing exact. For example, say we want to detect if occupancy >= 2. We
// activate if occupancy==1 and increasing, and we deactivate if occupancy==2 and decreasing. To detect if occupancy is 1 or 2,
// the bottom 2 bits of used_words needs to be exact, but the upper bits can be 1 clock cycle late. If the occupancy is 1 or 2 right
// now, then 1 clock cycle ago it must have been in the range of 0 to 3 inclusive. This technique is applied recursively, e.g. the
// higher bits of used_words are more stale. If we want a different threshold, then we adjust the reset value of used_words.

// This module was designed in conjunction with acl_high_speed_fifo.sv. The testbench is grouped together with the fifo.

// Required files:
// -acl_tessellated_incr_decr_threshold.sv
// -acl_reset_handler.sv
// -acl_fanout_pipeline.sv
// -acl_std_synchronizer_nocut.sv

// TEMPORARY FIX:
// Reset values are set to match the behavior of before reset cleanup. See FB case:457213. This is a workaround for now.
// Eventually the compiler needs to set the reset parameters correctly, at which point the default values will be set
// back to the original intent, which is for someone who knows nothing about the reset in their system.

`timescale 1ps/1ps
`default_nettype none

module acl_tessellated_incr_decr_threshold #(
    //general configuration
    parameter int CAPACITY,                       // occupancy starts at INITIAL_OCCUPANCY, incr_no_overflow and decr_no_underflow should never push occupancy below 0 or above CAPACITY
    parameter int THRESHOLD,                      // 1 or larger, up to CAPACITY, 1 checks for not empty, CAPACITY checks for full
    parameter int INITIAL_OCCUPANCY = 0,
    
    //special behavior needed for some cases in fifo
    parameter bit THRESHOLD_REACHED_AT_RESET = 0, // set to 1 if you want threshold_reached to be high at reset, e.g. fifo appears full at reset
    parameter int RESET_RELEASE_DELAY = 0,
    
    //reset configuration
    parameter bit ASYNC_RESET = 1,                // how do we use reset: 1 means registers are reset asynchronously, 0 means registers are reset synchronously
    parameter bit SYNCHRONIZE_RESET = 0,          // based on how reset gets to us, what do we need to do: 1 means synchronize reset before consumption (if reset arrives asynchronously), 0 means passthrough (managed externally)
    parameter bit RESET_EVERYTHING = 0,           // intended for partial reconfig debug, set to 1 to reset every register (normally async reset excludes data path and sync reset additionally excludes some control signals)
    parameter bit RESET_EXTERNALLY_HELD = 1       // set to 1 if resetn will be held for at least FIVE clock cycles, otherwise we will internally pulse stretch reset before consumption
)(
    input  wire     clock,
    input  wire     resetn,                       // longest reset chain is through the tessellated adder
    input  wire     incr_no_overflow,             // when tracking fifo occupancy, this is typically "wrreq & ~full"
    input  wire     incr_raw,                     // to detect when the threshold is reached, we don't care about overflow, so can use "wrreq"
    input  wire     decr_no_underflow,            // when tracking fifo occupancy, this is typically "rdreq & ~empty"
    input  wire     decr_raw,                     // to detect when the threshold is reached, we don't care about underflow, so can use "rdreq"
    output logic    threshold_reached             // asserted when occupancy >= THRESHOLD
);

    // the basic functionality of this circuit is as follows:
    // always_ff @(posedge clock) begin
    //     //decr must be off when occupancy is 0, incr must be off when occupancy == CAPACITY
    //     occupancy <= occupancy + incr_no_overflow - decr_no_underflow;
    //     if (~resetn) occupancy <= INITIAL_OCCUPANCY;
    // end
    // assign threshold_reached = (occupancy >= THRESHOLD);
    
    // This circuit was originally designed with the occupancy counter starting at 0 and detecting a threshold of 8. This means 
    // we need to check if occupancy==7 and increasing, or if occupancy=8 and decreasing. The idea was to allow bits 4 and
    // higher to load up to 7 clocks late, since the nearest boundary is 0 and 16. It was assumed that this would allow for
    // sufficient tessellation of the upper bits counter.
    //
    // This is the timing requirements for different bits of the occupancy counter:
    //
    // Bit range    | Name      | Max lateness  | Detection range boundary factoring in lateness
    // -------------+-----------+---------------+-------------------------------------------------
    // 1:0          | lo        | 0             | N/A - timing is exact
    // 2            | aux       | 1             | 6 to 9, are we in the right group of 4, this is basically bit 2 of (occupancy+2)
    // 3            | mid       | 3             | 4 to 11, are we in the right group of 8, this is basically bit 3 of (occupancy+4)
    // 4+           | hi        | 7             | 0 to 15, are we in the right group of 16
    //
    //                                                +-------+
    // True occupancy: -1   0   1   2   3   4   5   6 | 7   8 | 9  10  11  12  13  14  15  16
    //                                                +-------+
    //             lo:  3   0   1   2   3   0   1   2 | 3   0 | 1   2   3   0   1   2   3   0
    //                                            +---+-------+---+
    //            aux:  0   0   0   1   1   1   1 | 0   0   0   0 | 1   1   1   1   0   0   0
    //                                    +-------+---------------+-------+
    //            mid:  0   0   0   0   0 | 1   1   1   1   1   1   1   1 | 0   0   0   0   0
    //                    +---------------+-------------------------------+---------------+
    //             hi: -1 | 0   0   0   0   0   0   0   0   0   0   0   0   0   0   0   0 | 1
    //                    +---------------------------------------------------------------+
    //
    // If we want to instead detect threshold 2, the reset values of lo, aux, mid, and hi would simply change to the values in
    // the above chart in the true occupancy = 6 column, that way only 1 increment would get us to detect occupancy==7 and then second
    // increment would activate threshold_detected. In general, if the threshold increases by 1 then reset values come from one column
    // to the left, and if the threshold decreases by 1 then the reset values come from one column to the right. For example, the above
    // diagram shows we want LO_RESET=0 for THRESHOLD=8. For THRESHOLD=7, we just reset at true occupancy=1, so LO_RESET=1. In general,
    // if THRESHOLD decreases by 1 then LO_RESET increases by 1, and vice versa. Since lo is a 2-bit counter, the reset value must be
    // modulo 4. After accounting for offsets, we arrive at the LO_RESET formula below.
    //
    // Since there is lateness allowed on aux, mid, and hi, we have time to combine them and then register the output. This is
    // the "count_at_target" signal. For example to check if occupancy==7, we check if lo==3 && count_at_target==1.
    
    localparam int INIT_OCC_TO_THRESH = THRESHOLD - INITIAL_OCCUPANCY;
    localparam bit THRESHOLD_REACHED_EXIT_RESET = (THRESHOLD > INITIAL_OCCUPANCY) ? 1'b0 : 1'b1;
    
    localparam bit [31:0] MINUS_INIT_OCC_TO_THRESH = -INIT_OCC_TO_THRESH;
    localparam bit [1:0] LO_RESET = MINUS_INIT_OCC_TO_THRESH[1:0];
    
    localparam bit [31:0] ONE_PLUS_INIT_OCC_TO_THRESH = 1 + INIT_OCC_TO_THRESH;     //-1 to +2 maps to 0 to +3
    localparam bit AUX_RESET = ONE_PLUS_INIT_OCC_TO_THRESH[2];
    
    localparam bit [31:0] ELEVEN_PLUS_INIT_OCC_TO_THRESH = 11 + INIT_OCC_TO_THRESH; //-3 to +4 maps to +8 to +15
    localparam bit MID_RESET = ELEVEN_PLUS_INIT_OCC_TO_THRESH[3];
    
    localparam bit [31:0] EIGHT_MINUS_INIT_OCC_TO_THRESH = 8 - INIT_OCC_TO_THRESH;  //-7 to +8 maps to +15 to 0, +9 to +23 maps to -1 to -16
    localparam int HI_RESET = EIGHT_MINUS_INIT_OCC_TO_THRESH[31:4];
    localparam bit COUNT_AT_TARGET_RESET = (HI_RESET==0) ? 1'b1 : 1'b0;
    
    //reset
    genvar g;
    logic aclrn, sclrn;
    logic sclrn_before_pulse_stretch, sclrn_after_pulse_stretch, sclrn_base;
    logic [2:0] sclrn_chain;
    
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
    if (RESET_EXTERNALLY_HELD) begin : gen_direct_sclrn
        assign sclrn = sclrn_before_pulse_stretch;
    end
    else begin : gen_pulse_stretch_sclrn
        always_ff @(posedge clock) begin
            sclrn_chain <= (sclrn_chain << 1) | sclrn_before_pulse_stretch;
            sclrn_after_pulse_stretch <= &sclrn_chain;
            sclrn_base <= sclrn_after_pulse_stretch;
            sclrn <= sclrn_base;
        end
    end
    endgenerate
    
    //assuming occupancy starts at 0, so if threshold_reached needs to be asserted during reset, we need a way to deassert it after reset is released
    logic [RESET_RELEASE_DELAY+1:0] resetn_delayed;
    generate
    always_comb begin
        resetn_delayed[0] = (ASYNC_RESET) ? aclrn : sclrn;      //delay 0 = original reset that threshold_reached would have consumed
    end
    for (g=1; g<=RESET_RELEASE_DELAY+1; g++) begin : gen_resetn_delayed
        always_ff @(posedge clock or negedge aclrn) begin
            if (~aclrn) resetn_delayed[g] <= '0;
            else begin
                resetn_delayed[g] <= (g==1) ? 1'b1 : resetn_delayed[g-1];
                if (~sclrn) resetn_delayed[g] <= '0;
            end
        end
    end
    endgenerate
    
    
    logic [1:0] lo, lo_prev;
    logic       aux, incr_aux, decr_aux;
    logic       mid, lo_wrap_around;
    logic       incr_hi, decr_hi;
    logic       hi_eq_zero, count_at_target;
    
    generate
    if (THRESHOLD < 1) begin
        assign threshold_reached = 1'b1;
    end
    else if (THRESHOLD > CAPACITY) begin
        assign threshold_reached = 1'b0;
    end
    else if (CAPACITY == 1) begin
        always_ff @(posedge clock or negedge aclrn) begin
            if (~aclrn) threshold_reached <= THRESHOLD_REACHED_AT_RESET;
            else begin
                if (incr_no_overflow) threshold_reached <= 1'b1;
                if (decr_no_underflow) threshold_reached <= 1'b0;
                if (~resetn_delayed[RESET_RELEASE_DELAY+1]) threshold_reached <= THRESHOLD_REACHED_EXIT_RESET;
                if (~resetn_delayed[RESET_RELEASE_DELAY]) threshold_reached <= THRESHOLD_REACHED_AT_RESET;
            end
        end
    end
    else begin
        
        // lo tracks the lower 2 bits of occupancy with exact timing
        always_ff @(posedge clock or negedge aclrn) begin
            if (~aclrn) begin
                lo <= LO_RESET;
                lo_prev <= LO_RESET;
            end
            else begin
                // a more quartus-friedly version of:
                // lo <= lo + incr_no_overflow - decr_no_underflow
                lo[0] <= lo[0] ^ incr_no_overflow ^ decr_no_underflow;
                lo[1] <= lo[1] ^ (incr_no_overflow & ~decr_no_underflow & lo[0]) ^ (~incr_no_overflow & decr_no_underflow & ~lo[0]);
                lo_prev <= lo;
                if (~sclrn) lo <= LO_RESET;
                if (~sclrn && RESET_EVERYTHING) lo_prev <= LO_RESET;
            end
        end
        
        // aux tracks bit 2 of occupancy and is 1 clock late compared to lo
        // aux flips its value every time lo transitions between 1 and 2, therefore aux is guaranteed to be stable when lo is 0 or 3
        always_ff @(posedge clock or negedge aclrn) begin
            if (~aclrn) begin
                incr_aux <= 1'b0;
                decr_aux <= 1'b0;
                aux <= AUX_RESET;
            end
            else begin
                // conceptually we want is this:
                // flip_aux <= (incr_no_overflow & ~decr_no_underflow & (lo==2'h1)) | (~incr_no_overflow & decr_no_underflow & (lo==2'h2));
                // aux <= aux ^ flip_aux;
                // but flip_aux would be a 7 or 8 input function, so this has been split into two components
                incr_aux <= (incr_no_overflow & (lo==2'h1)) | (~incr_no_overflow & (lo==2'h2));
                decr_aux <= (~decr_no_underflow & (lo==2'h1)) | (decr_no_underflow & (lo==2'h2));
                aux <= aux ^ (incr_aux & decr_aux);
                if (~sclrn) begin
                    incr_aux <= 1'b0;
                    decr_aux <= 1'b0;
                    aux <= AUX_RESET;
                end
            end
        end
        
        // mid tracks bit 3 of occupancy and is 2 clocks late compared to lo
        always_ff @(posedge clock or negedge aclrn) begin
            if (~aclrn) begin
                lo_wrap_around <= 1'b0;
                mid <= MID_RESET;
            end
            else begin
                lo_wrap_around <= ((lo==2'h0) & (lo_prev==2'h3)) | ((lo==2'h3) & (lo_prev==2'h0));  //one clock later than lo
                mid <= mid ^ (lo_wrap_around & aux);                                                //two clocks later than lo
                if (~sclrn) begin
                    lo_wrap_around <= 1'b0;
                    mid <= MID_RESET;
                end
            end
        end
        
        // hi tracks bits 4+ of occupancy and is up to 6 clocks late compared to lo
        always_ff @(posedge clock or negedge aclrn) begin
            if (~aclrn) begin
                incr_hi <= 1'b0;
                decr_hi <= 1'b0;
            end
            else begin
                incr_hi <= lo_wrap_around & ~aux & ~mid & ~lo_prev[0];  //two clocks later than lo
                decr_hi <= lo_wrap_around & ~aux & ~mid & lo_prev[0];
                if (~sclrn) begin
                    incr_hi <= 1'b0;
                    decr_hi <= 1'b0;
                end
            end
        end
        
        if ($clog2(CAPACITY) >= 5) begin
            localparam int COUNT_HI_WIDTH = $clog2(CAPACITY)-4;
            localparam int COUNT_HI_TESS_RAW = (COUNT_HI_WIDTH+1)/2;    //2 bits per stage
            localparam int COUNT_HI_TESS = (COUNT_HI_TESS_RAW > 4) ? 4 : COUNT_HI_TESS_RAW;
            
            acl_tessellated_incr_decr #(
                .WIDTH              (COUNT_HI_WIDTH),
                .STAGES             (COUNT_HI_TESS),    //max 4 so that hi_eq_zero is up to 6 clocks late
                .RESET_VALUE        (HI_RESET),
                .RESET_EVERYTHING   (RESET_EVERYTHING)
            )
            acl_tessellated_incr_decr_inst
            (
                .clock              (clock),
                .aclrn              (aclrn),
                .sclrn              (sclrn),
                .incr_in            (incr_hi),          //2 clocks late
                .decr_in            (decr_hi),
                .counter            (),
                .count_eq_zero      (hi_eq_zero)        //2 + STAGES clock cycles late, up to 6
            );
        end
        else begin
            assign hi_eq_zero = 1'b1;
        end
        
        
        // merge the information in aux, mid, and hi
        // aux is allowed to be 1 clock late, mid is allowed to be 3 clocks late, and hi is allowed to be 7 clocks late
        // to register the merged information, we actually need the above components one clock earlier
        // this is fine for mid and hi, but for aux we just the next state value which is: (aux ^ (incr_aux & decr_aux))
        
        // let quartus trim away stuff that isn't needed at smaller bit width
        if (CAPACITY <= 4) begin
            assign count_at_target = 1'b1;
        end
        else if (CAPACITY <= 8) begin
            assign count_at_target = ~aux;
        end
        else begin
            always_ff @(posedge clock or negedge aclrn) begin
                if (~aclrn) count_at_target <= COUNT_AT_TARGET_RESET;
                else begin
                    count_at_target <= hi_eq_zero & mid & ~(aux ^ (incr_aux & decr_aux));
                    if (~sclrn) count_at_target <= COUNT_AT_TARGET_RESET;
                end
            end
        end
        
        // finally, check if we are crossing the threshold
        if (THRESHOLD == 1) begin               //checking for not empty
            always_ff @(posedge clock or negedge aclrn) begin
                if (~aclrn) threshold_reached <= THRESHOLD_REACHED_AT_RESET;
                else begin
                    if (decr_raw & (lo==2'h0) & count_at_target) threshold_reached <= 1'b0;
                    if (incr_raw) threshold_reached <= 1'b1;
                    if (~resetn_delayed[RESET_RELEASE_DELAY+1]) threshold_reached <= THRESHOLD_REACHED_EXIT_RESET;
                    if (~resetn_delayed[RESET_RELEASE_DELAY]) threshold_reached <= THRESHOLD_REACHED_AT_RESET;
                end
            end
        end
        else if (THRESHOLD == CAPACITY) begin   //checking for full
            always_ff @(posedge clock or negedge aclrn) begin
                if (~aclrn) threshold_reached <= THRESHOLD_REACHED_AT_RESET;
                else begin
                    if (incr_raw & (lo==2'h3) & count_at_target) threshold_reached <= 1'b1;
                    if (decr_raw) threshold_reached <= 1'b0;
                    if (~resetn_delayed[RESET_RELEASE_DELAY+1]) threshold_reached <= THRESHOLD_REACHED_EXIT_RESET;
                    if (~resetn_delayed[RESET_RELEASE_DELAY]) threshold_reached <= THRESHOLD_REACHED_AT_RESET;
                end
            end
        end
        else begin                              //if threshold is not near full or empty, don't need to guard against overflow/underflow
            always_ff @(posedge clock or negedge aclrn) begin
                if (~aclrn) threshold_reached <= THRESHOLD_REACHED_AT_RESET;
                else begin
                    if (incr_raw & ~decr_raw & (lo==2'h3) & count_at_target) threshold_reached <= 1'b1;
                    if (~incr_raw & decr_raw & (lo==2'h0) & count_at_target) threshold_reached <= 1'b0;
                    if (~resetn_delayed[RESET_RELEASE_DELAY+1]) threshold_reached <= THRESHOLD_REACHED_EXIT_RESET;
                    if (~resetn_delayed[RESET_RELEASE_DELAY]) threshold_reached <= THRESHOLD_REACHED_AT_RESET;
                end
            end
        end
    end
    endgenerate
    
endmodule





module acl_tessellated_incr_decr #(
    parameter int WIDTH,
    parameter int STAGES,
    parameter int RESET_VALUE,
    parameter int RESET_EVERYTHING
)
(
    input  wire                 clock,
    input  wire                 aclrn,
    input  wire                 sclrn,
    input  wire                 incr_in,
    input  wire                 decr_in,
    output logic    [WIDTH-1:0] counter,
    output logic                count_eq_zero
);
    
    localparam bit [WIDTH-1:0] RV = RESET_VALUE;    //allows for bit extractions from RESET_VALUE
    
    logic [STAGES:0] inc, dec, cz;
    logic [WIDTH-1:0] cnt;
    assign inc[0] = incr_in;
    assign dec[0] = decr_in;
    assign cz[0] = 1'b1;
    assign count_eq_zero = cz[STAGES];
    assign counter = cnt;
    
    genvar g;
    generate
    for (g=0; g<STAGES; g=g+1) begin : gen_cnt
        localparam int HI = (g+1) * WIDTH / STAGES; //exclusive
        localparam int LO = (g) * WIDTH / STAGES;   //inclusive
        //at each stage we do the following:
        //increment out = (increment in) & (counter_bits_for_this_stage are all 1)
        //decrement out = (decrement in) & (counter_bits_for_this_stage are all 0)
        //count_equals_zero out = (count_equals_zero in) & (next state value of counter_bits_for_this_stage are all 0)
        //counter_bits_for_this_stage out = (counter_bits_for_this_stage in) + (increment in) - (decrement in)
        if ( HI - LO == 0 ) begin   //counter width is 0, this is just a pipeline stage
            always_ff @(posedge clock or negedge aclrn) begin
                if (~aclrn) begin
                    inc[g+1] <= 1'b0;
                    dec[g+1] <= 1'b0;
                    cz[g+1] <= 1'b1;
                end
                else begin
                    inc[g+1] <= inc[g];
                    dec[g+1] <= dec[g];
                    cz[g+1] <= cz[g];
                    if (~sclrn && RESET_EVERYTHING) begin
                        inc[g+1] <= 1'b0;
                        dec[g+1] <= 1'b0;
                        cz[g+1] <= 1'b1;
                    end
                end
            end
        end
        else if ( HI - LO == 1) begin       //counter width is 1
            always_ff @(posedge clock or negedge aclrn) begin
                if (~aclrn) begin
                    inc[g+1] <= 1'b0;
                    dec[g+1] <= 1'b0;
                    cz[g+1] <= ~(|RV[LO:0]);
                    cnt[LO] <= RV[LO];
                end
                else begin
                    inc[g+1] <= inc[g] & cnt[LO];
                    dec[g+1] <= dec[g] & ~cnt[LO];
                    cz[g+1] <= cz[g] & ~(cnt[LO] ^ inc[g] ^ dec[g]);
                    cnt[LO] <= cnt[LO] ^ inc[g] ^ dec[g];
                    if (~sclrn) begin
                        cnt[LO] <= RV[LO];
                        if (RESET_EVERYTHING) begin
                            inc[g+1] <= 1'b0;
                            dec[g+1] <= 1'b0;
                            cz[g+1] <= ~(|RV[LO:0]);
                        end
                    end
                end
            end
        end
        else begin
            logic [1:0] cnt_up;     //need to sign extend before adding       
            assign cnt_up[0] = inc[g] ^ dec[g];    //assert if intended effect is +1 or -1
            assign cnt_up[1] = ~inc[g] & dec[g];   //assert if intended effect is -1
            always_ff @(posedge clock or negedge aclrn) begin
                if (~aclrn) begin
                    inc[g+1] <= 1'b0;
                    dec[g+1] <= 1'b0;
                    cz[g+1] <= ~(|RV[HI-1:0]);
                    cnt[HI-1:LO] <= RV[HI-1:LO];
                end
                else begin
                    inc[g+1] <= inc[g] & (&cnt[HI-1:LO]);
                    dec[g+1] <= dec[g] & ~(|cnt[HI-1:LO]);
                    cz[g+1] <= cz[g] &
                        ((inc[g] & ~dec[g]) ? (&cnt[HI-1:LO]) :                     //increasing and cnt is all ones -> will become all zeros
                        ((~inc[g] & dec[g]) ? (~(|cnt[HI-1:LO+1]) & cnt[LO]) :      //decreasing and cnt is like 001 -> will become all zeros
                        ~(|cnt[HI-1:LO])));                                         //no change and cnt is already all zeros
                    cnt[HI-1:LO] <= cnt[HI-1:LO] + { {(HI-LO-1){cnt_up[1]}} , cnt_up[0] };
                    if (~sclrn) begin
                        cnt[HI-1:LO] <= RV[HI-1:LO];
                        if (RESET_EVERYTHING) begin
                            inc[g+1] <= 1'b0;
                            dec[g+1] <= 1'b0;
                            cz[g+1] <= ~(|RV[HI-1:0]);
                        end
                    end
                end
            end
        end
    end
    endgenerate
    
endmodule

`default_nettype wire
