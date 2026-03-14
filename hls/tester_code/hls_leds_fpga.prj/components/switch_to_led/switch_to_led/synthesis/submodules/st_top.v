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
 * This is a variant of the staging reg - which allows you to add an
 * pre-initialized value; useful for feedback channels
 */
module init_reg
(
    clk, reset, i_init, i_data, i_valid, o_stall, o_data, o_valid, i_stall
);

/*************
* Parameters *
*************/
parameter WIDTH    = 32;
parameter INIT     = 0;
parameter INIT_VAL = 32'h0000000000000000;

/********
* Ports *
********/
// Standard global signals
input clk;
input reset;
input i_init;

// Upstream interface
input [WIDTH-1:0] i_data;
input i_valid;
output o_stall;

// Downstream interface
output [WIDTH-1:0] o_data;
output o_valid;
input i_stall;

/***************
* Architecture *
***************/
reg [WIDTH-1:0] r_data;
reg r_valid;

// Upstream
assign o_stall = r_valid;

// Downstream
assign o_data = (r_valid) ? r_data : i_data;
assign o_valid = (r_valid) ? r_valid : i_valid;

// Storage reg
always@(posedge clk or posedge reset)
begin
    if(reset == 1'b1)
    begin
        r_valid <= INIT;
        r_data  <= INIT_VAL;
    end
    else if (i_init) 
    begin
        r_valid <= INIT;
        r_data  <= INIT_VAL;
    end
    else
    begin
        if (~r_valid) r_data <= i_data;
        r_valid <= i_stall && (r_valid || i_valid);
    end
end

endmodule

//===----------------------------------------------------------------------===//
//
// Avalon Streaming Read Unit
//
//===----------------------------------------------------------------------===//
module st_read (
        clock,
        resetn,
        i_init,

        // input stream from kernel pipeline
        // this triggers the read request from the fifo
        i_predicate,
        i_valid,
        o_stall,

        // downstream (ouput), to kernel pipeline
        o_valid,
        i_stall,
        o_data,
	o_datavalid, // used only in non-blocking case
        o_startofpacket, // used only in packet case
        o_endofpacket,   // used only in packet case

        // input data from inter kernel pipeline
        i_fifodata,
        i_fifovalid,
        o_fifoready,
        i_fifosize,
        i_fifostartofpacket, // used only in packet case
        i_fifoendofpacket,   // used only in packet case

        // profiler
        profile_i_valid,
        profile_i_stall,
        profile_o_stall,
        profile_total_req,
        profile_fifo_stall,
        profile_total_fifo_size, profile_total_fifo_size_incr
        );

parameter DATA_WIDTH = 32;
parameter INIT = 0;
parameter INIT_VAL = 64'h0000000000000000;
parameter NON_BLOCKING = 0;
parameter FIFOSIZE_WIDTH=32;

parameter ACL_PROFILE=0;      // Set to 1 to enable stall/valid profiling
parameter ACL_PROFILE_INCREMENT_WIDTH=32;

input clock, resetn, i_stall, i_valid, i_fifovalid;
// init reinitializes the init fifo
input i_init;
output o_stall, o_valid, o_fifoready;
input i_predicate;
output o_datavalid;
output [DATA_WIDTH-1:0] o_data;
input [DATA_WIDTH-1:0] i_fifodata;
input [FIFOSIZE_WIDTH-1:0] i_fifosize;
input i_fifostartofpacket;
input i_fifoendofpacket;
output o_startofpacket;
output o_endofpacket;

// profiler
output profile_i_valid;
output profile_i_stall;
output profile_o_stall;
output profile_total_req;
output profile_fifo_stall;
output profile_total_fifo_size;
output [ACL_PROFILE_INCREMENT_WIDTH-1:0] profile_total_fifo_size_incr;

wire non_blocking = (NON_BLOCKING == 1) ? 1'b1 : 1'b0;

wire feedback_downstream, data_downstream;
wire nop = i_predicate;

wire initvalid;
wire initready;

assign feedback_downstream = i_valid & ~nop & initvalid;
assign data_downstream = i_valid & nop;
assign o_datavalid = feedback_downstream;

wire init_reset;
wire r_o_stall;
wire init_val;

generate
if ( INIT ) begin
assign init_reset = ~resetn;
assign init_val   = i_init;

init_reg
  #( .WIDTH    ( DATA_WIDTH + 2 ),
     .INIT     ( INIT     ),
     .INIT_VAL ( {2'b00, INIT_VAL} ) )
reg_data ( 
      .clk     ( clock ),
      .reset   ( init_reset ),
      .i_init  ( init_val   ),
      .i_data  ( {i_fifostartofpacket, i_fifoendofpacket, i_fifodata} ),
      .i_valid ( i_fifovalid ), 
      .o_valid ( initvalid ),
      .o_data  ( {o_startofpacket, o_endofpacket, o_data} ),
      .o_stall ( r_o_stall ),
      .i_stall ( ~initready ) 
      );
end
else begin

assign o_data = i_fifodata;
assign initvalid = i_fifovalid;
assign r_o_stall = ~initready;
assign o_startofpacket = i_fifostartofpacket;
assign o_endofpacket = i_fifoendofpacket;
end
endgenerate

assign o_fifoready = ~r_o_stall;

assign o_valid = feedback_downstream | data_downstream | ( i_valid & non_blocking );

// assign o_data = i_fifodata ;

// stall upstream if
//   downstream is stalling (i_stall)
//   I'm waiting for data from fifo, don't stall if this read is
//   predicated
assign o_stall = ( i_valid & ~nop & ~initvalid & ~non_blocking) | i_stall;

// don't accept data if:
//  downstream cannot accept data (i_stall)
//  data from upstream is selected (data_downstream)
//  no thread exists to read data (~i_valid)
// TODO: I should never set o_fifoready is this is
//       a fifo peek operation
assign initready = ~(i_stall  | data_downstream | ~i_valid); 



generate
if(ACL_PROFILE==1)
begin
  assign profile_i_valid = ( i_valid & ~o_stall );
  assign profile_i_stall = ( o_valid & i_stall );
  assign profile_o_stall = ( i_valid & o_stall );
  assign profile_total_req = ( i_valid & ~o_stall & ~nop );
  assign profile_fifo_stall = ( i_valid & ~nop & ~initvalid );

  // use fifosize value when we actually receive the data
  assign profile_total_fifo_size = ( i_fifovalid & o_fifoready );
  assign profile_total_fifo_size_incr = i_fifosize;
end
else
begin
  assign profile_i_valid = 1'b0;
  assign profile_i_stall = 1'b0;
  assign profile_o_stall = 1'b0;
  assign profile_total_req = 1'b0;
  assign profile_fifo_stall = 1'b0;
  assign profile_total_fifo_size = 1'b0;
  assign profile_total_fifo_size_incr = {ACL_PROFILE_INCREMENT_WIDTH{1'b0}};
end
endgenerate

endmodule

//===----------------------------------------------------------------------===//
//
// Avalon Streaming Write Unit
// downstream are signals that continue into our "normal" pipeline.
//
//===----------------------------------------------------------------------===//
module st_write (
        clock,
        resetn,

        // interface from kernel pipeline, input stream
        i_predicate,
        i_data,
        i_valid,
        o_stall,
        i_startofpacket, // used only in packet case
        i_endofpacket,   // used only in packet case

        // interface to kernel pipeline, downstream
        o_valid,
	o_ack,
        i_stall,
        // data_out,

        // interface to kernel channel fifo, avalon master
        o_fifodata,
        o_fifovalid,
        i_fifoready,
        i_fifosize,
        o_fifostartofpacket, // used only in packet case
        o_fifoendofpacket,   // used only in packet case

        // profiler
        profile_i_valid,
        profile_i_stall,
        profile_o_stall,
        profile_total_req,
        profile_fifo_stall,
        profile_total_fifo_size, profile_total_fifo_size_incr
        );

parameter DATA_WIDTH = 32;
parameter NON_BLOCKING = 0;
parameter FIFOSIZE_WIDTH=32;
parameter EFI_LATENCY = 1;
parameter ENABLED = 0;

// When enabled, the o_valid signal is determined by o_ack signal.
// This is appropriate when multiple channel writes may access the same channel.
// Please notice that parameter can only be used in a single threaded execution context.
// This has never been tested in multiple threaded execution context.
parameter ACK_AS_VALID = 0;

// Delay the ready signal by the specified number of cycles
//
// This allows the channel fifo side to have a non-zero Ready-Latency (RL)
// while keeping the kernel pipeline side at RL = 0.
//
parameter DELAY_READY = 0;

parameter ACL_PROFILE=0;      // Set to 1 to enable stall/valid profiling
parameter ACL_PROFILE_INCREMENT_WIDTH=32;

input clock, resetn, i_stall, i_valid, i_fifoready;
output o_stall, o_valid, o_fifovalid;
input [DATA_WIDTH-1:0] i_data;
input i_startofpacket;
input i_endofpacket;
input i_predicate;
output [DATA_WIDTH-1:0] o_fifodata;
output o_ack;
input [FIFOSIZE_WIDTH-1:0] i_fifosize;
output o_fifostartofpacket;
output o_fifoendofpacket;

// profiler
output profile_i_valid;
output profile_i_stall;
output profile_o_stall;
output profile_total_req;
output profile_fifo_stall;
output profile_total_fifo_size;
output [ACL_PROFILE_INCREMENT_WIDTH-1:0] profile_total_fifo_size_incr;

wire non_blocking = (NON_BLOCKING == 1) ? 1'b1 : 1'b0;

wire nop;
assign nop = i_predicate;

wire fifo_stall;

//////////////////////////////////////////////////////////////////////////////
// a shift register that delays the fifoready signal
//////////////////////////////////////////////////////////////////////////////

wire delayed_fifoready;

generate

if (DELAY_READY == 0) begin

  assign delayed_fifoready = i_fifoready;

end else begin

  // shift left
  reg [DELAY_READY-1:0] fifoready_sr;

  assign delayed_fifoready = fifoready_sr[DELAY_READY-1];

  always @(posedge clock or negedge resetn) begin
    if (!resetn) begin
      fifoready_sr <= {DELAY_READY{1'b0}};
    end else begin
      if (DELAY_READY == 1) begin
        fifoready_sr <= i_fifoready;
      end else begin
        fifoready_sr <= {fifoready_sr[DELAY_READY-2:0], i_fifoready};
      end
    end
  end

end

endgenerate


reg consumed_downstream, consumed_sidepath;

wire stall_contribution_downstream, stall_contribution_sidepath;

generate 
if (EFI_LATENCY == 0) begin

  // if latency is 0 - this will create a combinational cycle with
  // the stall-valid logic since I
  // connect directly to the EFI st_read as will the 
  // efi_module path.
  // efi_st_write-> efi_mod
  //       ^           |
  //       |           |
  // efi_st_read <-----|
  //
  // This modification breaks
  // the cycle and works because the fifo path will stall back
  // appropriately if the st_read is being stalled (i.e. I don't have
  // to check the pipeline stall for o_stall).
  // efi_st_write-> efi_mod
  //                   |
  //                   |
  // efi_st_read <-----|
  assign o_valid       = i_valid;
  assign o_stall       = (nop & i_stall) | ( (fifo_stall & (~nop) & i_valid & !non_blocking) );
  assign o_fifovalid   = i_valid & ~nop;

end else if (NON_BLOCKING) begin
  
  assign o_valid     = i_valid;
  assign o_stall     = i_stall;
  assign o_fifovalid = i_valid & ~nop & ~i_stall;

end else begin
  // For blocking write, we generate different IP if multiple call
  // sites exist (ACK_AS_VALID = 1).
  // Terminologies:
  // *downstream: the direction kernel/component execution flow moves to
  //              stall/valid signals pairs are i_stall/o_valid
  // *side path: the direction FIFO data moves to
  //             stall/valid signals pairs are delayed_fifoready/o_fifovalid
  // *single/multiple call site(s): One/more than one write access point(s) in a
  //                                single OpenCL Kernel/HLS component
  //
  // Case 1: single call site version (ACK_AS_VALID = 0)
  // 2 consumed registers are designed to allow a single thread
  // to make progress on one path but not the other:
  // -- (register)consumed_downstream: mark the status of downstream went ahead of side path,
  //                                   in this status, current thread is allowed to make progress
  //                                   on the side path, not downstream.
  // -- (register)consumed_sidepath: mark the status of side path went ahead of downstream,
  //                                 in this status, current thread is allowed to make progress
  //                                 on the downstream, not side path.
  // -- stall_contribution_downstream: current thread is making progress on downstream in this cycle
  //                                   or has made progress in previous cycles
  // -- stall_contribution_sidepath: current thread is making progress on side path in this cycle
  //                                   or has made progress in previous cycles
  // -- o_stall: In single thread context, st_write will stall upstream if at least one side is stalled.
  // These designs together make sure the IP has capacity 1 and only allow a single
  // thread to make progress on one path but not the other.
  //
  // Case 2: multiple call site version (ACK_AS_VALID = 1)
  // The execution model of multiple call sites is that all call sites will be ordered in CPU
  // single thread model, which means the order of execution is fixed
  // Current mechanism in compiler to ensure the order:
  // 1. Multiple call sites to the same FIFO share the FIFO access port using a simple
  //    arbitration logic with no back-pressure functionality
  // 2. Every call sites has to make sure: downstream can only make progress if a write (or read)
  //    operation is committed (or guaranteed to happen in a cycle). In this way, it prevents itself from
  //    being in a data race condition with other call sites in downstream.
  // 3. In compiler, the section where multiple call sites' accesses to FIFO is allowed is
  //    marked as a single threaded section.
  // The current implementation of IP reuses the design of single call sites with one tweak:
  // -- consumed_downstream: should never be turned on since we only allow side path go ahead
  //    of downstream.
  
  if(ENABLED) begin
  
  always @(posedge clock or negedge resetn) begin
    if(!resetn) begin
      consumed_downstream <= 1'b0;
      consumed_sidepath   <= 1'b0;
    end else begin
      if(~i_stall) begin
        consumed_downstream <= stall_contribution_downstream & o_stall;
        consumed_sidepath   <= stall_contribution_sidepath & o_stall;
      end
    end
  end

  end else begin
    
  always @(posedge clock or negedge resetn) begin
    if(!resetn) begin
      consumed_downstream <= 1'b0;
      consumed_sidepath   <= 1'b0;
    end else begin
      consumed_downstream <= stall_contribution_downstream & o_stall;
      consumed_sidepath   <= stall_contribution_sidepath & o_stall;
    end
  end

  end
  // use o_ack signal as o_valid in multiple call site case:
  // in multiple call sites case, down stream flow may have another
  // channel write site access the same FIFO, that call site has to
  // wait untill this call site "commit" writing data to the FIFO (o_ack)
  if(ACK_AS_VALID) begin
    //ways we can provide a valid to kernel downstream:
    //-we are writing to the channel right now, this is o_ack
    //-when we wrote to the channel kernel downstream stalled us, so we would have turned on consumed_sidepath
    //-the valid was predicated, in which case we would never have looked at the channel
    assign o_valid     = o_ack | (i_valid & nop) | consumed_sidepath;
  end else begin
    assign o_valid     = i_valid & ~consumed_downstream;
  end
  assign o_fifovalid = (i_valid & ~nop) & ~consumed_sidepath;

  if (ACK_AS_VALID) begin
    //we can never allow consumed_downstream to turn on, otherwise this ruins the ordering of multiple write sites writing into the same channel
    assign o_stall = i_stall | (fifo_stall & ~nop); //must stall uptream if downstream is stalling otherwise consumed_downstream would turn on
                                                    //even when downstream is not stalling, we could still be blocked by non-predicated write to a full channel
    assign stall_contribution_downstream = 1'b0;
  end
  else begin
    assign o_stall = ~(stall_contribution_downstream & stall_contribution_sidepath) ;
    assign stall_contribution_downstream = consumed_downstream | (i_valid & ~i_stall);
  end
  assign stall_contribution_sidepath   = consumed_sidepath | (i_valid & ~(~nop & fifo_stall));

end
endgenerate

assign o_ack        = o_fifovalid & delayed_fifoready;


assign fifo_stall = ~delayed_fifoready;
assign o_fifodata = i_data;
assign o_fifostartofpacket = i_startofpacket;
assign o_fifoendofpacket   = i_endofpacket;

generate
if(ACL_PROFILE==1)
begin
  assign profile_i_valid = ( i_valid & ~o_stall );
  assign profile_i_stall = ( o_valid & i_stall );
  assign profile_o_stall = ( i_valid & o_stall );
  assign profile_total_req = ( i_valid & ~o_stall & ~nop );
  assign profile_fifo_stall = (fifo_stall & (~nop) & i_valid) ;

  // use fifosize value when we actually send the data
  assign profile_total_fifo_size = ( o_fifovalid & i_fifoready );
  assign profile_total_fifo_size_incr = i_fifosize;
end
else
begin
  assign profile_i_valid = 1'b0;
  assign profile_i_stall = 1'b0;
  assign profile_o_stall = 1'b0;
  assign profile_total_req = 1'b0;
  assign profile_fifo_stall = 1'b0;
  assign profile_total_fifo_size = 1'b0;
  assign profile_total_fifo_size_incr = {ACL_PROFILE_INCREMENT_WIDTH{1'b0}};
end
endgenerate

endmodule

// vim:set filetype=verilog:

