module microgpt_exact_core (
    input  wire        clk,
    input  wire        resetn,
    input  wire        start,
    input  wire        clear_cache,
    input  wire        sample_mode,
    input  wire [15:0] temperature_q8_8,
    input  wire [31:0] rng_state_in,
    input  wire [7:0]  token_in,
    input  wire [7:0]  pos_in,
    output reg         busy,
    output reg         done,
    output reg  [7:0]  next_token,
    output reg  [7:0]  argmax_token,
    output reg  [31:0] rng_state_out,
    output reg  signed [15:0] top_logit_q12,
    output wire signed [(27*16)-1:0] logits_flat
);

`include "microgpt_exact_core_params.svh"

reg [5:0] state_reg;
reg [7:0] token_reg;
reg [7:0] pos_reg;
reg [6:0] row_reg;
reg [6:0] col_reg;
reg [3:0] idx_reg;
reg [3:0] lm_reduce_idx;
reg [1:0] head_reg;
reg [4:0] time_reg;

reg signed [63:0] acc_reg;
reg signed [63:0] attn_dot_acc_reg;
reg signed [63:0] sumsq_reg;
reg signed [63:0] linear_acc [0:15];
reg signed [15:0] rms_scale_reg;
reg signed [15:0] attn_max_reg;
reg [31:0] attn_weight_sum_reg;
reg [31:0] attn_weight_reg;
reg rms_start_reg;
reg [63:0] rms_sumsq_reg;
reg [3:0] attn_div_start_reg;
reg signed [63:0] attn_div_num_reg [0:3];
reg [31:0] attn_div_den_reg;
reg signed [63:0] attn_value_acc [0:3];
reg signed [15:0] attn_value_sample [0:3];

reg signed [15:0] x_vec [0:15];
reg signed [15:0] norm_vec [0:15];
reg signed [15:0] residual_vec [0:15];
reg signed [15:0] q_vec [0:15];
reg signed [15:0] k_vec [0:15];
reg signed [15:0] v_vec [0:15];
reg signed [15:0] x_attn [0:15];
reg signed [15:0] mlp_vec [0:63];
reg signed [15:0] logits [0:26];
reg signed [15:0] lm_tile_logits [0:TILE_ROWS-1];
reg signed [15:0] attn_scores [0:15];

reg signed [15:0] k_cache [0:15][0:15];
reg signed [15:0] v_cache [0:15][0:15];

reg signed [15:0] wte_rom [0:431];
reg signed [15:0] wpe_rom [0:255];
reg signed [15:0] lm_head_rom [0:431];
reg signed [15:0] attn_wq_rom [0:255];
reg signed [15:0] attn_wk_rom [0:255];
reg signed [15:0] attn_wv_rom [0:255];
reg signed [15:0] attn_wo_rom [0:255];
reg signed [15:0] mlp_fc1_rom [0:1023];
reg signed [15:0] mlp_fc2_rom [0:1023];

integer i;
integer j;
integer t;
genvar logits_idx;

reg signed [63:0] acc_next;
reg signed [63:0] prod64;
reg signed [15:0] value16;
reg signed [15:0] max_logit_tmp;
reg signed [15:0] max_score_tmp;
reg signed [31:0] delta_tmp;
reg [31:0] weight_tmp;
reg [7:0] best_token_tmp;
reg systolic_start_reg;
reg sampler_start_reg;

reg signed [15:0] systolic_vector_value;
reg signed [(TILE_ROWS*16)-1:0] systolic_weights_flat;
wire [4:0] systolic_col_idx;
wire systolic_busy;
wire systolic_done;
wire signed [(TILE_ROWS*64)-1:0] systolic_result_flat;
wire rms_busy;
wire rms_done;
wire signed [15:0] rms_scale_out;
wire [3:0] attn_div_busy;
wire [3:0] attn_div_done;
wire signed [15:0] attn_div_quotient [0:3];
wire sampler_busy;
wire sampler_done;
wire [7:0] sampler_next_token;

systolic_matvec16_tile #(
    .DATA_WIDTH(16),
    .ACC_WIDTH(64),
    .LANES(TILE_ROWS)
) linear_tile_inst (
    .clk(clk),
    .resetn(resetn),
    .start(systolic_start_reg),
    .vector_value(systolic_vector_value),
    .weights_flat(systolic_weights_flat),
    .col_idx(systolic_col_idx),
    .busy(systolic_busy),
    .done(systolic_done),
    .result_flat(systolic_result_flat)
);

rms_scale_engine rms_scale_inst (
    .clk(clk),
    .resetn(resetn),
    .start(rms_start_reg),
    .sumsq(rms_sumsq_reg),
    .busy(rms_busy),
    .done(rms_done),
    .scale_q12(rms_scale_out)
);

genvar div_idx;
generate
    for (div_idx = 0; div_idx < HEAD_DIM; div_idx = div_idx + 1) begin : GEN_ATTN_DIV
        sat_div16_engine attn_div_inst (
            .clk(clk),
            .resetn(resetn),
            .start(attn_div_start_reg[div_idx]),
            .numerator(attn_div_num_reg[div_idx]),
            .denominator(attn_div_den_reg),
            .busy(attn_div_busy[div_idx]),
            .done(attn_div_done[div_idx]),
            .quotient(attn_div_quotient[div_idx])
        );
    end
endgenerate


microgpt_categorical_sampler #(
    .VOCAB_SIZE(VOCAB_SIZE)
) sampler_inst (
    .clk(clk),
    .resetn(resetn),
    .start(sampler_start_reg),
    .temperature_q8_8(temperature_q8_8),
    .rng_state(rng_state_out),
    .argmax_token(argmax_token),
    .top_logit_q12(top_logit_q12),
    .logits_flat(logits_flat),
    .busy(sampler_busy),
    .done(sampler_done),
    .next_token(sampler_next_token)
);

`include "microgpt_exact_core_rom_init.svh"

always @(*) begin
    systolic_vector_value = 16'sd0;
    systolic_weights_flat = '0;

    case (state_reg)
        ST_Q_LINEAR: begin
            systolic_vector_value = norm_vec[systolic_col_idx];
            for (i = 0; i < TILE_ROWS; i = i + 1)
                systolic_weights_flat[(i*16) +: 16] = attn_wq_rom[(row_reg + i) * EMBED_DIM + systolic_col_idx];
        end

        ST_K_LINEAR: begin
            systolic_vector_value = norm_vec[systolic_col_idx];
            for (i = 0; i < TILE_ROWS; i = i + 1)
                systolic_weights_flat[(i*16) +: 16] = attn_wk_rom[(row_reg + i) * EMBED_DIM + systolic_col_idx];
        end

        ST_V_LINEAR: begin
            systolic_vector_value = norm_vec[systolic_col_idx];
            for (i = 0; i < TILE_ROWS; i = i + 1)
                systolic_weights_flat[(i*16) +: 16] = attn_wv_rom[(row_reg + i) * EMBED_DIM + systolic_col_idx];
        end

        ST_ATTN_WO: begin
            systolic_vector_value = x_attn[systolic_col_idx];
            for (i = 0; i < TILE_ROWS; i = i + 1)
                systolic_weights_flat[(i*16) +: 16] = attn_wo_rom[(row_reg + i) * EMBED_DIM + systolic_col_idx];
        end

        ST_FC1: begin
            systolic_vector_value = norm_vec[systolic_col_idx];
            for (i = 0; i < TILE_ROWS; i = i + 1)
                systolic_weights_flat[(i*16) +: 16] = mlp_fc1_rom[((row_reg + i) * EMBED_DIM) + systolic_col_idx];
        end

        ST_FC2: begin
            systolic_vector_value = mlp_vec[col_reg + systolic_col_idx];
            for (i = 0; i < TILE_ROWS; i = i + 1)
                systolic_weights_flat[(i*16) +: 16] = mlp_fc2_rom[((row_reg + i) * MLP_DIM) + col_reg + systolic_col_idx];
        end

        ST_LM_HEAD: begin
            systolic_vector_value = x_vec[systolic_col_idx];
            for (i = 0; i < TILE_ROWS; i = i + 1) begin
                if ((row_reg + i) < VOCAB_SIZE)
                    systolic_weights_flat[(i*16) +: 16] = lm_head_rom[((row_reg + i) * EMBED_DIM) + systolic_col_idx];
                else
                    systolic_weights_flat[(i*16) +: 16] = 16'sd0;
            end
        end

        default: begin
        end
    endcase
end

`include "microgpt_exact_core_math.svh"

generate
    for (logits_idx = 0; logits_idx < VOCAB_SIZE; logits_idx = logits_idx + 1) begin : GEN_LOGITS_FLAT
        assign logits_flat[(logits_idx*16) +: 16] = logits[logits_idx];
    end
endgenerate

always @(posedge clk) begin
    if (!resetn) begin
        state_reg <= ST_IDLE;
        token_reg <= 8'd0;
        pos_reg <= 8'd0;
        row_reg <= 7'd0;
        col_reg <= 7'd0;
        idx_reg <= 4'd0;
        lm_reduce_idx <= 4'd0;
        head_reg <= 2'd0;
        time_reg <= 5'd0;
        acc_reg <= 64'sd0;
        attn_dot_acc_reg <= 64'sd0;
        sumsq_reg <= 64'sd0;
        systolic_start_reg <= 1'b0;
        sampler_start_reg <= 1'b0;
        rms_start_reg <= 1'b0;
        attn_div_start_reg <= 4'd0;
        rms_scale_reg <= 16'sd0;
        attn_max_reg <= 16'sd0;
        attn_weight_sum_reg <= 32'd0;
        attn_weight_reg <= 32'd0;
        rms_sumsq_reg <= 64'd0;
        attn_div_den_reg <= 32'd0;
        busy <= 1'b0;
        done <= 1'b0;
        next_token <= 8'd0;
        argmax_token <= 8'd0;
        rng_state_out <= 32'd1;
        top_logit_q12 <= 16'sd0;
        for (i = 0; i < EMBED_DIM; i = i + 1) begin
            x_vec[i] <= 16'sd0;
            norm_vec[i] <= 16'sd0;
            residual_vec[i] <= 16'sd0;
            q_vec[i] <= 16'sd0;
            k_vec[i] <= 16'sd0;
            v_vec[i] <= 16'sd0;
            x_attn[i] <= 16'sd0;
        end
        for (i = 0; i < MLP_DIM; i = i + 1)
            mlp_vec[i] <= 16'sd0;
        for (i = 0; i < VOCAB_SIZE; i = i + 1)
            logits[i] <= 16'sd0;
        for (i = 0; i < TILE_ROWS; i = i + 1)
            lm_tile_logits[i] <= 16'sd0;
        for (i = 0; i < 16; i = i + 1)
            linear_acc[i] <= 64'sd0;
        for (i = 0; i < HEAD_DIM; i = i + 1) begin
            attn_div_num_reg[i] <= 64'sd0;
            attn_value_acc[i] <= 64'sd0;
            attn_value_sample[i] <= 16'sd0;
        end
        for (i = 0; i < 16; i = i + 1) begin
            attn_scores[i] <= 16'sd0;
            for (j = 0; j < EMBED_DIM; j = j + 1) begin
                k_cache[i][j] <= 16'sd0;
                v_cache[i][j] <= 16'sd0;
            end
        end
    end else begin
        done <= 1'b0;
        systolic_start_reg <= 1'b0;
        sampler_start_reg <= 1'b0;
        rms_start_reg <= 1'b0;
        attn_div_start_reg <= 4'd0;
        case (state_reg)
            ST_IDLE: begin
                busy <= 1'b0;
                if (start) begin
                    token_reg <= token_in;
                    pos_reg <= pos_in;
                    idx_reg <= 4'd0;
                    row_reg <= 7'd0;
                    col_reg <= 7'd0;
                    head_reg <= 2'd0;
                    time_reg <= 5'd0;
                    acc_reg <= 64'sd0;
                    sumsq_reg <= 64'sd0;
                    if (sample_mode)
                        rng_state_out <= xorshift32(rng_state_in);
                    else
                        rng_state_out <= rng_state_in;
                    if (clear_cache) begin
                        for (i = 0; i < 16; i = i + 1) begin
                            for (j = 0; j < EMBED_DIM; j = j + 1) begin
                                k_cache[i][j] <= 16'sd0;
                                v_cache[i][j] <= 16'sd0;
                            end
                        end
                    end
                    busy <= 1'b1;
                    state_reg <= ST_LOAD_X;
                end
            end

            ST_LOAD_X: begin
                value16 = sat16($signed(wte_rom[token_reg * EMBED_DIM + idx_reg]) + $signed(wpe_rom[pos_reg * EMBED_DIM + idx_reg]));
                prod64 = $signed(value16) * $signed(value16);
                x_vec[idx_reg] <= value16;
                sumsq_reg <= sumsq_reg + (prod64 >>> FRAC_BITS);
                if (idx_reg == EMBED_DIM - 1) begin
                    idx_reg <= 4'd0;
                    rms_sumsq_reg <= sumsq_reg + (prod64 >>> FRAC_BITS);
                    state_reg <= ST_RMS0_WAIT;
                end else begin
                    idx_reg <= idx_reg + 4'd1;
                end
            end

            ST_RMS0_SUM: begin
                prod64 = $signed(x_vec[idx_reg]) * $signed(x_vec[idx_reg]);
                sumsq_reg <= sumsq_reg + (prod64 >>> FRAC_BITS);
                if (idx_reg == EMBED_DIM - 1) begin
                    rms_sumsq_reg <= sumsq_reg + (prod64 >>> FRAC_BITS);
                    state_reg <= ST_RMS0_WAIT;
                end else begin
                    idx_reg <= idx_reg + 4'd1;
                end
            end

            ST_RMS0_WAIT: begin
                if (!rms_busy && !rms_done)
                    rms_start_reg <= 1'b1;
                if (rms_done) begin
                    rms_scale_reg <= rms_scale_out;
                    idx_reg <= 4'd0;
                    sumsq_reg <= 64'sd0;
                    state_reg <= ST_RMS0_APPLY;
                end
            end

            ST_RMS0_APPLY: begin
                value16 = mul_q12(x_vec[idx_reg], rms_scale_reg);
                x_vec[idx_reg] <= value16;
                residual_vec[idx_reg] <= value16;
                if (idx_reg == EMBED_DIM - 1) begin
                    idx_reg <= 4'd0;
                    sumsq_reg <= 64'sd0;
                    state_reg <= ST_ATTN_RMS_SUM;
                end else begin
                    idx_reg <= idx_reg + 4'd1;
                end
            end

            ST_ATTN_SAVE_RES: begin
                for (i = 0; i < EMBED_DIM; i = i + 1)
                    residual_vec[i] <= x_vec[i];
                idx_reg <= 4'd0;
                sumsq_reg <= 64'sd0;
                state_reg <= ST_ATTN_RMS_SUM;
            end

            ST_ATTN_RMS_SUM: begin
                prod64 = $signed(x_vec[idx_reg]) * $signed(x_vec[idx_reg]);
                sumsq_reg <= sumsq_reg + (prod64 >>> FRAC_BITS);
                if (idx_reg == EMBED_DIM - 1) begin
                    rms_sumsq_reg <= sumsq_reg + (prod64 >>> FRAC_BITS);
                    state_reg <= ST_ATTN_RMS_WAIT;
                end else begin
                    idx_reg <= idx_reg + 4'd1;
                end
            end

            ST_ATTN_RMS_WAIT: begin
                if (!rms_busy && !rms_done)
                    rms_start_reg <= 1'b1;
                if (rms_done) begin
                    rms_scale_reg <= rms_scale_out;
                    idx_reg <= 4'd0;
                    state_reg <= ST_ATTN_RMS_APPLY;
                end
            end

            ST_ATTN_RMS_APPLY: begin
                norm_vec[idx_reg] <= mul_q12(x_vec[idx_reg], rms_scale_reg);
                if (idx_reg == EMBED_DIM - 1) begin
                    row_reg <= 7'd0;
                    col_reg <= 7'd0;
                    acc_reg <= 64'sd0;
                    state_reg <= ST_Q_LINEAR;
                end else begin
                    idx_reg <= idx_reg + 4'd1;
                end
            end

            ST_Q_LINEAR: begin
                if (!systolic_busy && !systolic_done)
                    systolic_start_reg <= 1'b1;
                if (systolic_done) begin
                    for (i = 0; i < TILE_ROWS; i = i + 1)
                        q_vec[i] <= sat16($signed(systolic_result_flat[(i*64) +: 64]) >>> FRAC_BITS);
                    if (row_reg == LAST_EMBED_ROW_TILE) begin
                        row_reg <= 7'd0;
                        state_reg <= ST_K_LINEAR;
                    end else begin
                        row_reg <= row_reg + TILE_ROW_STEP;
                    end
                end
            end

            ST_K_LINEAR: begin
                if (!systolic_busy && !systolic_done)
                    systolic_start_reg <= 1'b1;
                if (systolic_done) begin
                    for (i = 0; i < TILE_ROWS; i = i + 1)
                        k_vec[i] <= sat16($signed(systolic_result_flat[(i*64) +: 64]) >>> FRAC_BITS);
                    if (row_reg == LAST_EMBED_ROW_TILE) begin
                        row_reg <= 7'd0;
                        state_reg <= ST_V_LINEAR;
                    end else begin
                        row_reg <= row_reg + TILE_ROW_STEP;
                    end
                end
            end

            ST_V_LINEAR: begin
                if (!systolic_busy && !systolic_done)
                    systolic_start_reg <= 1'b1;
                if (systolic_done) begin
                    for (i = 0; i < TILE_ROWS; i = i + 1)
                        v_vec[i] <= sat16($signed(systolic_result_flat[(i*64) +: 64]) >>> FRAC_BITS);
                    if (row_reg == LAST_EMBED_ROW_TILE) begin
                        row_reg <= 7'd0;
                        state_reg <= ST_CACHE_QKV;
                    end else begin
                        row_reg <= row_reg + TILE_ROW_STEP;
                    end
                end
            end

            ST_CACHE_QKV: begin
                for (i = 0; i < EMBED_DIM; i = i + 1) begin
                    k_cache[pos_reg][i] <= k_vec[i];
                    v_cache[pos_reg][i] <= v_vec[i];
                end
                head_reg <= 2'd0;
                time_reg <= 5'd0;
                col_reg <= 7'd0;
                acc_reg <= 64'sd0;
                state_reg <= ST_ATTN_DOT;
            end

            ST_ATTN_DOT: begin
                acc_next = 64'sd0 +
                    ($signed(q_vec[head_reg * HEAD_DIM + 0]) * $signed(k_cache[time_reg][head_reg * HEAD_DIM + 0])) +
                    ($signed(q_vec[head_reg * HEAD_DIM + 1]) * $signed(k_cache[time_reg][head_reg * HEAD_DIM + 1])) +
                    ($signed(q_vec[head_reg * HEAD_DIM + 2]) * $signed(k_cache[time_reg][head_reg * HEAD_DIM + 2])) +
                    ($signed(q_vec[head_reg * HEAD_DIM + 3]) * $signed(k_cache[time_reg][head_reg * HEAD_DIM + 3]));
                attn_dot_acc_reg <= acc_next;
                state_reg <= ST_ATTN_DOT_COMMIT;
            end

            ST_ATTN_DOT_COMMIT: begin
                value16 = sat16((attn_dot_acc_reg >>> FRAC_BITS) >>> 1);
                attn_scores[time_reg] <= value16;
                if (time_reg == 5'd0 || value16 > attn_max_reg)
                    attn_max_reg <= value16;
                acc_reg <= 64'sd0;
                col_reg <= 7'd0;
                if (time_reg == pos_reg[4:0]) begin
                    attn_weight_sum_reg <= 32'd0;
                    time_reg <= 5'd0;
                    state_reg <= ST_ATTN_SUM;
                end else begin
                    time_reg <= time_reg + 5'd1;
                    state_reg <= ST_ATTN_DOT;
                end
            end

            ST_ATTN_SOFT: begin
                attn_max_reg <= attn_scores[0];
                if (pos_reg == 8'd0) begin
                    attn_weight_sum_reg <= 32'd0;
                    time_reg <= 5'd0;
                    state_reg <= ST_ATTN_SUM;
                end else begin
                    time_reg <= 5'd1;
                    state_reg <= ST_ATTN_MAX;
                end
            end

            ST_ATTN_MAX: begin
                max_score_tmp = attn_max_reg;
                if (attn_scores[time_reg] > max_score_tmp)
                    max_score_tmp = attn_scores[time_reg];
                attn_max_reg <= max_score_tmp;
                if (time_reg == pos_reg[4:0]) begin
                    attn_weight_sum_reg <= 32'd0;
                    time_reg <= 5'd0;
                    state_reg <= ST_ATTN_SUM;
                end else begin
                    time_reg <= time_reg + 5'd1;
                end
            end

            ST_ATTN_SUM: begin
                delta_tmp = $signed(attn_scores[time_reg]) - $signed(attn_max_reg);
                weight_tmp = exp_neg_q12(delta_tmp);
                attn_weight_sum_reg <= attn_weight_sum_reg + weight_tmp;
                if (time_reg == pos_reg[4:0]) begin
                    if ((attn_weight_sum_reg + weight_tmp) == 32'd0)
                        attn_weight_sum_reg <= 32'd1;
                    col_reg <= 7'd0;
                    time_reg <= 5'd0;
                    acc_reg <= 64'sd0;
                    for (i = 0; i < HEAD_DIM; i = i + 1)
                        attn_value_acc[i] <= 64'sd0;
                    state_reg <= ST_ATTN_WEIGHT;
                end else begin
                    time_reg <= time_reg + 5'd1;
                end
            end

            ST_ATTN_WEIGHT: begin
                delta_tmp = $signed(attn_scores[time_reg]) - $signed(attn_max_reg);
                weight_tmp = exp_neg_q12(delta_tmp);
                attn_weight_reg <= weight_tmp;
                for (i = 0; i < HEAD_DIM; i = i + 1)
                    attn_value_sample[i] <= v_cache[time_reg][head_reg * HEAD_DIM + i];
                state_reg <= ST_ATTN_WEIGHT_ACC;
            end

            ST_ATTN_WEIGHT_ACC: begin
                for (i = 0; i < HEAD_DIM; i = i + 1) begin
                    attn_value_acc[i] <= attn_value_acc[i] +
                        ($signed({1'b0, attn_weight_reg[30:0]}) * $signed(attn_value_sample[i]));
                end
                if (time_reg == pos_reg[4:0]) begin
                    attn_div_den_reg <= attn_weight_sum_reg;
                    acc_reg <= 64'sd0;
                    time_reg <= 5'd0;
                    state_reg <= ST_ATTN_DIV_PREP;
                end else begin
                    time_reg <= time_reg + 5'd1;
                    state_reg <= ST_ATTN_WEIGHT;
                end
            end

            ST_ATTN_DIV_PREP: begin
                for (i = 0; i < HEAD_DIM; i = i + 1)
                    attn_div_num_reg[i] <= attn_value_acc[i];
                state_reg <= ST_ATTN_DIV_WAIT;
            end

            ST_ATTN_DIV_WAIT: begin
                if (!(|attn_div_busy) && !(|attn_div_done))
                    attn_div_start_reg <= 4'b1111;
                if (&attn_div_done) begin
                    for (i = 0; i < HEAD_DIM; i = i + 1)
                        x_attn[head_reg * HEAD_DIM + i] <= attn_div_quotient[i];
                    col_reg <= 7'd0;
                    if (head_reg == N_HEAD - 1) begin
                        row_reg <= 7'd0;
                        state_reg <= ST_ATTN_WO;
                    end else begin
                        head_reg <= head_reg + 2'd1;
                        time_reg <= 5'd0;
                        state_reg <= ST_ATTN_DOT;
                    end
                end
            end

            ST_ATTN_WO: begin
                if (!systolic_busy && !systolic_done)
                    systolic_start_reg <= 1'b1;
                if (systolic_done) begin
                    for (i = 0; i < TILE_ROWS; i = i + 1)
                        norm_vec[i] <= sat16($signed(systolic_result_flat[(i*64) +: 64]) >>> FRAC_BITS);
                    if (row_reg == LAST_EMBED_ROW_TILE) begin
                        row_reg <= 7'd0;
                        idx_reg <= 4'd0;
                        sumsq_reg <= 64'sd0;
                        state_reg <= ST_ATTN_ADD;
                    end else begin
                        row_reg <= row_reg + TILE_ROW_STEP;
                    end
                end
            end

            ST_ATTN_ADD: begin
                value16 = sat16($signed(norm_vec[idx_reg]) + $signed(residual_vec[idx_reg]));
                prod64 = $signed(value16) * $signed(value16);
                x_vec[idx_reg] <= value16;
                residual_vec[idx_reg] <= value16;
                sumsq_reg <= sumsq_reg + (prod64 >>> FRAC_BITS);
                if (idx_reg == EMBED_DIM - 1) begin
                    idx_reg <= 4'd0;
                    rms_sumsq_reg <= sumsq_reg + (prod64 >>> FRAC_BITS);
                    state_reg <= ST_MLP_RMS_WAIT;
                end else begin
                    idx_reg <= idx_reg + 4'd1;
                end
            end

            ST_MLP_SAVE_RES: begin
                for (i = 0; i < EMBED_DIM; i = i + 1)
                    residual_vec[i] <= x_vec[i];
                idx_reg <= 4'd0;
                sumsq_reg <= 64'sd0;
                state_reg <= ST_MLP_RMS_SUM;
            end

            ST_MLP_RMS_SUM: begin
                prod64 = $signed(x_vec[idx_reg]) * $signed(x_vec[idx_reg]);
                sumsq_reg <= sumsq_reg + (prod64 >>> FRAC_BITS);
                if (idx_reg == EMBED_DIM - 1) begin
                    rms_sumsq_reg <= sumsq_reg + (prod64 >>> FRAC_BITS);
                    state_reg <= ST_MLP_RMS_WAIT;
                end else begin
                    idx_reg <= idx_reg + 4'd1;
                end
            end

            ST_MLP_RMS_WAIT: begin
                if (!rms_busy && !rms_done)
                    rms_start_reg <= 1'b1;
                if (rms_done) begin
                    rms_scale_reg <= rms_scale_out;
                    idx_reg <= 4'd0;
                    state_reg <= ST_MLP_RMS_APPLY;
                end
            end

            ST_MLP_RMS_APPLY: begin
                norm_vec[idx_reg] <= mul_q12(x_vec[idx_reg], rms_scale_reg);
                if (idx_reg == EMBED_DIM - 1) begin
                    row_reg <= 7'd0;
                    col_reg <= 7'd0;
                    for (i = 0; i < 16; i = i + 1)
                        linear_acc[i] <= 64'sd0;
                    state_reg <= ST_FC1;
                end else begin
                    idx_reg <= idx_reg + 4'd1;
                end
            end

            ST_FC1: begin
                if (!systolic_busy && !systolic_done)
                    systolic_start_reg <= 1'b1;
                if (systolic_done) begin
                    case (row_reg)
                        7'd0: begin
                            for (i = 0; i < TILE_ROWS; i = i + 1) begin
                                value16 = sat16($signed(systolic_result_flat[(i*64) +: 64]) >>> FRAC_BITS);
                                mlp_vec[i] <= value16[15] ? 16'sd0 : value16;
                            end
                        end
                        7'd16: begin
                            for (i = 0; i < TILE_ROWS; i = i + 1) begin
                                value16 = sat16($signed(systolic_result_flat[(i*64) +: 64]) >>> FRAC_BITS);
                                mlp_vec[16 + i] <= value16[15] ? 16'sd0 : value16;
                            end
                        end
                        7'd32: begin
                            for (i = 0; i < TILE_ROWS; i = i + 1) begin
                                value16 = sat16($signed(systolic_result_flat[(i*64) +: 64]) >>> FRAC_BITS);
                                mlp_vec[32 + i] <= value16[15] ? 16'sd0 : value16;
                            end
                        end
                        default: begin
                            for (i = 0; i < TILE_ROWS; i = i + 1) begin
                                value16 = sat16($signed(systolic_result_flat[(i*64) +: 64]) >>> FRAC_BITS);
                                mlp_vec[48 + i] <= value16[15] ? 16'sd0 : value16;
                            end
                        end
                    endcase
                    if (row_reg == LAST_MLP_ROW_TILE) begin
                        row_reg <= 7'd0;
                        col_reg <= 7'd0;
                        for (i = 0; i < 16; i = i + 1)
                            linear_acc[i] <= 64'sd0;
                        state_reg <= ST_FC2;
                    end else begin
                        row_reg <= row_reg + TILE_ROW_STEP;
                    end
                end
            end

            ST_FC2: begin
                if (!systolic_busy && !systolic_done)
                    systolic_start_reg <= 1'b1;
                if (systolic_done) begin
                    if (col_reg == 7'd48) begin
                        for (i = 0; i < TILE_ROWS; i = i + 1) begin
                            acc_next = linear_acc[i] + $signed(systolic_result_flat[(i*64) +: 64]);
                            norm_vec[i] <= sat16(acc_next >>> FRAC_BITS);
                            linear_acc[i] <= 64'sd0;
                        end
                        if (row_reg == LAST_EMBED_ROW_TILE) begin
                            row_reg <= 7'd0;
                            col_reg <= 7'd0;
                            idx_reg <= 4'd0;
                            state_reg <= ST_MLP_ADD;
                        end else begin
                            row_reg <= row_reg + TILE_ROW_STEP;
                            col_reg <= 7'd0;
                        end
                    end else begin
                        for (i = 0; i < TILE_ROWS; i = i + 1)
                            linear_acc[i] <= linear_acc[i] + $signed(systolic_result_flat[(i*64) +: 64]);
                        col_reg <= col_reg + 7'd16;
                    end
                end
            end

            ST_MLP_ADD: begin
                x_vec[idx_reg] <= sat16($signed(norm_vec[idx_reg]) + $signed(residual_vec[idx_reg]));
                if (idx_reg == EMBED_DIM - 1) begin
                    row_reg <= 7'd0;
                    col_reg <= 7'd0;
                    top_logit_q12 <= 16'sh8000;
                    argmax_token <= 8'd0;
                    state_reg <= ST_LM_HEAD;
                end else begin
                    idx_reg <= idx_reg + 4'd1;
                end
            end

            ST_LM_HEAD: begin
                if (!systolic_busy && !systolic_done)
                    systolic_start_reg <= 1'b1;
                if (systolic_done) begin
                    for (i = 0; i < TILE_ROWS; i = i + 1) begin
                        if ((row_reg + i) < VOCAB_SIZE) begin
                            value16 = sat16($signed(systolic_result_flat[(i*64) +: 64]) >>> FRAC_BITS);
                            logits[row_reg + i] <= value16;
                            lm_tile_logits[i] <= value16;
                        end else begin
                            lm_tile_logits[i] <= 16'sh8000;
                        end
                    end
                    lm_reduce_idx <= 4'd0;
                    state_reg <= ST_LM_HEAD_REDUCE;
                end
            end

            ST_LM_HEAD_REDUCE: begin
                max_logit_tmp = top_logit_q12;
                best_token_tmp = argmax_token;
                if ((row_reg + lm_reduce_idx) < VOCAB_SIZE) begin
                    if (lm_tile_logits[lm_reduce_idx] > max_logit_tmp) begin
                        max_logit_tmp = lm_tile_logits[lm_reduce_idx];
                        best_token_tmp = row_reg + lm_reduce_idx;
                    end
                end

                top_logit_q12 <= max_logit_tmp;
                argmax_token <= best_token_tmp;

                if ((lm_reduce_idx == TILE_ROWS - 1) || ((row_reg + lm_reduce_idx) == VOCAB_SIZE - 1)) begin
                    lm_reduce_idx <= 4'd0;
                    if (row_reg == LAST_VOCAB_ROW_TILE) begin
                        state_reg <= ST_LM_HEAD_FINISH;
                    end else begin
                        row_reg <= row_reg + TILE_ROW_STEP;
                        state_reg <= ST_LM_HEAD;
                    end
                end else begin
                    lm_reduce_idx <= lm_reduce_idx + 4'd1;
                end
            end

            ST_LM_HEAD_FINISH: begin
                if (sample_mode) begin
                    sampler_start_reg <= 1'b1;
                    state_reg <= ST_SAMPLE_SCALE;
                end else begin
                    next_token <= argmax_token;
                    state_reg <= ST_DONE;
                end
            end

            ST_SAMPLE: begin
                top_logit_q12 <= logits[0];
                argmax_token <= 8'd0;
                row_reg <= 7'd1;
                state_reg <= ST_SAMPLE_MAX;
            end

            ST_SAMPLE_MAX: begin
                max_logit_tmp = top_logit_q12;
                best_token_tmp = argmax_token;
                if (logits[row_reg] > max_logit_tmp) begin
                    max_logit_tmp = logits[row_reg];
                    best_token_tmp = {1'b0, row_reg};
                end
                top_logit_q12 <= max_logit_tmp;
                argmax_token <= best_token_tmp;
                if (row_reg == VOCAB_SIZE - 1) begin
                    if (sample_mode) begin
                        sampler_start_reg <= 1'b1;
                        state_reg <= ST_SAMPLE_SCALE;
                    end else begin
                        next_token <= best_token_tmp;
                        state_reg <= ST_DONE;
                    end
                end else begin
                    row_reg <= row_reg + 7'd1;
                end
            end

            ST_SAMPLE_SCALE: begin
                if (sampler_done) begin
                    next_token <= sampler_next_token;
                    state_reg <= ST_DONE;
                end
            end

            ST_DONE: begin
                busy <= 1'b0;
                done <= 1'b1;
                state_reg <= ST_IDLE;
            end

            default: begin
                state_reg <= ST_IDLE;
                busy <= 1'b0;
            end
        endcase
    end
end

endmodule
