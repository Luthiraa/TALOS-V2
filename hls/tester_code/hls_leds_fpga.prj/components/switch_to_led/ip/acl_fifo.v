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
// Parameterized FIFO with input and output registers and ACL pipeline
// protocol ports.
//
//===----------------------------------------------------------------------===//
module acl_fifo (
	clock,
	resetn,
	data_in,
	data_out,
	valid_in,
	valid_out,
	stall_in,
	stall_out,
	usedw,
	empty,
	full,
	almost_full);

	function integer my_local_log;
	input [31:0] value;
		for (my_local_log=0; value>0; my_local_log=my_local_log+1)
			value = value>>1;
	endfunction		
	
	parameter DATA_WIDTH = 32;
	parameter DEPTH = 256;
	parameter NUM_BITS_USED_WORDS = DEPTH == 1 ? 1 : my_local_log(DEPTH-1);
	parameter ALMOST_FULL_VALUE = 0;
	parameter LPM_HINT = "unused";
        parameter string IMPL = "basic";   // impl: (basic|pow_of_2_full|pow_of_2_full_reg_data_in|pow_of_2_full_reg_output_accepted|pow_of_2_full_reg_data_in_reg_output_accepted)

	input clock, stall_in, valid_in, resetn;
	output stall_out, valid_out;
	input [DATA_WIDTH-1:0] data_in;
	output [DATA_WIDTH-1:0] data_out;
	output [NUM_BITS_USED_WORDS-1:0] usedw;
        output empty, full, almost_full;

  generate
    if ((IMPL == "pow_of_2_full") || 
        (IMPL == "pow_of_2_full_reg_output_accepted") ||
        (IMPL == "pow_of_2_full_reg_data_in") ||
        (IMPL == "pow_of_2_full_reg_data_in_reg_output_accepted"))
    begin
          localparam DEPTH_LOG2 = $clog2(DEPTH);
          localparam DEPTH_SNAPPED_TO_POW_OF_2 = 1 << DEPTH_LOG2;
          localparam FULL_COUNTER_OFFSET = DEPTH_SNAPPED_TO_POW_OF_2 - DEPTH;
          
          localparam ALMOST_FULL_DEPTH_LOG2 = $clog2(DEPTH); // required to be DEPTH, this guarantees that almost_full=1 iff fifo occupancy >= ALMOST_FULL_VALUE
          localparam ALMOST_FULL_DEPTH_SNAPPED_TO_POW_OF_2 = 1 << ALMOST_FULL_DEPTH_LOG2;
          localparam ALMOST_FULL_COUNTER_OFFSET = ALMOST_FULL_DEPTH_SNAPPED_TO_POW_OF_2 - ALMOST_FULL_VALUE;

          reg [DEPTH_LOG2:0]              full_counter;
          reg [ALMOST_FULL_DEPTH_LOG2:0]  almost_full_counter;
          
          wire input_accepted_comb;
          wire input_accepted_for_fifo;
          wire input_accepted_for_counter;
          wire output_accepted_comb;
          wire output_accepted_for_fifo;
          wire output_accepted_for_counter;
          wire [DATA_WIDTH-1:0] data_in_for_fifo;
          wire [1:0] counter_update;
          wire [DEPTH_LOG2:0] full_counter_update;
          wire [ALMOST_FULL_DEPTH_LOG2:0] almost_full_counter_update;

          assign full         = full_counter[DEPTH_LOG2];
          assign almost_full  = almost_full_counter[ALMOST_FULL_DEPTH_LOG2];

          assign input_accepted_comb  = valid_in & ~full;
          assign output_accepted_comb = ~stall_in & ~empty;

          assign input_accepted_for_counter = input_accepted_comb;
          assign output_accepted_for_fifo   = output_accepted_comb;

          assign counter_update = input_accepted_for_counter - output_accepted_for_counter;
          // Sign extend to the correct widths
          assign full_counter_update = $signed(counter_update);
          assign almost_full_counter_update = $signed(counter_update);

          if ((IMPL == "pow_of_2_full") || (IMPL=="pow_of_2_full_reg_data_in"))
          begin
            assign output_accepted_for_counter = output_accepted_comb;
          end
          else // pow_of_2_full_reg_output_accepted, pow_of_2_full_reg_output_accepted_reg_data_in
          begin
            reg stall_in_reg;
            reg empty_reg;

            always @(posedge clock or negedge resetn)
            begin
              if (~resetn)
              begin
                stall_in_reg  <= 1;
                empty_reg     <= 1;
              end
              else
              begin
                stall_in_reg  <= stall_in;
                empty_reg     <= empty;
              end
            end 
            
            // registered and retimed version of output_accepted_comb
            assign output_accepted_for_counter = ~stall_in_reg & ~empty_reg;
          end

          if ((IMPL == "pow_of_2_full") || (IMPL == "pow_of_2_full_reg_output_accepted")) 
          begin
            assign input_accepted_for_fifo    = input_accepted_comb;
            assign data_in_for_fifo           = data_in;
          end
          else // pow_of_2_full_reg_data_in, pow_of_2_full_reg_output_accepted_reg_data_in
          begin
            reg input_accepted_reg;
            reg [DATA_WIDTH-1:0] data_in_reg;

            always @(posedge clock or negedge resetn)
            begin
              if (~resetn)
              begin
                input_accepted_reg  <= 0;
                data_in_reg         <= 'x;
              end
              else
              begin
                input_accepted_reg  <= input_accepted_comb;
                data_in_reg         <= data_in;
              end
            end

            assign input_accepted_for_fifo    = input_accepted_reg;
            assign data_in_for_fifo           = data_in_reg;
          end
          
          always @(posedge clock or negedge resetn)
          begin
            if (~resetn)
            begin
              full_counter        <= FULL_COUNTER_OFFSET;
              almost_full_counter <= ALMOST_FULL_COUNTER_OFFSET;
            end
            else
            begin
              full_counter        <= full_counter         + full_counter_update; 
              almost_full_counter <= almost_full_counter  + almost_full_counter_update;
            end
          end 

          scfifo	scfifo_component (
                                  .clock (clock),
                                  .data (data_in_for_fifo),
                                  .rdreq (output_accepted_for_fifo),
                                  .sclr (),
                                  .wrreq (input_accepted_for_fifo),
                                  .empty (empty),
                                  .full (), // dangle and synthesize away SCFIFO's full logic
                                  .q (data_out),
                                  .aclr (~resetn),
                                  .almost_empty (),
                                  .almost_full (), // dangle and synthesize away SCFIFO's almost_full logic
                                  .usedw (usedw));
          defparam
                  scfifo_component.add_ram_output_register = "ON",
                  scfifo_component.intended_device_family = "Stratix IV",
                  scfifo_component.lpm_hint = LPM_HINT,
                  scfifo_component.lpm_numwords = DEPTH,
                  scfifo_component.lpm_showahead = "ON",
                  scfifo_component.lpm_type = "scfifo",
                  scfifo_component.lpm_width = DATA_WIDTH,
                  scfifo_component.lpm_widthu = NUM_BITS_USED_WORDS,
                  scfifo_component.use_eab = "ON",
                  scfifo_component.almost_full_value = 0; // not used

          assign stall_out = full;
          assign valid_out = ~empty;
    end 
    else 
    begin // default to "basic"

          scfifo	scfifo_component (
                                  .clock (clock),
                                  .data (data_in),
                                  .rdreq ((~stall_in) & (~empty)),
                                  .sclr (),
                                  .wrreq (valid_in & (~full)),
                                  .empty (empty),
                                  .full (full),
                                  .q (data_out),
                                  .aclr (~resetn),
                                  .almost_empty (),
                                  .almost_full (almost_full),
                                  .usedw (usedw));
          defparam
                  scfifo_component.add_ram_output_register = "ON",
                  scfifo_component.intended_device_family = "Stratix IV",
                  scfifo_component.lpm_hint = LPM_HINT,
                  scfifo_component.lpm_numwords = DEPTH,
                  scfifo_component.lpm_showahead = "ON",
                  scfifo_component.lpm_type = "scfifo",
                  scfifo_component.lpm_width = DATA_WIDTH,
                  scfifo_component.lpm_widthu = NUM_BITS_USED_WORDS,
                  scfifo_component.overflow_checking = "ON",
                  scfifo_component.underflow_checking = "ON",
                  scfifo_component.use_eab = "ON",
                  scfifo_component.almost_full_value = ALMOST_FULL_VALUE;

          assign stall_out = full;
          assign valid_out = ~empty;
    end
  endgenerate


endmodule
