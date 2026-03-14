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


/*
   acl_reset_handler
   
   This block handles the generation of asynchronous and synchronous reset 
   signals for an OpenCL system.  Only one type of reset will be generated
   (based on the ASYNC_RESET parameter), with the other hard-wired to be 
   inactive, so that any logic relying on the unused reset signal will be
   optimized away.  
   
   A code snippet showing the recommended use of the outputs from this module
   can be found at the bottom of this file.
   
   The block takes an active-low reset input that is meant to be fed by a
   global signal.  For use as an asynchronous reset, the input signal directly
   (or through a synchronizer) feeds the asynchronous reset output.  For use 
   as a synchronous reset signal, the input reset is synchronized with proper 
   metastability hardening.
   
                             *-------------------------------------------------*
                             |              AVAILABLE FEATURES                 |
   *-------------------------*--------------*----------------*-----------------*
   |       WIRING MODE       | Synchronizer | Pulse Extender | Fanout Pipeline |
   *-------------------------*--------------*----------------*-----------------*
   | synchronous             | Optional     | Optional       | Optional        |
   | async pass-through      | -            | -              | -               |
   | async with synchronizer | Must Enable  | -              | -               |
   *-------------------------*--------------*----------------*-----------------* 
   
*/
module acl_reset_handler #(
   // Configure port wiring:
   parameter   ASYNC_RESET = 0,           // set to 1 to select asynchronous reset output, 0 to select synchronous reset output
   parameter   SYNCHRONIZE_ACLRN = 0,     // set to 1 to cause the aclrn output to be fed through the synchronizer (if enabled), 0 to have it fed directly by i_resetn (when ASYNC_RESET = 1)

   // Configure the synchronizer block:
   parameter   USE_SYNCHRONIZER = 1,      // set to 1 to enable a clock domain crossing synchronizer, 0 to use i_resetn directly without a synchronizer

   // Configure the pulse extender block:
   parameter   PULSE_EXTENSION = 0,       // prolongs the duration of the synchronized reset pulse by PULSE_EXTENSION cycles
                                          // Parameter is only respected when reset is synchronous (ASYNC_RESET = 0)

   // Configure the fanout block:
   parameter   PIPE_DEPTH = 1,            // number of pipeline stages for synchronous reset outputs (pipeline stages are added AFTER the synchronizer)
                                          // A value of 0 is valid and means the input will be passed straight to the output after the synchronizer chain
   parameter   NUM_COPIES = 1             // number of copies of the synchronous reset output. Minimum value 1.
)(
   input  logic                  clk,
   input  logic                  i_resetn,      // this MUST be an active-low reset signal, NOTE that if this signal is left disconnected, the output reset signals will be stuck ASSERTED
   output logic                  o_aclrn,       // asynchronous reset output, equal to i_resetn (synchronized if SYNCHRONIZE_ACLRN=1) if ASYNC_RESET=1, hard wired to '1' otherwise
   output logic [NUM_COPIES-1:0] o_sclrn,       // multiple copies of synchronous reset output, with 'dont_merge' constraints applied to the registers that feed them to help with fanout
                                                // these signals will be hard-wired to '1' if ASYNC_RESET is 1
   output logic         o_resetn_synchronized   // signal to drive reset to local sub-modules (to prevent the need for multiple reset synchronizers within a local block)
                                                // if ASYNC_RESET = 1 and SYNCHRONIZE_ACLRN = 0, this is a copy of i_resetn, otherwise this is the reset signal after the synchronizer block
);

   localparam SYNCHRONIZER_DEFAULT_DEPTH = 3;         // this is set as a localparam so it can't be overridden by each block that instantiates this module
   localparam SYNCHRONIZER_DEPTH = USE_SYNCHRONIZER ? SYNCHRONIZER_DEFAULT_DEPTH : 0;     // if synchronizer is not being used, set depth to 0
   localparam PULSE_EXTENSION_ACTUAL = ASYNC_RESET ? 0 : PULSE_EXTENSION;  // Ignore pulse extender argument if reset type is asynchronous
  

   // acl_reset_fanout_pipeline_with_synchronizer block to synchronize the reset to the local clock and create multiple copies with pipelining
   logic [NUM_COPIES-1:0]  sclrn_pipe;
   logic                   resetn_sync;
   acl_reset_fanout_pipeline_with_synchronizer_and_pulse_extender #(
      .SYNCHRONIZER_DEPTH(SYNCHRONIZER_DEPTH),
      .PULSE_EXTENSION(PULSE_EXTENSION_ACTUAL),
      .PIPE_DEPTH(PIPE_DEPTH),
      .NUM_COPIES(NUM_COPIES)
   ) reset_fanout_pipeline (
      .clk (clk),
      .i_resetn(i_resetn),
      .o_resetn_sync(resetn_sync),
      .o_resetn(sclrn_pipe)
   );

   // if asynchronous reset is not selected, o_aclrn is hard-wired '1' (inactive)
   // if asynchronous reset is selected, o_aclrn is either a direct copy of the input i_resetn (when SYNCHRONIZE_ACLRN = 0), or a synchronized version of i_resetn
   assign o_aclrn = (ASYNC_RESET) ? ( (SYNCHRONIZE_ACLRN) ? resetn_sync : i_resetn ) : '1;

   // if asynchronous reset is not selected, or if async reset is selected and SYNCHRONIZE_ACLRN is selected, o_resetn_synchronized is taken from the output of the synchronizer block
   // if asynchronous reset is selected and SYNCHRONIZE_ACLRN is not selected, o_resetn_synchronized is a copy of i_resetn
   assign o_resetn_synchronized = (ASYNC_RESET) ? ( (SYNCHRONIZE_ACLRN) ? resetn_sync : i_resetn ) : resetn_sync;
   
   // if synchronous reset is selected, o_sclrn is taken from the acl_reset_fanout_pipeline_with_synchronizer block, otherwise hard-wire all sclrn signals to '1' (inactive)
   assign o_sclrn = (ASYNC_RESET) ? '1 : sclrn_pipe;

endmodule


/*
   acl_reset_fanout_pipeline_with_synchronizer_and_pulse_extender
   
   The intended use of this block is to take a resetn signal from a globally routed net and
   synchronize it to the clock before fanning it out to multiple copies using the acl_fanout_pipeline
   block.  Note that the input MUST be a single active-low signal, and that singal will be used
   to drive the ACLR input to synchronizer chain.  This is NOT a generic syncronizer/clock domain 
   crossing block, it is intended for a very specific purpose.

   This module wraps acl_fanout_pipeline, but passes the input signal through a synchronizer
   (a parameterizable number of back to back registers) before entering the acl_fanout_pipeline
   block.  An altera standard synchronizer block is used to synchronize the reset.
   
   Optionally, a pulse extender can be inserted between the synchronizer and the acl_fanout_pipeline
   block to prolong the duration of the reset pulse by a parameterizable number of cycles.
*/
module acl_reset_fanout_pipeline_with_synchronizer_and_pulse_extender #(
   parameter   SYNCHRONIZER_DEPTH = 3, // number of registers in the synchronizer.  0 means no synchronizer, otherwise minimum value is 2.
   parameter   PULSE_EXTENSION = 0,    // number of cycles to prolong the synchronized reset pulse. 0 means no pulse extender
   parameter   PIPE_DEPTH = 1,         // number of pipeline stages. A value of 0 is valid and means the input will be passed straight to the output after the synchronizer chain
   parameter   NUM_COPIES = 1          // number of copies of the pipeline. Minimum value 1.
)(
   input  logic                  clk,
   input  logic                  i_resetn,      // this MUST be an active-low reset signal, this block can not be used as a generic synchronizer
   output logic                  o_resetn_sync, // reset signal immediately after the synchronizer
   output logic [NUM_COPIES-1:0] o_resetn       // multiple copies of reset_out are provided, with 'dont_merge' constraints applied to the registers that feed them to help with fanout
);

   // signal used to connect the end of the synchronizer chain to the fanout_pipeline module
   logic resetn_synchronized;

   // signal used to connect the output of the pulse extender module to the fanout_pipeline module
   logic resetn_extended;
   
   generate
      if (SYNCHRONIZER_DEPTH == 0) begin     : GEN_NO_SYNCHRONIZER      // do not generate a synchronizer block
      
         assign resetn_synchronized = i_resetn;
         
      end else begin                         : GEN_SYNCHRONIZER         // do generate a synchronizer block
      
         // use n standard synchronizer block to synchronize the reset signal
         acl_std_synchronizer_nocut #(
            .depth      (SYNCHRONIZER_DEPTH),
            .rst_value  (0)
         ) reset_synchronizer (
            .clk        (clk),
            .reset_n    (i_resetn),
            .din        (1'b1),                 // when i_resetn is released, this will cause the output to synchronously de-assert
            .dout       (resetn_synchronized)
         );
   
      end
   endgenerate

   // extend the reset pulse by PULSE_EXTENSION cycles
   acl_reset_pulse_extender #(
    .EXTENSION  (PULSE_EXTENSION), // if 0, result is a wire
    .POLARITY   (0) // active low
   ) pulse_extender (
    .clk        (clk),
    .din        (resetn_synchronized), 
    .dout       (resetn_extended)
   );

   
   // connect the now synchronized and extended resetn signal to the acl_fanout_pipeline block
   acl_fanout_pipeline #(
      .PIPE_DEPTH (PIPE_DEPTH),
      .NUM_COPIES (NUM_COPIES),
      .WIDTH      (1)      
   ) reset_sync_fanout_pipeline_inst (
      .clk  (clk),
      .in   (resetn_extended),
      .out  (o_resetn)
   );
   assign o_resetn_sync = resetn_extended;

endmodule

/*
   acl_reset_pulse_extender
   
   This block takes an input signal din, which is assumed to be usually inactive but occasionally pulse active (like a reset).
   Its output is a pulse-extended version of the input signal.
  
   POWER-UP NOTE:
   Like the fanout pipeline, this module has no "reset" for its own internal state, and will power up to a random state (PR).
   If the MSB is 0 on power-up, a spurious reset pulse of unknown length will be triggered while the counter counts down to -1.
   This is not a problem because the "real" reset pulse on din will follow. The resulting behavior will be correct whether the "real" pulse
   arrives during or after the spurious pulse.   
*/
module acl_reset_pulse_extender #(
   parameter   EXTENSION = 10,   // number of cycles by which to prolong the incoming pulse
   parameter   POLARITY = 0     // 1 for active high, 0 for active low
)(
   input  logic  clk,
   input  logic  din,           // input pulse - this signal should be normally inactive, and occasionally pulsed
   output logic  dout           // output pulse - delayed by one clock cycle relative to the input pulse, and EXTENSION cycles longer
);
   // Create a dynamically sized counter to count up from -(EXTENSION+1) to 0.
   // We will use the uppermost bit to detect counter rollover with a single-bit comparison.
   localparam WIDTH = $clog2(EXTENSION+1) + 1;  // Number of bits needed to represent EXTENSION, plus one extra MSB for rollover detection
   logic [WIDTH-1:0] count;

   // Peculiar coding style is used to work around synthesis arithmetic LUT inference issue - see case 459381.
   // Must express all combinational logic as happening BEFORE the arithmetic logic to guarantee LUT depth 1. 
   logic [WIDTH-1:0] count_mod;
   logic [WIDTH-1:0] decr;

   // Present synthesis with an unmistakable counter
   always_ff @(posedge clk) begin
      count <= count_mod - decr;
   end
   
   // Express control logic as coming before the arithmetic operands
   always_comb begin
      if (din == POLARITY) begin
         // (din asserted) |=> (count == EXTENSION)
         count_mod = EXTENSION;
         decr = '0;
      end else begin
         if (!count[WIDTH-1]) begin
            // (counter not yet rolled over) |=> (decrement counter)
            count_mod = count;
            decr = 1'b1;
         end else begin
            // (counter rolled over) |=> (stay at -1)
            count_mod = '1;
            decr = '0;
         end
      end
   end
 
   // The output pulse lasts for the entire duration that the counter is not in its static "-1" state.
   // So, the uppermost counter bit is our pulse. Correct its polarity by XORing with the POLARITY parameter.
   assign dout = (EXTENSION == 0) ? din : count[WIDTH-1] ^ POLARITY;
   
   // Original code, pre-refactor (for readability)
/*
   always @(posedge clk) begin
      if (din == POLARITY) begin             // If an input pulse is detected, initialize the counter
         count <= EXTENSION;
      end 
      else if (count[WIDTH-1] != 1'b1) begin // If the input is inactive and the counter has not yet rolled over, increment it
         count <= count - 1;
      end
      else begin                             // Unnecessary "else" added for simulation X-propagation
         count <= -1;                        // Won't affect LCELL count, since count MSB is already an input to our arithmetic LUTs
      end    
   end
   
   assign dout = (EXTENSION == 0) ? din : count[WIDTH-1] ^ POLARITY;
 */

endmodule

/*
   Sample code illustrating recommended use of acl_reset_handler 
*/
/*
module my_module #(
   parameter         ASYNC_RESET = 1,
   ...
) (
   input  logic      clk,
   input  logic      i_resetn,                              // this signal is assumed to be routed on a global network (although that is not strictlty necessary)
   ...
);

   // local parameters
   localparam                    NUM_RESET_COPIES = 3;      // select this number to reduce the fanout of the synchronous reset signal within this module
   localparam                    RESET_PIPE_DEPTH = 4;      // select this number to allow adequate registers on the reset path for retiming
   
   // reset related signals
   // we will write code that uses both of these signals, but remember that one of them will be hard-wired to '1' based on whether we select asynchronous or synchronous reset
   logic                         aclrn;                     // only one async reset signal, no special handling for fanout
   logic [NUM_RESET_COPIES-1:0]  sclrn;                     // multiple copies of synchronous reset to reduce fanout
   logic                         resetn_synchronized;       // use this signal to prevent sub-blocks from requiring additional synchronizers

   // instantiate the reset handler
   acl_reset_handler #(
      .ASYNC_RESET            (ASYNC_RESET),                   // select async or sync reset
      .USE_SYNCHRONIZER       (1),                             // use a synchronizer
      .SYNCHRONIZE_ACLRN      (0),                             // do not synchronize the async clear signal (when it is used) 
      .PIPE_DEPTH             (RESET_PIPE_DEPTH),
      .NUM_COPIES             (NUM_RESET_COPIES)
   ) acl_reset_handler_inst (
      .clk                    (clk),
      .i_resetn               (i_resetn),
      .o_aclrn                (aclrn),
      .o_sclrn                (sclrn),
      .o_resetn_synchronized  (resetn_synchronized)
   );
   
   ...
   
   // sample always block showing use of both aclrn and sclrn
   always @(posedge clk or negedge aclrn) begin
      // code to use the async reset
      // remember, if ASYNC_RESET is set to 0, then aclrn is hard-wired to '1', and all this logic is
      // optimized away, so no ACLR ports are actually used in that case
      if (~aclrn) begin          
         // reset EVERY register with aclrn
         myreg1 <= '0;
         myreg2 <= '0;
         ...
      end else begin

         myreg1 <= ...;
         myreg2 <= ...;
         
         // code the sync reset
         // Since this comes at the BOTTOM of the code, the assignments here override assignments above, thus
         // the synchronous reset takes precendence over all other assignments in this always block.
         // Recommended conding style is that this code should be an exact copy of the async code above, 
         // but optionally with select lines commented out, since not all signals may need a synchronous
         // reset.  It is a good practice to only reset those registers that REQUIRE a reset here.
         if (~scnlrn[...]) begin       // select which copy of sclrn to use, to optimize fanout of each copy
            // reset only SOME register with sclrn
            myreg1 <= '0;
            //myreg2 <= '0;      // leave this code here, but commented out, to show that this signal has intentionally NOT been reset with sclrn
         end
         
      end
   end
   
   // sample sub-module instantiation that has its own synchronizer
   my_submodule1 #(
      .ASYNC_RESET      (ASYNC_RESET),       // pass this parameter on to sub modules
      ...
   ) my_submodule1_inst (
      .clk              (clk),
      .i_resetn         (i_resetn),          // pass the input reset signal straight through
      ...
   );
   
   // sample sub-module instantiation that does not have its own synchronizer
   my_submodule2 #(
      .ASYNC_RESET      (ASYNC_RESET),       // module may or may not have this parameter
      .ADD_RESET_SYNC   (0),                 // some modules may selectively allow adding a synchronizer locally or not 
                                             // this would be passed on to the USE_SYNCHRONIZER parameter in my_submodule2's acl_reset_handler
      ...
   ) my_submodule2_inst (
      .clk              (clk),
      .i_resetn         (resetn_synchronized),
      ...
   )
   
   ...
   
endmodule
*/
         
         

         
         

      
