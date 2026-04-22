module de1_soc_microgpt_rtl (
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

localparam [7:0] BOS_TOKEN = 8'd26;
localparam [2:0] ST_READY = 3'd0;
localparam [2:0] ST_WAIT_CORE = 3'd1;
localparam [2:0] ST_DONE = 3'd2;

reg [6:0] clkdiv;
wire clk = clkdiv[6];
wire resetn = ~SW[1];
wire enable = SW[0];

reg [2:0] state_reg;
reg [7:0] token_reg;
reg [7:0] pos_reg;
reg [7:0] out_len_reg;
reg [31:0] rng_reg;
reg start_core_reg;
reg clear_cache_reg;
reg key0_prev;
reg done_latched_reg;
reg [7:0] last_token_reg;
reg [15:0] cycle_blink_reg;

wire core_busy;
wire core_done;
wire [7:0] core_next_token;
wire [7:0] core_argmax_token;
wire [31:0] core_rng_state;
wire signed [15:0] core_top_logit;

always @(posedge CLOCK_50) begin
    if (!resetn)
        clkdiv <= 7'd0;
    else
        clkdiv <= clkdiv + 7'd1;
end

microgpt_exact_core core_inst (
    .clk(clk),
    .resetn(resetn),
    .start(start_core_reg),
    .clear_cache(clear_cache_reg),
    .sample_mode(1'b1),
    .temperature_q8_8(16'h0080),
    .rng_state_in(rng_reg),
    .token_in(token_reg),
    .pos_in(pos_reg),
    .busy(core_busy),
    .done(core_done),
    .next_token(core_next_token),
    .argmax_token(core_argmax_token),
    .rng_state_out(core_rng_state),
    .top_logit_q12(core_top_logit)
);

always @(posedge clk) begin
    if (!resetn) begin
        state_reg <= ST_READY;
        token_reg <= BOS_TOKEN;
        pos_reg <= 8'd0;
        out_len_reg <= 8'd0;
        rng_reg <= 32'h00000001;
        start_core_reg <= 1'b0;
        clear_cache_reg <= 1'b0;
        key0_prev <= 1'b1;
        done_latched_reg <= 1'b0;
        last_token_reg <= 8'd0;
        cycle_blink_reg <= 16'd0;
    end else begin
        start_core_reg <= 1'b0;
        clear_cache_reg <= 1'b0;
        key0_prev <= KEY[0];
        cycle_blink_reg <= cycle_blink_reg + 16'd1;

        if (!enable) begin
            state_reg <= ST_READY;
            token_reg <= BOS_TOKEN;
            pos_reg <= 8'd0;
            out_len_reg <= 8'd0;
            rng_reg <= 32'h00000001;
            done_latched_reg <= 1'b0;
            last_token_reg <= 8'd0;
        end else begin
            case (state_reg)
                ST_READY: begin
                    if (key0_prev && !KEY[0]) begin
                        token_reg <= BOS_TOKEN;
                        pos_reg <= 8'd0;
                        out_len_reg <= 8'd0;
                        rng_reg <= rng_reg + 32'h9E3779B9;
                        done_latched_reg <= 1'b0;
                        last_token_reg <= 8'd0;
                        clear_cache_reg <= 1'b1;
                        start_core_reg <= 1'b1;
                        state_reg <= ST_WAIT_CORE;
                    end
                end

                ST_WAIT_CORE: begin
                    if (core_done) begin
                        rng_reg <= core_rng_state;
                        last_token_reg <= core_next_token;
                        if ((core_next_token == BOS_TOKEN) || (pos_reg == 8'd15)) begin
                            done_latched_reg <= 1'b1;
                            state_reg <= ST_DONE;
                        end else begin
                            token_reg <= core_next_token;
                            pos_reg <= pos_reg + 8'd1;
                            out_len_reg <= out_len_reg + 8'd1;
                            start_core_reg <= 1'b1;
                            state_reg <= ST_WAIT_CORE;
                        end
                    end
                end

                ST_DONE: begin
                    if (key0_prev && !KEY[0]) begin
                        token_reg <= BOS_TOKEN;
                        pos_reg <= 8'd0;
                        out_len_reg <= 8'd0;
                        rng_reg <= rng_reg + 32'h9E3779B9;
                        done_latched_reg <= 1'b0;
                        last_token_reg <= 8'd0;
                        clear_cache_reg <= 1'b1;
                        start_core_reg <= 1'b1;
                        state_reg <= ST_WAIT_CORE;
                    end
                end

                default: state_reg <= ST_READY;
            endcase
        end
    end
end

assign LEDR[0] = enable && (state_reg == ST_READY);
assign LEDR[1] = enable && (state_reg == ST_WAIT_CORE);
assign LEDR[2] = done_latched_reg;
assign LEDR[3] = core_done;
assign LEDR[4] = resetn;
assign LEDR[5] = enable;
assign LEDR[6] = cycle_blink_reg[15] && (state_reg == ST_WAIT_CORE);
assign LEDR[7] = last_token_reg[0];
assign LEDR[8] = last_token_reg[1];
assign LEDR[9] = last_token_reg[2];

assign HEX0 = hex7seg(last_token_reg[3:0]);
assign HEX1 = hex7seg(last_token_reg[7:4]);
assign HEX2 = hex7seg(out_len_reg[3:0]);
assign HEX3 = hex7seg(out_len_reg[7:4]);
assign HEX4 = hex7seg({1'b0, state_reg});
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
