module microgpt_mmio (
    input  wire        clk,
    input  wire        resetn,
    input  wire [31:0] avs_address,
    input  wire        avs_read,
    input  wire        avs_write,
    input  wire [31:0] avs_writedata,
    input  wire [3:0]  avs_byteenable,
    output reg  [31:0] avs_readdata,
    output reg         avs_readdatavalid,
    output wire        avs_waitrequest,
    input  wire [1:0]  sw,
    input  wire [1:0]  key_n,
    output wire        led_idle,
    output wire        led_busy,
    output wire        led_done,
    output wire        led_host,
    output wire        led_error,
    output wire [7:0]  dbg_out_len,
    output wire [7:0]  dbg_last_token,
    output wire [3:0]  dbg_state
);

localparam [7:0] BOS_TOKEN = 8'd26;
localparam [3:0] ST_IDLE = 4'd0;
localparam [3:0] ST_WAIT = 4'd1;

reg [7:0] prompt_mem [0:15];
reg [7:0] output_mem [0:15];
reg [63:0] logits_mem [0:6];

reg [7:0] prompt_len_reg = 8'd0;
reg [7:0] max_gen_reg = 8'd8;
reg [15:0] temperature_reg = 16'h0100;
reg [31:0] rng_seed_reg = 32'h00000001;

reg running_reg = 1'b0;
reg done_reg = 1'b0;
reg error_reg = 1'b0;
reg host_toggle_reg = 1'b0;

reg [7:0] out_len_reg = 8'd0;
reg [7:0] current_pos_reg = 8'd0;
reg [7:0] prompt_index_reg = 8'd0;
reg [7:0] gen_count_reg = 8'd0;
reg [7:0] step_token_reg = BOS_TOKEN;
reg [31:0] rng_state_reg = 32'h00000001;

reg [3:0] state_reg = ST_IDLE;
reg step_start_reg = 1'b0;
reg step_clear_reg = 1'b0;

reg [7:0] last_sampled_token_reg = 8'd0;
reg [7:0] last_argmax_token_reg = 8'd0;
reg signed [15:0] last_top1_logit_reg = 16'sd0;
reg [7:0] last_top2_token_reg = 8'd0;
reg signed [15:0] last_top2_logit_reg = 16'sd0;
reg [31:0] perf_cycles_reg = 32'd0;
reg read_pending_reg = 1'b0;

reg key0_prev = 1'b1;
reg key1_prev = 1'b1;
reg start_req = 1'b0;
reg clear_req = 1'b0;

wire step_busy;
wire step_done;
wire [7:0] step_next_token;
wire [7:0] step_argmax_token;
wire [31:0] step_rng_state;
wire signed [15:0] step_top1_logit;
wire [7:0] step_top2_token;
wire signed [15:0] step_top2_logit;
wire [63:0] step_logits_pack0;
wire [63:0] step_logits_pack1;
wire [63:0] step_logits_pack2;
wire [63:0] step_logits_pack3;
wire [63:0] step_logits_pack4;
wire [63:0] step_logits_pack5;
wire [63:0] step_logits_pack6;

assign avs_waitrequest = 1'b0;
assign led_idle = !running_reg;
assign led_busy = running_reg;
assign led_done = done_reg;
assign led_host = host_toggle_reg;
assign led_error = error_reg;
assign dbg_out_len = out_len_reg;
assign dbg_last_token = last_sampled_token_reg;
assign dbg_state = state_reg;

microgpt_step_hls_adapter microgpt_step_inst (
    .clock(clk),
    .resetn(resetn),
    .start(step_start_reg),
    .busy(step_busy),
    .done(step_done),
    .stall(1'b0),
    .token_in(step_token_reg),
    .pos_in(current_pos_reg),
    .clear_cache(step_clear_reg),
    .sample_mode(1'b1),
    .temperature_q8_8(temperature_reg),
    .rng_state_in(rng_state_reg),
    .next_token(step_next_token),
    .argmax_token(step_argmax_token),
    .rng_state_out(step_rng_state),
    .top1_logit_q11(step_top1_logit),
    .top2_token(step_top2_token),
    .top2_logit_q11(step_top2_logit),
    .logits_pack0(step_logits_pack0),
    .logits_pack1(step_logits_pack1),
    .logits_pack2(step_logits_pack2),
    .logits_pack3(step_logits_pack3),
    .logits_pack4(step_logits_pack4),
    .logits_pack5(step_logits_pack5),
    .logits_pack6(step_logits_pack6)
);

integer idx;
integer out_idx;

always @(posedge clk) begin
    if (!resetn) begin
        prompt_len_reg <= 8'd0;
        max_gen_reg <= 8'd8;
        temperature_reg <= 16'h0100;
        rng_seed_reg <= 32'h00000001;
        running_reg <= 1'b0;
        done_reg <= 1'b0;
        error_reg <= 1'b0;
        host_toggle_reg <= 1'b0;
        out_len_reg <= 8'd0;
        current_pos_reg <= 8'd0;
        prompt_index_reg <= 8'd0;
        gen_count_reg <= 8'd0;
        step_token_reg <= BOS_TOKEN;
        rng_state_reg <= 32'h00000001;
        state_reg <= ST_IDLE;
        step_start_reg <= 1'b0;
        step_clear_reg <= 1'b0;
        avs_readdatavalid <= 1'b0;
        avs_readdata <= 32'd0;
        read_pending_reg <= 1'b0;
        last_sampled_token_reg <= 8'd0;
        last_argmax_token_reg <= 8'd0;
        last_top1_logit_reg <= 16'sd0;
        last_top2_token_reg <= 8'd0;
        last_top2_logit_reg <= 16'sd0;
        perf_cycles_reg <= 32'd0;
        key0_prev <= 1'b1;
        key1_prev <= 1'b1;
        start_req <= 1'b0;
        clear_req <= 1'b0;
        for (idx = 0; idx < 16; idx = idx + 1) begin
            prompt_mem[idx] <= 8'd0;
            output_mem[idx] <= 8'd0;
        end
        for (idx = 0; idx < 7; idx = idx + 1) begin
            logits_mem[idx] <= 64'd0;
        end
    end else begin
        step_start_reg <= 1'b0;
        avs_readdatavalid <= 1'b0;
        key0_prev <= key_n[0];
        key1_prev <= key_n[1];

        if (read_pending_reg) begin
            avs_readdatavalid <= 1'b1;
            read_pending_reg <= 1'b0;
        end else if (avs_read) begin
            read_pending_reg <= 1'b1;
            avs_readdata <= read_data_comb;
        end

        if (avs_write || avs_read) begin
            host_toggle_reg <= ~host_toggle_reg;
        end

        if (state_reg != ST_IDLE) begin
            perf_cycles_reg <= perf_cycles_reg + 32'd1;
        end

        if (key0_prev && !key_n[0]) begin
            start_req <= 1'b1;
        end
        if (key1_prev && !key_n[1]) begin
            clear_req <= 1'b1;
        end

        if (avs_write) begin
            case (avs_address[9:2])
                6'h02: begin
                    if (avs_writedata[0]) start_req <= 1'b1;
                    if (avs_writedata[1]) clear_req <= 1'b1;
                    if (avs_writedata[2]) done_reg <= 1'b0;
                end
                6'h04: begin
                    prompt_len_reg <= avs_writedata[7:0];
                    max_gen_reg <= avs_writedata[15:8];
                    temperature_reg <= avs_writedata[31:16];
                end
                6'h05: rng_seed_reg <= avs_writedata;
                default: begin
                    if ((avs_address[9:2] >= 6'h08) && (avs_address[9:2] < 6'h18)) begin
                        prompt_mem[avs_address[5:2] - 4'h8] <= avs_writedata[7:0];
                    end
                end
            endcase
        end

        if (clear_req) begin
            running_reg <= 1'b0;
            done_reg <= 1'b0;
            error_reg <= 1'b0;
            out_len_reg <= 8'd0;
            current_pos_reg <= 8'd0;
            prompt_index_reg <= 8'd0;
            gen_count_reg <= 8'd0;
            step_token_reg <= BOS_TOKEN;
            rng_state_reg <= rng_seed_reg;
            state_reg <= ST_IDLE;
            step_clear_reg <= 1'b0;
            last_sampled_token_reg <= 8'd0;
            last_argmax_token_reg <= 8'd0;
            last_top1_logit_reg <= 16'sd0;
            last_top2_token_reg <= 8'd0;
            last_top2_logit_reg <= 16'sd0;
            perf_cycles_reg <= 32'd0;
            for (out_idx = 0; out_idx < 16; out_idx = out_idx + 1) begin
                output_mem[out_idx] <= 8'd0;
            end
            clear_req <= 1'b0;
        end else begin
            case (state_reg)
                ST_IDLE: begin
                    if (start_req) begin
                        done_reg <= 1'b0;
                        error_reg <= 1'b0;
                        out_len_reg <= 8'd0;
                        current_pos_reg <= 8'd0;
                        prompt_index_reg <= 8'd0;
                        gen_count_reg <= 8'd0;
                        step_token_reg <= BOS_TOKEN;
                        rng_state_reg <= rng_seed_reg;
                        perf_cycles_reg <= 32'd0;
                        step_clear_reg <= 1'b1;
                        if (max_gen_reg > 8'd15) begin
                            error_reg <= 1'b1;
                        end else begin
                            running_reg <= 1'b1;
                            step_start_reg <= 1'b1;
                            state_reg <= ST_WAIT;
                        end
                        start_req <= 1'b0;
                    end
                end

                ST_WAIT: begin
                    if (step_done) begin
                        last_sampled_token_reg <= step_next_token;
                        last_argmax_token_reg <= step_argmax_token;
                        last_top1_logit_reg <= step_top1_logit;
                        last_top2_token_reg <= step_top2_token;
                        last_top2_logit_reg <= step_top2_logit;
                        logits_mem[0] <= step_logits_pack0;
                        logits_mem[1] <= step_logits_pack1;
                        logits_mem[2] <= step_logits_pack2;
                        logits_mem[3] <= step_logits_pack3;
                        logits_mem[4] <= step_logits_pack4;
                        logits_mem[5] <= step_logits_pack5;
                        logits_mem[6] <= step_logits_pack6;
                        rng_state_reg <= step_rng_state;
                        step_clear_reg <= 1'b0;

                        if ((step_next_token == BOS_TOKEN) || (gen_count_reg >= max_gen_reg) || (current_pos_reg == 8'd15)) begin
                            running_reg <= 1'b0;
                            done_reg <= 1'b1;
                            state_reg <= ST_IDLE;
                        end else begin
                            output_mem[out_len_reg] <= step_next_token;
                            out_len_reg <= out_len_reg + 8'd1;
                            gen_count_reg <= gen_count_reg + 8'd1;
                            step_token_reg <= step_next_token;
                            current_pos_reg <= current_pos_reg + 8'd1;
                            if ((gen_count_reg + 8'd1 >= max_gen_reg) || (current_pos_reg == 8'd15)) begin
                                running_reg <= 1'b0;
                                done_reg <= 1'b1;
                                state_reg <= ST_IDLE;
                            end else begin
                                step_start_reg <= 1'b1;
                                state_reg <= ST_WAIT;
                            end
                        end
                    end
                end

                default: state_reg <= ST_IDLE;
            endcase
        end
    end
end

reg [31:0] read_data_comb;

always @(*) begin
    read_data_comb = 32'd0;
    case (avs_address[9:2])
        6'h00: read_data_comb = 32'h4D475054;
        6'h01: read_data_comb = 32'h00010000;
        6'h02: read_data_comb = 32'd0;
        6'h03: read_data_comb = {
            current_pos_reg,
            out_len_reg,
            8'd0,
            1'b0,
            1'b1,
            1'b1,
            host_toggle_reg,
            error_reg,
            done_reg,
            running_reg,
            ~running_reg
        };
        6'h04: read_data_comb = {temperature_reg, max_gen_reg, 8'd0};
        6'h05: read_data_comb = rng_seed_reg;
        6'h06: read_data_comb = {last_top1_logit_reg[15:0], last_argmax_token_reg, last_sampled_token_reg};
        6'h07: read_data_comb = {last_top2_logit_reg[15:0], 8'd0, last_top2_token_reg};
        6'h36: read_data_comb = perf_cycles_reg;
        default: begin
            if ((avs_address[9:2] >= 6'h08) && (avs_address[9:2] < 6'h18)) begin
                read_data_comb = {24'd0, prompt_mem[avs_address[5:2] - 4'h8]};
            end else if ((avs_address[9:2] >= 6'h18) && (avs_address[9:2] < 6'h28)) begin
                read_data_comb = {24'd0, output_mem[avs_address[5:2] - 4'h8]};
            end else if ((avs_address[9:2] >= 6'h28) && (avs_address[9:2] < 6'h36)) begin
                case (avs_address[9:2] - 6'h28)
                    4'd0: read_data_comb = logits_mem[0][31:0];
                    4'd1: read_data_comb = logits_mem[0][63:32];
                    4'd2: read_data_comb = logits_mem[1][31:0];
                    4'd3: read_data_comb = logits_mem[1][63:32];
                    4'd4: read_data_comb = logits_mem[2][31:0];
                    4'd5: read_data_comb = logits_mem[2][63:32];
                    4'd6: read_data_comb = logits_mem[3][31:0];
                    4'd7: read_data_comb = logits_mem[3][63:32];
                    4'd8: read_data_comb = logits_mem[4][31:0];
                    4'd9: read_data_comb = logits_mem[4][63:32];
                    4'd10: read_data_comb = logits_mem[5][31:0];
                    4'd11: read_data_comb = logits_mem[5][63:32];
                    4'd12: read_data_comb = logits_mem[6][31:0];
                    4'd13: read_data_comb = logits_mem[6][63:32];
                    default: read_data_comb = 32'd0;
                endcase
            end
        end
    endcase
end

endmodule
