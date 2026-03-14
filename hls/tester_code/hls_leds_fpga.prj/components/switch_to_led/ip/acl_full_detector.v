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


// Full detector used in acl_stall_free_sink, implemented as a
// counter with increment and decrement signals

// The behaviour is undefined when full is asserted and incr and decr are asserted.

// This IP is used only in SFC exits. The full signal forms the
// stall (or is or'd to produce the stall). As such, we cannot write to the SFC
// while it is full because we would not be able to deassert stall. Therefore,
// asserting increment while full is not a valid input.

// To support multi-cycle resets, an SFC must assert stall_out for the duration 
// of its reset. Thus, "full" must be held high during reset, and the full_detector's
// internal reset pulse must be extended to account for any reset pipelining within
// the cluster.

// Required files:
//    acl_reset_handler.sv
//    acl_std_synchronizer_nocut.v
//    acl_fanout_pipeline.sv
//    acl_tessellated_incr_decr_threshold.sv

`default_nettype none

module acl_full_detector
#(
  parameter integer WIDTH = 5,
  parameter integer SCHEDULEII = 1,
  parameter integer ALWAYS_THROTTLE = 0,
  parameter integer FAST_COUNTER = 0,
  parameter ASYNC_RESET         = 1,     // 1 - resetn is applied asynchronously, 0 - resetn is applied synchronously
  parameter SYNCHRONIZE_RESET   = 0,     // 1 - add a local synchronizer to the incoming reset signal
  parameter EXTEND_RESET_STALL  = 0      // if > 0, pulse extends the incoming reset signal by the specified number of cycles
                                         // must be set to 0 if SYNCHRONIZE_RESET = 0
) (
  input  wire  clock,
  input  wire  resetn,
  input  wire  increment,
  input  wire  decrement,
  output logic full,

  input wire  inc_pipelined_thread,
  input wire  dec_pipelined_thread,
  output logic throttle
);

  // asynchronous/synchronous reset logic
  localparam                    NUM_RESET_COPIES = 1;
  localparam                    RESET_PIPE_DEPTH = 1;
  logic                         aclrn;
  logic [NUM_RESET_COPIES-1:0]  sclrn;
  logic                         resetn_synchronized;
  acl_reset_handler #(
    .ASYNC_RESET            (ASYNC_RESET),
    .USE_SYNCHRONIZER       (SYNCHRONIZE_RESET),
    .SYNCHRONIZE_ACLRN      (SYNCHRONIZE_RESET),
    .PULSE_EXTENSION        (EXTEND_RESET_STALL),  // Extending the reset pulse to the full detector defers the SFC's exit from "reset safe state"
    .PIPE_DEPTH             (RESET_PIPE_DEPTH),
    .NUM_COPIES             (NUM_RESET_COPIES)
  ) acl_reset_handler_inst (
    .clk                    (clock),
    .i_resetn               (resetn),
    .o_aclrn                (aclrn),
    .o_sclrn                (sclrn),
    .o_resetn_synchronized  (resetn_synchronized)
  );


 // Full detection
 reg [WIDTH-1:0] counter; 

 wire [1:0] counter_update; 
 wire [WIDTH-1:0] counter_update_extended; 
 wire [1:0] threads_count_update;
 wire [$clog2(SCHEDULEII):0] threads_count_update_extended;
 
 generate
 if (FAST_COUNTER == 1) begin
   acl_tessellated_incr_decr_threshold #(
     .CAPACITY(1 << (WIDTH-1)),
     .THRESHOLD(1 << (WIDTH-1)),
     .THRESHOLD_REACHED_AT_RESET(1),  // While reset is asserted, full should be held high (stall_out for the SFC)
     .ASYNC_RESET(ASYNC_RESET),
     .SYNCHRONIZE_RESET(0),
     .RESET_EXTERNALLY_HELD(1)
   ) fast_incr_decr_counter (
     .clock(clock),
     .resetn(resetn_synchronized),
     .incr_no_overflow(increment), // We only have one version of increment
     .incr_raw(increment),
     .decr_no_underflow(decrement), // We only have one version of decrement
     .decr_raw(decrement),
     .threshold_reached(full)
   );
 end else begin
 
   // When reset is synchronous, full should be held high while reset is asserted 
   assign full = counter[WIDTH-1] || ~sclrn[0]; 
   
   // All these counter updates are calculated first and then sign extended to reduce adder bitwidths
   assign counter_update = increment - decrement;
   assign counter_update_extended = $signed(counter_update);
   always @(posedge clock or negedge aclrn)
   begin
     if (~aclrn)
     begin
       counter <= {(WIDTH){1'b0}};
     end
     else begin
       counter <= counter + counter_update_extended;
       if (~sclrn) begin
         counter <= '0;
       end
     end
   end
 end
 endgenerate

 // Throttling
 reg[$clog2(SCHEDULEII):0] IIschedcount;
 reg[$clog2(SCHEDULEII):0] threads_count; 

 wire input_accepted;
 assign input_accepted = increment;

 assign threads_count_update = inc_pipelined_thread - dec_pipelined_thread;
 assign threads_count_update_extended = $signed(threads_count_update);

 always @(posedge clock or negedge aclrn)
 begin
  if (~aclrn) begin
    IIschedcount <= '0;
    threads_count <= '0;
  end else begin
    // do not increase the counter if a thread is exiting
    // increasing threads_count is already decreasing the window
    // increasing IIschedcount ends up accepting the next thread too early
    IIschedcount <= ((ALWAYS_THROTTLE == 0) && input_accepted && dec_pipelined_thread) ? IIschedcount : (IIschedcount == (SCHEDULEII - 1) ? 0 : (IIschedcount + 1));
    if (input_accepted) begin
      threads_count <= (ALWAYS_THROTTLE) ? (inc_pipelined_thread ? 2'b01 : threads_count) : (threads_count + threads_count_update_extended);
    end
    if (~sclrn) begin
      IIschedcount <= '0;
      threads_count <= '0;
    end

  end
 end 

 // allow threads in a window of the II cycles
 // this prevents the next iteration from entering too early
 assign throttle = (IIschedcount >= (threads_count > 0 ? threads_count : 1));

endmodule

`default_nettype wire
