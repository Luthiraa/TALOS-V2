module de1_soc_hls_leds (
    input  wire       CLOCK_50,
    input  wire [1:0] KEY,
    output wire [9:0] LEDR,
    output wire [6:0] HEX0,
    output wire [6:0] HEX1,
    output wire [6:0] HEX2,
    output wire [6:0] HEX3,
    output wire [6:0] HEX4,
    output wire [6:0] HEX5,
    output wire       UART_TXD
);

localparam integer DEBOUNCE_CLKS = 20'd500_000;
localparam integer MSG_LEN = 18;

reg [3:0]  reset_pipe = 4'b0000;
reg [1:0]  key_meta = 2'b11;
reg [1:0]  key_sync = 2'b11;
reg [1:0]  key_stable = 2'b11;
reg [19:0] debounce_count [0:1];

reg        start_reg = 1'b0;
reg        waiting_for_done = 1'b0;
reg        button_reg = 1'b1;
reg        reset_button_reg = 1'b1;

reg [31:0] count_reg = 32'd0;
reg [31:0] last_sent_count = 32'd0;
reg [31:0] pending_count = 32'd0;
reg        message_pending = 1'b0;

reg [4:0]  msg_index = 5'd0;
reg        uart_valid = 1'b0;
reg [7:0]  uart_data = 8'd0;
reg [7:0]  msg_mem [0:MSG_LEN-1];

wire       resetn;
wire       busy;
wire       done;
wire [31:0] returndata;
wire       uart_ready;
wire [31:0] jtag_source_unused;
genvar     jtag_idx;
integer    key_idx;

assign resetn = reset_pipe[3];
assign LEDR = count_reg[9:0];
assign HEX0 = hex7seg(count_reg[3:0]);
assign HEX1 = hex7seg(count_reg[7:4]);
assign HEX2 = hex7seg(count_reg[11:8]);
assign HEX3 = hex7seg(count_reg[15:12]);
assign HEX4 = hex7seg(count_reg[19:16]);
assign HEX5 = hex7seg(count_reg[23:20]);

function [7:0] hex_ascii;
    input [3:0] nibble;
    begin
        case (nibble)
            4'h0: hex_ascii = "0";
            4'h1: hex_ascii = "1";
            4'h2: hex_ascii = "2";
            4'h3: hex_ascii = "3";
            4'h4: hex_ascii = "4";
            4'h5: hex_ascii = "5";
            4'h6: hex_ascii = "6";
            4'h7: hex_ascii = "7";
            4'h8: hex_ascii = "8";
            4'h9: hex_ascii = "9";
            4'hA: hex_ascii = "A";
            4'hB: hex_ascii = "B";
            4'hC: hex_ascii = "C";
            4'hD: hex_ascii = "D";
            4'hE: hex_ascii = "E";
            default: hex_ascii = "F";
        endcase
    end
endfunction

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

task load_message;
    input [31:0] value;
    begin
        msg_mem[0]  = "c";
        msg_mem[1]  = "o";
        msg_mem[2]  = "u";
        msg_mem[3]  = "n";
        msg_mem[4]  = "t";
        msg_mem[5]  = "=";
        msg_mem[6]  = "0";
        msg_mem[7]  = "x";
        msg_mem[8]  = hex_ascii(value[31:28]);
        msg_mem[9]  = hex_ascii(value[27:24]);
        msg_mem[10] = hex_ascii(value[23:20]);
        msg_mem[11] = hex_ascii(value[19:16]);
        msg_mem[12] = hex_ascii(value[15:12]);
        msg_mem[13] = hex_ascii(value[11:8]);
        msg_mem[14] = hex_ascii(value[7:4]);
        msg_mem[15] = hex_ascii(value[3:0]);
        msg_mem[16] = 8'h0D;
        msg_mem[17] = 8'h0A;
    end
endtask

always @(posedge CLOCK_50) begin
    reset_pipe <= {reset_pipe[2:0], 1'b1};
    key_meta <= KEY;
    key_sync <= key_meta;

    if (!resetn) begin
        key_stable <= 2'b11;
        debounce_count[0] <= 20'd0;
        debounce_count[1] <= 20'd0;
        start_reg <= 1'b0;
        waiting_for_done <= 1'b0;
        button_reg <= 1'b1;
        reset_button_reg <= 1'b1;
        count_reg <= 32'd0;
        last_sent_count <= 32'd0;
        pending_count <= 32'd0;
        message_pending <= 1'b0;
        msg_index <= 5'd0;
        uart_valid <= 1'b0;
        uart_data <= 8'd0;
    end else begin
        start_reg <= 1'b0;
        uart_valid <= 1'b0;

        for (key_idx = 0; key_idx < 2; key_idx = key_idx + 1) begin
            if (key_sync[key_idx] == key_stable[key_idx]) begin
                debounce_count[key_idx] <= 20'd0;
            end else if (debounce_count[key_idx] == DEBOUNCE_CLKS - 1) begin
                key_stable[key_idx] <= key_sync[key_idx];
                debounce_count[key_idx] <= 20'd0;
            end else begin
                debounce_count[key_idx] <= debounce_count[key_idx] + 20'd1;
            end
        end

        if (!waiting_for_done && !busy) begin
            button_reg <= key_stable[0];
            reset_button_reg <= key_stable[1];
            start_reg <= 1'b1;
            waiting_for_done <= 1'b1;
        end

        if (done) begin
            count_reg <= returndata;
            waiting_for_done <= 1'b0;

            if (returndata != last_sent_count) begin
                pending_count <= returndata;
                message_pending <= 1'b1;
            end
        end

        if (message_pending && (msg_index == 0) && uart_ready) begin
            load_message(pending_count);
            last_sent_count <= pending_count;
            message_pending <= 1'b0;
            uart_data <= msg_mem[0];
            uart_valid <= 1'b1;
            msg_index <= 5'd1;
        end else if ((msg_index != 0) && uart_ready) begin
            uart_data <= msg_mem[msg_index];
            uart_valid <= 1'b1;

            if (msg_index == MSG_LEN - 1) begin
                msg_index <= 5'd0;
            end else begin
                msg_index <= msg_index + 5'd1;
            end
        end
    end
end

switch_to_led switch_to_led_inst (
    .clock(CLOCK_50),
    .resetn(resetn),
    .start(start_reg),
    .busy(busy),
    .done(done),
    .stall(1'b0),
    .returndata(returndata),
    .button_n(button_reg),
    .reset_button_n(reset_button_reg)
);

uart_tx #(
    .CLKS_PER_BIT(434)
) uart_tx_inst (
    .clk(CLOCK_50),
    .resetn(resetn),
    .data(uart_data),
    .valid(uart_valid),
    .ready(uart_ready),
    .txd(UART_TXD)
);

generate
    for (jtag_idx = 0; jtag_idx < 32; jtag_idx = jtag_idx + 1) begin : jtag_count_probe_bits
        altsource_probe jtag_count_probe (
            .probe(count_reg[jtag_idx]),
            .source(jtag_source_unused[jtag_idx]),
            .source_clk(CLOCK_50),
            .source_ena(1'b1)
        );

        defparam jtag_count_probe.instance_id = "CNTBIT";
        defparam jtag_count_probe.probe_width = 1;
        defparam jtag_count_probe.source_width = 1;
        defparam jtag_count_probe.source_initial_value = "0";
        defparam jtag_count_probe.enable_metastability = "NO";
        defparam jtag_count_probe.sld_auto_instance_index = "YES";
    end
endgenerate

endmodule

module uart_tx #(
    parameter integer CLKS_PER_BIT = 434
) (
    input  wire      clk,
    input  wire      resetn,
    input  wire [7:0] data,
    input  wire      valid,
    output wire      ready,
    output reg       txd
);

reg [8:0] shifter = 9'h1FF;
reg [15:0] baud_count = 16'd0;
reg [3:0] bit_count = 4'd0;
reg        active = 1'b0;

assign ready = !active;

always @(posedge clk) begin
    if (!resetn) begin
        shifter <= 9'h1FF;
        baud_count <= 16'd0;
        bit_count <= 4'd0;
        active <= 1'b0;
        txd <= 1'b1;
    end else if (!active) begin
        txd <= 1'b1;
        baud_count <= 16'd0;
        bit_count <= 4'd0;

        if (valid) begin
            shifter <= {1'b1, data};
            active <= 1'b1;
            txd <= 1'b0;
        end
    end else if (baud_count == CLKS_PER_BIT - 1) begin
        baud_count <= 16'd0;

        if (bit_count == 4'd8) begin
            txd <= 1'b1;
            active <= 1'b0;
            bit_count <= 4'd0;
        end else begin
            txd <= shifter[bit_count];
            bit_count <= bit_count + 4'd1;
        end
    end else begin
        baud_count <= baud_count + 16'd1;
    end
end

endmodule
