module de1_soc_microgpt (
    input  wire       CLOCK_50,
    input  wire [1:0] KEY,
    input  wire [1:0] SW,
    output wire [9:0] LEDR,
    output wire [6:0] HEX0,
    output wire [6:0] HEX1,
    output wire [6:0] HEX2,
    output wire [6:0] HEX3,
    output wire [6:0] HEX4,
    output wire [6:0] HEX5
);

reg [3:0] reset_pipe = 4'b0000;
wire sys_clk = CLOCK_50;
wire resetn = reset_pipe[3];

wire [31:0] jtag_master_address;
wire        jtag_master_read;
wire [31:0] jtag_master_readdata;
wire        jtag_master_write;
wire [31:0] jtag_master_writedata;
wire [3:0]  jtag_master_byteenable;
wire        jtag_master_waitrequest;
wire        jtag_master_readdatavalid;

wire led_idle;
wire led_busy;
wire led_done;
wire led_host;
wire led_error;
wire [7:0] dbg_out_len;
wire [7:0] dbg_last_token;
wire [3:0] dbg_state;

always @(posedge sys_clk) begin
    reset_pipe <= {reset_pipe[2:0], 1'b1};
end

jtag_microgpt_bridge jtag_bridge_inst (
    .clk_clk(sys_clk),
    .reset_reset_n(resetn),
    .master_address(jtag_master_address),
    .master_read(jtag_master_read),
    .master_readdata(jtag_master_readdata),
    .master_write(jtag_master_write),
    .master_writedata(jtag_master_writedata),
    .master_byteenable(jtag_master_byteenable),
    .master_waitrequest(jtag_master_waitrequest),
    .master_readdatavalid(jtag_master_readdatavalid)
);

microgpt_mmio microgpt_mmio_inst (
    .clk(sys_clk),
    .resetn(resetn),
    .avs_address(jtag_master_address),
    .avs_read(jtag_master_read),
    .avs_write(jtag_master_write),
    .avs_writedata(jtag_master_writedata),
    .avs_byteenable(jtag_master_byteenable),
    .avs_readdata(jtag_master_readdata),
    .avs_readdatavalid(jtag_master_readdatavalid),
    .avs_waitrequest(jtag_master_waitrequest),
    .sw(SW),
    .key_n(KEY),
    .led_idle(led_idle),
    .led_busy(led_busy),
    .led_done(led_done),
    .led_host(led_host),
    .led_error(led_error),
    .dbg_out_len(dbg_out_len),
    .dbg_last_token(dbg_last_token),
    .dbg_state(dbg_state)
);

assign LEDR[0] = led_idle;
assign LEDR[1] = led_busy;
assign LEDR[2] = led_done;
assign LEDR[3] = led_host;
assign LEDR[4] = led_error;
assign LEDR[5] = SW[0];
assign LEDR[6] = SW[1];
assign LEDR[7] = dbg_out_len[0];
assign LEDR[8] = dbg_last_token[0];
assign LEDR[9] = dbg_state[0];

assign HEX0 = hex7seg(dbg_last_token[3:0]);
assign HEX1 = hex7seg(dbg_last_token[7:4]);
assign HEX2 = hex7seg(dbg_out_len[3:0]);
assign HEX3 = hex7seg(dbg_out_len[7:4]);
assign HEX4 = hex7seg({1'b0, dbg_state[2:0]});
assign HEX5 = hex7seg({2'b00, SW});

function [6:0] hex7seg;
    input [3:0] nibble;
    begin
        case (nibble)
            4'h0: hex7seg = 7'b1000000;
            4'h1: hex7seg = 7'b1111001;
            4'h2: hex7seg = 7'b0100100;
            4'h3: hex7seg = 7'b0110000;
            4'h4: hex7seg = 7'b0011001;
            4'h5: hex7seg = 7'b0010010;
            4'h6: hex7seg = 7'b0000010;
            4'h7: hex7seg = 7'b1111000;
            4'h8: hex7seg = 7'b0000000;
            4'h9: hex7seg = 7'b0010000;
            4'hA: hex7seg = 7'b0001000;
            4'hB: hex7seg = 7'b0000011;
            4'hC: hex7seg = 7'b1000110;
            4'hD: hex7seg = 7'b0100001;
            4'hE: hex7seg = 7'b0000110;
            default: hex7seg = 7'b0001110;
        endcase
    end
endfunction

endmodule
