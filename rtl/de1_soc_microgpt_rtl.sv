module de1_soc_microgpt_rtl (
    input  wire       CLOCK_50,
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
localparam [31:0] CORE_CLOCK_HZ = 32'd390625;

reg [6:0] clkdiv = 7'd0;
wire clk = clkdiv[6];
wire resetn = ~SW[1];
wire enable = SW[0];

reg [2:0] state_reg = ST_READY;
reg [7:0] token_reg = BOS_TOKEN;
reg [7:0] pos_reg = 8'd0;
reg [7:0] out_len_reg = 8'd0;
reg [31:0] rng_reg = 32'h00000001;
reg [15:0] temperature_reg = 16'h0080;
reg [7:0] max_gen_reg = 8'd15;
reg start_core_reg = 1'b0;
reg clear_cache_reg = 1'b0;
reg done_latched_reg = 1'b0;
reg [7:0] last_token_reg = 8'd0;
reg [15:0] cycle_blink_reg = 16'd0;
reg [7:0] output_mem [0:15];
reg [31:0] perf_cycles_reg = 32'd0;
reg [31:0] tokens_per_sec_reg = 32'd0;
reg host_toggle_reg = 1'b0;
reg error_reg = 1'b0;
reg host_start_req = 1'b0;
reg host_clear_req = 1'b0;
reg read_pending_reg = 1'b0;
reg host_run_reg = 1'b0;
reg host_start_toggle_50 = 1'b0;
reg host_clear_toggle_50 = 1'b0;
reg [31:0] host_seed_reg = 32'h00000001;
reg [15:0] host_temperature_reg = 16'h0080;
reg [7:0] host_max_gen_reg = 8'd15;
reg start_sync0 = 1'b0;
reg start_sync1 = 1'b0;
reg start_seen_reg = 1'b0;
reg clear_sync0 = 1'b0;
reg clear_sync1 = 1'b0;
reg clear_seen_reg = 1'b0;

wire [31:0] jtag_master_address;
wire        jtag_master_read;
reg  [31:0] jtag_master_readdata = 32'd0;
wire        jtag_master_write;
wire [31:0] jtag_master_writedata;
wire        jtag_master_waitrequest;
reg         jtag_master_readdatavalid = 1'b0;
wire [3:0]  jtag_master_byteenable;

wire core_busy;
wire core_done;
wire [7:0] core_next_token;
wire [7:0] core_argmax_token;
wire [31:0] core_rng_state;
wire signed [15:0] core_top_logit;
wire [9:0] jtag_word_addr;

integer out_i;

assign jtag_master_waitrequest = 1'b0;
assign jtag_word_addr = jtag_master_address[11:2];

jtag_microgpt_bridge jtag_bridge_inst (
    .clk_clk(CLOCK_50),
    .reset_reset_n(1'b1),
    .master_address(jtag_master_address),
    .master_readdata(jtag_master_readdata),
    .master_read(jtag_master_read),
    .master_write(jtag_master_write),
    .master_writedata(jtag_master_writedata),
    .master_waitrequest(jtag_master_waitrequest),
    .master_readdatavalid(jtag_master_readdatavalid),
    .master_byteenable(jtag_master_byteenable)
);

always @(posedge CLOCK_50) begin
    clkdiv <= clkdiv + 7'd1;
end

always @(posedge CLOCK_50) begin
    jtag_master_readdatavalid <= 1'b0;

    if (read_pending_reg) begin
        jtag_master_readdatavalid <= 1'b1;
        read_pending_reg <= 1'b0;
    end else if (jtag_master_read) begin
        jtag_master_readdata <= read_data_comb;
        read_pending_reg <= 1'b1;
        host_toggle_reg <= ~host_toggle_reg;
    end

    if (jtag_master_write) begin
        host_toggle_reg <= ~host_toggle_reg;
        case (jtag_word_addr)
            10'h002: begin
                if (jtag_master_writedata[0])
                    host_start_toggle_50 <= ~host_start_toggle_50;
                if (jtag_master_writedata[1])
                    host_clear_toggle_50 <= ~host_clear_toggle_50;
            end
            10'h004: begin
                host_max_gen_reg <= jtag_master_writedata[15:8];
                host_temperature_reg <= jtag_master_writedata[31:16];
            end
            10'h005: begin
                host_seed_reg <= jtag_master_writedata;
            end
            default: begin
            end
        endcase
    end
end

microgpt_exact_core core_inst (
    .clk(clk),
    .resetn(resetn),
    .start(start_core_reg),
    .clear_cache(clear_cache_reg),
    .sample_mode(1'b1),
    .temperature_q8_8(temperature_reg),
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
        rng_reg <= host_seed_reg;
        temperature_reg <= host_temperature_reg;
        max_gen_reg <= host_max_gen_reg;
        start_core_reg <= 1'b0;
        clear_cache_reg <= 1'b0;
        done_latched_reg <= 1'b0;
        last_token_reg <= 8'd0;
        cycle_blink_reg <= 16'd0;
        perf_cycles_reg <= 32'd0;
        tokens_per_sec_reg <= 32'd0;
        error_reg <= 1'b0;
        host_start_req <= 1'b0;
        host_clear_req <= 1'b0;
        host_run_reg <= 1'b0;
        start_sync0 <= host_start_toggle_50;
        start_sync1 <= host_start_toggle_50;
        start_seen_reg <= host_start_toggle_50;
        clear_sync0 <= host_clear_toggle_50;
        clear_sync1 <= host_clear_toggle_50;
        clear_seen_reg <= host_clear_toggle_50;
        for (out_i = 0; out_i < 16; out_i = out_i + 1) begin
            output_mem[out_i] <= 8'd0;
        end
    end else begin
        start_core_reg <= 1'b0;
        clear_cache_reg <= 1'b0;
        cycle_blink_reg <= cycle_blink_reg + 16'd1;

        start_sync0 <= host_start_toggle_50;
        start_sync1 <= start_sync0;
        clear_sync0 <= host_clear_toggle_50;
        clear_sync1 <= clear_sync0;

        if (start_sync1 != start_seen_reg) begin
            host_start_req <= 1'b1;
            host_run_reg <= 1'b1;
            start_seen_reg <= start_sync1;
            max_gen_reg <= host_max_gen_reg;
            temperature_reg <= host_temperature_reg;
            rng_reg <= host_seed_reg;
        end

        if (clear_sync1 != clear_seen_reg) begin
            host_clear_req <= 1'b1;
            clear_seen_reg <= clear_sync1;
        end

        if (state_reg == ST_WAIT_CORE)
            perf_cycles_reg <= perf_cycles_reg + 32'd1;

        if (host_clear_req) begin
            state_reg <= ST_READY;
            token_reg <= BOS_TOKEN;
            pos_reg <= 8'd0;
            out_len_reg <= 8'd0;
            done_latched_reg <= 1'b0;
            last_token_reg <= 8'd0;
            perf_cycles_reg <= 32'd0;
            tokens_per_sec_reg <= 32'd0;
            error_reg <= 1'b0;
            host_clear_req <= 1'b0;
            host_run_reg <= 1'b0;
            for (out_i = 0; out_i < 16; out_i = out_i + 1) begin
                output_mem[out_i] <= 8'd0;
            end
        end else if (!enable && !host_run_reg) begin
            state_reg <= ST_READY;
            token_reg <= BOS_TOKEN;
            pos_reg <= 8'd0;
            out_len_reg <= 8'd0;
            done_latched_reg <= 1'b0;
            last_token_reg <= 8'd0;
        end else begin
            case (state_reg)
                ST_READY: begin
                    if (host_start_req) begin
                        token_reg <= BOS_TOKEN;
                        pos_reg <= 8'd0;
                        out_len_reg <= 8'd0;
                        done_latched_reg <= 1'b0;
                        last_token_reg <= 8'd0;
                        perf_cycles_reg <= 32'd0;
                        tokens_per_sec_reg <= 32'd0;
                        error_reg <= 1'b0;
                        for (out_i = 0; out_i < 16; out_i = out_i + 1) begin
                            output_mem[out_i] <= 8'd0;
                        end
                        clear_cache_reg <= 1'b1;
                        if (max_gen_reg == 8'd0 || max_gen_reg > 8'd15) begin
                            error_reg <= 1'b1;
                            done_latched_reg <= 1'b1;
                            state_reg <= ST_DONE;
                        end else begin
                            start_core_reg <= 1'b1;
                            state_reg <= ST_WAIT_CORE;
                        end
                        host_start_req <= 1'b0;
                    end
                end

                ST_WAIT_CORE: begin
                    if (core_done) begin
                        rng_reg <= core_rng_state;
                        last_token_reg <= core_next_token;
                        if ((core_next_token == BOS_TOKEN) || (pos_reg == 8'd15)) begin
                            done_latched_reg <= 1'b1;
                            if (perf_cycles_reg != 32'd0)
                                tokens_per_sec_reg <= (out_len_reg * CORE_CLOCK_HZ) / perf_cycles_reg;
                            state_reg <= ST_DONE;
                        end else begin
                            output_mem[out_len_reg] <= core_next_token;
                            token_reg <= core_next_token;
                            pos_reg <= pos_reg + 8'd1;
                            out_len_reg <= out_len_reg + 8'd1;
                            if ((out_len_reg + 8'd1) >= max_gen_reg) begin
                                done_latched_reg <= 1'b1;
                                if (perf_cycles_reg != 32'd0)
                                    tokens_per_sec_reg <= ((out_len_reg + 8'd1) * CORE_CLOCK_HZ) / perf_cycles_reg;
                                state_reg <= ST_DONE;
                            end else begin
                                start_core_reg <= 1'b1;
                                state_reg <= ST_WAIT_CORE;
                            end
                        end
                    end
                end

                ST_DONE: begin
                    if (host_start_req) begin
                        token_reg <= BOS_TOKEN;
                        pos_reg <= 8'd0;
                        out_len_reg <= 8'd0;
                        done_latched_reg <= 1'b0;
                        last_token_reg <= 8'd0;
                        perf_cycles_reg <= 32'd0;
                        tokens_per_sec_reg <= 32'd0;
                        error_reg <= 1'b0;
                        for (out_i = 0; out_i < 16; out_i = out_i + 1) begin
                            output_mem[out_i] <= 8'd0;
                        end
                        clear_cache_reg <= 1'b1;
                        if (max_gen_reg == 8'd0 || max_gen_reg > 8'd15) begin
                            error_reg <= 1'b1;
                            done_latched_reg <= 1'b1;
                            state_reg <= ST_DONE;
                        end else begin
                            start_core_reg <= 1'b1;
                            state_reg <= ST_WAIT_CORE;
                        end
                        host_start_req <= 1'b0;
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
assign LEDR[3] = host_toggle_reg;
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

reg [31:0] read_data_comb;

always @(*) begin
    read_data_comb = 32'd0;
    case (jtag_word_addr)
        10'h000: read_data_comb = 32'h4D475254; // MGRT
        10'h001: read_data_comb = 32'h00020000;
        10'h002: read_data_comb = 32'd0;
        10'h003: read_data_comb = {
            pos_reg,
            out_len_reg,
            8'd0,
            3'd0,
            host_toggle_reg,
            error_reg,
            done_latched_reg,
            (state_reg == ST_WAIT_CORE),
            (state_reg == ST_READY)
        };
        10'h004: read_data_comb = {temperature_reg, max_gen_reg, 8'd0};
        10'h005: read_data_comb = rng_reg;
        10'h006: read_data_comb = {core_top_logit[15:0], core_argmax_token, last_token_reg};
        10'h007: read_data_comb = {16'd0, 8'd0, BOS_TOKEN};
        10'h036: read_data_comb = perf_cycles_reg;
        10'h037: read_data_comb = tokens_per_sec_reg;
        default: begin
            if ((jtag_word_addr >= 10'h018) && (jtag_word_addr < 10'h028)) begin
                read_data_comb = {24'd0, output_mem[jtag_word_addr - 10'h018]};
            end else begin
                read_data_comb = 32'd0;
            end
        end
    endcase
end

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
