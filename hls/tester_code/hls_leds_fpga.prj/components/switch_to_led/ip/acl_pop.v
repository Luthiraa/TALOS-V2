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
// C backend 'pop' primitive
//
//===----------------------------------------------------------------------===//

// altera message_off 10230

module acl_pop (
        clock,
        resetn,

        // input stream from kernel pipeline
        dir,
        valid_in,
        data_in,
        stall_out,
        predicate,

        // downstream, to kernel pipeline
        valid_out,
        stall_in,
        data_out,

        // feedback downstream, from feedback acl_push
        feedback_in,
        feedback_valid_in,
        feedback_stall_out
);

parameter DATA_WIDTH = 32;
parameter string STYLE = "REGULAR";  // REGULAR vs COALESCE
parameter COALESCE_DISTANCE = 1;
parameter INF_LOOP = 0;

    // this will pop garbage off of the feedback
localparam POP_GARBAGE = STYLE == "COALESCE" ? 1 : 0;

input clock, resetn, stall_in, valid_in, feedback_valid_in;
output stall_out, valid_out, feedback_stall_out;
input [DATA_WIDTH-1:0] data_in;
input dir;
input predicate;
output [DATA_WIDTH-1:0] data_out;
input [DATA_WIDTH-1:0] feedback_in;

localparam DISTANCE_WIDTH = ((POP_GARBAGE == 1) && (COALESCE_DISTANCE > 1)) ? $clog2(COALESCE_DISTANCE) : 1;

wire feedback_downstream, data_downstream;

wire pop_garbage;
wire actual_dir;

generate
if (STYLE == "BYPASS") begin
  // Turn this pop into wires
  assign valid_out = valid_in;
  assign stall_out = stall_in;
  assign feedback_stall_out = 1'b0;
  assign data_out = data_in;
end else begin
  if(POP_GARBAGE == 0) begin
    // For non-coalesced pops, we don't need to generate the
    // counter logic. Though quartus probably would have sweeped
    // away the extraneous logic, this makes it clear.
    assign pop_garbage = 0;
  end else begin
    reg [DISTANCE_WIDTH-1:0] garbage_count;
    reg pop_garbage_r;
    always @(posedge clock or negedge resetn)
    begin
      if ( !resetn ) begin
        pop_garbage_r = 0;
      end
      else if ( ( garbage_count == {(DISTANCE_WIDTH){1'b0}} ) && (valid_out & ~stall_in & ~predicate) ) begin
        // If the garbage count will hit -1 next cycle then we can start popping garbage
        pop_garbage_r = POP_GARBAGE;
      end
    end

    assign pop_garbage = pop_garbage_r;

    always @(posedge clock or negedge resetn)
    begin
      if ( !resetn ) begin
        garbage_count = COALESCE_DISTANCE-1;
      end
      else if ( valid_out & ~stall_in & ~predicate) begin
        // If we're predicated then we can't decrement the garbage count this cycle because valid data wasn't fed into the push
        garbage_count = garbage_count - 1'b1;
      end
    end
  end

  if (INF_LOOP == 1) begin
    // If we're in an infinite loop where feedback_in clears to the value of data_in, we don't need
    // to ever select data_in.  Case:432276
    assign actual_dir = 1'b0;
  end else begin
    assign actual_dir = dir;
  end

  assign feedback_downstream = valid_in & ~actual_dir & feedback_valid_in;
  assign data_downstream = valid_in & actual_dir;

  assign valid_out = feedback_downstream | ( data_downstream & (~pop_garbage | feedback_valid_in ) ) ;

  assign data_out = ~actual_dir ? feedback_in : data_in;

  //assign stall_out = stall_in;
  //assign stall_out = valid_in & ~((feedback_downstream | data_downstream) & ~stall_in);
  // assign stall_out = ~((feedback_downstream | data_downstream) & ~stall_in);
  // stall upstream if
  //   downstream is stalling (stall_in)
  //   I'm waiting for data from feedback (valid_in&~actual_dir&~feedback_valid_in)
  assign stall_out = ( valid_in & ( ( ~actual_dir & ~feedback_valid_in ) |  ( actual_dir & ~feedback_valid_in & pop_garbage ) )  ) | stall_in;

  // don't accept data if:
  //  downstream cannot accept data (stall_in)
  //  data from upstream is selected (data_downstream)
  //  no thread exists to read data (~valid_in)
  //  predicate is high
  assign feedback_stall_out = stall_in  | (data_downstream & ~pop_garbage) | ~valid_in | predicate;

end
endgenerate

endmodule

