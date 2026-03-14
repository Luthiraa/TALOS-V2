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
// C backend 'push' primitive
//
// Upstream are signals that go to the feedback (snk node is a acl_pop),
// downstream are signals that continue into our "normal" pipeline.
//
// dir indicates if you want to push it to the feedback
//   1 - push to feedback
//   0 - bypass, just push out to downstream
//===----------------------------------------------------------------------===//

// altera message_off 10036

module acl_push (
	clock,
	resetn,

	// interface from kernel pipeline, input stream
	dir,
	data_in,
    valid_in,
    stall_out,
    predicate,

	// interface to kernel pipeline, downstream
    valid_out,
    stall_in,
    data_out,

	// interface to pipeline feedback, upstream
    feedback_out,
    feedback_valid_out,
    feedback_stall_in
);

    parameter DATA_WIDTH = 32;
    parameter FIFO_DEPTH = 1;
    parameter MIN_FIFO_LATENCY = 0;
    // style can be "REGULAR", for a regular push
    // or "TOKEN" for a special fifo that hands out tokens 
    parameter string STYLE = "REGULAR";     // "REGULAR"/"TOKEN"
    parameter STALLFREE = 0;
    parameter ENABLED = 0;
    parameter INF_LOOP = 0;
    parameter INF_LOOP_INITIALIZATION = 32'b0;  // Initial value to use, when INITIALIZE_TO_VALID is 1
    parameter RAM_FIFO_DEPTH_INC = 1; // allows incrementing RAM fifo depth by 1

input clock, resetn, stall_in, valid_in, feedback_stall_in;
output stall_out, valid_out, feedback_valid_out;
input [DATA_WIDTH-1:0] data_in;
input dir;
input predicate;
output [DATA_WIDTH-1:0] data_out, feedback_out;

wire [DATA_WIDTH-1:0] feedback;
wire data_downstream, data_upstream;

wire push_upstream;
assign push_upstream = dir & ~predicate;

assign data_upstream = valid_in & push_upstream;
assign data_downstream = valid_in;

wire feedback_stall, feedback_valid;

reg consumed_downstream, consumed_upstream;

generate
if (STYLE == "BYPASS") begin
  // Turn this push into wires
  assign valid_out = valid_in;
  assign stall_out = stall_in;
  assign feedback_valid_out = 1'b0;
  assign feedback_out = 'bx;
  assign data_out = data_in;
end else begin

  assign valid_out = data_downstream & !consumed_downstream;
  assign feedback_valid = data_upstream & !consumed_upstream & (ENABLED ? ~stall_in : 1'b1);
  assign data_out = data_in;
  assign feedback = data_in;
  
  assign stall_out = stall_in | (feedback_stall & push_upstream );
  
     if (ENABLED) begin
  
        always @(posedge clock or negedge resetn) begin
           if (!resetn) begin
              consumed_downstream <= 1'b0;
              consumed_upstream <= 1'b0;
           end else begin
              if (~stall_in) begin
                 if (consumed_downstream)
                   consumed_downstream <= stall_out;
                 else  
                   consumed_downstream <= stall_out & data_downstream;
  
                 consumed_upstream <= 1'b0;
              end
           end
        end
  
     end else begin
  
        always @(posedge clock or negedge resetn) begin
           if (!resetn) begin
              consumed_downstream <= 1'b0;
              consumed_upstream <= 1'b0;
           end else begin
              if (consumed_downstream)
                consumed_downstream <= stall_out;
              else  
                consumed_downstream <= stall_out & (data_downstream & ~stall_in);
  
              if (consumed_upstream)
                consumed_upstream <= stall_out;
              else  
                consumed_upstream <= stall_out & (data_upstream & ~feedback_stall);
           end
        end
  
     end
  
  localparam TYPE = MIN_FIFO_LATENCY < 1 ? (FIFO_DEPTH < 8 ? "zl_reg" : "zl_ram") : (MIN_FIFO_LATENCY < 3 ? (FIFO_DEPTH < 8 ? "ll_reg" : "ll_ram") : (FIFO_DEPTH < 8 ? "ll_reg" : "ram"));
  
  if ( STYLE == "TOKEN" )
  begin
    acl_token_fifo_counter 
    #(
      .DEPTH(FIFO_DEPTH)
     )
    fifo (
      .clock(clock),
      .resetn(resetn),
      .data_out(feedback_out),
      .valid_in(feedback_valid),
      .valid_out(feedback_valid_out),
      .stall_in(feedback_stall_in),
      .stall_out(feedback_stall)
    );
  end
  else if (FIFO_DEPTH == 0) begin
    // if no FIFO depth is requested, just connect
    // feedback directly to output
    assign feedback_out = feedback;
    assign feedback_valid_out = feedback_valid;
    assign feedback_stall = feedback_stall_in;
  end
  else if (FIFO_DEPTH == 1 && MIN_FIFO_LATENCY == 0) begin
    // simply add a staging register if the requested depth is 1
    // and the latency must be 0
    acl_staging_reg #(
    .WIDTH(DATA_WIDTH)
    ) staging_reg (
    .clk(clock), 
    .reset(~resetn), 
    .i_data(feedback),
    .i_valid(feedback_valid),
    .o_stall(feedback_stall),
    .o_data(feedback_out), 
    .o_valid(feedback_valid_out), 
    .i_stall(feedback_stall_in)
    );
  end
  else
  begin
  
    // only allow full write in stall free clusters if you're an ll_reg
    // otherwise, comb cycles can form, since stall_out depends on
    // stall_in the acl_data_fifo.  To make up for the last space, we
    // add a capacity of 1 to the FIFO
    localparam OFFSET = ( (TYPE == "ll_reg") && !STALLFREE ) ? 1 : 0;
    localparam ALLOW_FULL_WRITE = ( (TYPE == "ll_reg") && !STALLFREE ) ? 0 : 1;
  
    acl_data_fifo #(
     .DATA_WIDTH(DATA_WIDTH),
     .DEPTH(((TYPE == "ram")  || (TYPE == "ll_ram") || (TYPE == "zl_ram")) ? FIFO_DEPTH + RAM_FIFO_DEPTH_INC : FIFO_DEPTH + OFFSET),
     .IMPL(TYPE),
     .ALLOW_FULL_WRITE(ALLOW_FULL_WRITE),
     .INITIALIZE_TO_VALID(INF_LOOP),
     .INITIAL_FIFO_VALUE(INF_LOOP_INITIALIZATION)
     )
    fifo (
    .clock(clock),
    .resetn(resetn),
    .data_in(feedback),
    .data_out(feedback_out),
    .valid_in(feedback_valid),
    .valid_out(feedback_valid_out),
    .stall_in(feedback_stall_in),
    .stall_out(feedback_stall)
    );
  end
end
endgenerate

endmodule

