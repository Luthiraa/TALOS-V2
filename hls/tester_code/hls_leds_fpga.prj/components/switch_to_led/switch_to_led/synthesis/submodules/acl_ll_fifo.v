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


// Low latency FIFO
// One cycle latency from all inputs to all outputs
// Storage implemented in registers, not memory.

// altera message_off 10036

module acl_ll_fifo(clk, reset, data_in, write, data_out, read, empty, full, almost_full);

/* Parameters */
parameter WIDTH = 32;
parameter DEPTH = 32;
parameter ALMOST_FULL_VALUE = 0;

/* Ports */
input clk;
input reset;
input [WIDTH-1:0] data_in;
input write;
output [WIDTH-1:0] data_out;
input read;
output empty;
output full;
output almost_full;

/* Architecture */
// One-hot write-pointer bit (indicates next position to write at),
// last bit indicates the FIFO is full
reg [DEPTH:0] wptr;
// Replicated copy of the stall / valid logic
reg [DEPTH:0] wptr_copy /* synthesis dont_merge */;
// FIFO data registers
reg [DEPTH-1:0][WIDTH-1:0] data;

// Write pointer updates:
wire wptr_hold; // Hold the value
wire wptr_dir;  // Direction to shift

// Data register updates:
wire [DEPTH-1:0] data_hold;     // Hold the value
wire [DEPTH-1:0] data_new;      // Write the new data value in

// Write location is constant unless the occupancy changes
assign wptr_hold = !(read ^ write);
assign wptr_dir = read;

// Hold the value unless we are reading, or writing to this
// location
genvar i;
generate
for(i = 0; i < DEPTH; i++)
begin : data_mux
    assign data_hold[i] = !(read | (write & wptr[i]));
    assign data_new[i] = !read | wptr[i+1];
end
endgenerate

// The data registers
generate
for(i = 0; i < DEPTH-1; i++)
begin : data_reg
    always@(posedge clk or posedge reset)
    begin
        if(reset == 1'b1)
            data[i] <= {WIDTH{1'b0}};
        else
            data[i] <= data_hold[i] ? data[i] : 
                       data_new[i] ? data_in : data[i+1];
    end
end
endgenerate
always@(posedge clk or posedge reset)
begin
    if(reset == 1'b1)
        data[DEPTH-1] <= {WIDTH{1'b0}};
    else
        data[DEPTH-1] <= data_hold[DEPTH-1] ? data[DEPTH-1] : data_in;
end

// The write pointer
always@(posedge clk or posedge reset)
begin
    if(reset == 1'b1)
    begin
        wptr <= {{DEPTH{1'b0}}, 1'b1};
        wptr_copy <= {{DEPTH{1'b0}}, 1'b1};
    end
    else
    begin
        wptr <= wptr_hold ? wptr : 
                wptr_dir ? {1'b0, wptr[DEPTH:1]} : {wptr[DEPTH-1:0], 1'b0};

        wptr_copy <= wptr_hold ? wptr_copy : 
                wptr_dir ? {1'b0, wptr_copy[DEPTH:1]} : {wptr_copy[DEPTH-1:0], 1'b0};
    end
end

// Outputs
assign empty = wptr_copy[0];
assign full = wptr_copy[DEPTH];
assign almost_full = |wptr_copy[DEPTH:ALMOST_FULL_VALUE];
assign data_out = data[0];

endmodule

