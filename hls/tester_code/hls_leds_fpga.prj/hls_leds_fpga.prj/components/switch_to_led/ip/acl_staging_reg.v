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


// acl_staging_reg.v
//
// Module to implement a staging register.  Used to pipeline stall signals.
//

module acl_staging_reg
(
    clk, reset, i_data, i_valid, o_stall, o_data, o_valid, i_stall
);

/*************
* Parameters *
*************/
parameter WIDTH=32;

/********
* Ports *
********/
// Standard global signals
input clk;
input reset;

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
        r_valid <= 1'b0;
        r_data <= 'x;   // don't need to reset
    end
    else
    begin
        if (~r_valid) r_data <= i_data;
        r_valid <= i_stall && (r_valid || i_valid);
    end
end

endmodule
