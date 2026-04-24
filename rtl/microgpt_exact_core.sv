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

localparam integer EMBED_DIM = 16;
localparam integer VOCAB_SIZE = 27;
localparam integer MLP_DIM = 64;
localparam integer N_HEAD = 4;
localparam integer HEAD_DIM = 4;
localparam integer FRAC_BITS = 12;
localparam integer SCALE = 1 << FRAC_BITS;

localparam [5:0]
    ST_IDLE             = 6'd0,
    ST_LOAD_X           = 6'd1,
    ST_RMS0_SUM         = 6'd2,
    ST_RMS0_APPLY       = 6'd3,
    ST_ATTN_SAVE_RES    = 6'd4,
    ST_ATTN_RMS_SUM     = 6'd5,
    ST_ATTN_RMS_APPLY   = 6'd6,
    ST_Q_LINEAR         = 6'd7,
    ST_K_LINEAR         = 6'd8,
    ST_V_LINEAR         = 6'd9,
    ST_CACHE_QKV        = 6'd10,
    ST_ATTN_DOT         = 6'd11,
    ST_ATTN_SOFT        = 6'd12,
    ST_ATTN_WO          = 6'd13,
    ST_ATTN_ADD         = 6'd14,
    ST_MLP_SAVE_RES     = 6'd15,
    ST_MLP_RMS_SUM      = 6'd16,
    ST_MLP_RMS_APPLY    = 6'd17,
    ST_FC1              = 6'd18,
    ST_FC2              = 6'd19,
    ST_MLP_ADD          = 6'd20,
    ST_LM_HEAD          = 6'd21,
    ST_SAMPLE           = 6'd22,
    ST_DONE             = 6'd23,
    ST_ATTN_SUM         = 6'd24,
    ST_ATTN_WEIGHT      = 6'd25,
    ST_ATTN_MAX         = 6'd26,
    ST_SAMPLE_MAX       = 6'd27,
    ST_SAMPLE_SUM       = 6'd28,
    ST_SAMPLE_PICK      = 6'd29,
    ST_RMS0_WAIT        = 6'd30,
    ST_ATTN_RMS_WAIT    = 6'd31,
    ST_MLP_RMS_WAIT     = 6'd32,
    ST_ATTN_DIV_WAIT    = 6'd33;

reg [5:0] state_reg;
reg [7:0] token_reg;
reg [7:0] pos_reg;
reg [6:0] row_reg;
reg [6:0] col_reg;
reg [3:0] idx_reg;
reg [1:0] head_reg;
reg [4:0] time_reg;

reg signed [63:0] acc_reg;
reg signed [63:0] sumsq_reg;
reg signed [63:0] linear_acc [0:15];
reg signed [15:0] rms_scale_reg;
reg signed [15:0] attn_max_reg;
reg [31:0] attn_weight_sum_reg;
reg [31:0] sample_weight_sum_reg;
reg [31:0] sample_cut_reg;
reg [31:0] sample_acc_reg;
reg [7:0] sample_choice_reg;
reg sample_found_reg;
reg rms_start_reg;
reg [63:0] rms_sumsq_reg;
reg attn_div_start_reg;
reg signed [63:0] attn_div_num_reg;
reg [31:0] attn_div_den_reg;

reg signed [15:0] x_vec [0:15];
reg signed [15:0] norm_vec [0:15];
reg signed [15:0] residual_vec [0:15];
reg signed [15:0] q_vec [0:15];
reg signed [15:0] k_vec [0:15];
reg signed [15:0] v_vec [0:15];
reg signed [15:0] x_attn [0:15];
reg signed [15:0] mlp_vec [0:63];
reg signed [15:0] logits [0:26];
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
reg [31:0] weight_sum_tmp;
reg [31:0] sample_cut_tmp;
reg [31:0] sample_acc_tmp;
reg [31:0] rng_tmp;
reg [7:0] token_choice_tmp;
reg [7:0] best_token_tmp;
reg sample_found_tmp;
reg systolic_start_reg;

reg signed [15:0] systolic_vector_value;
reg signed [(4*16)-1:0] systolic_weights_flat;
wire [4:0] systolic_col_idx;
wire systolic_busy;
wire systolic_done;
wire signed [(4*64)-1:0] systolic_result_flat;
wire rms_busy;
wire rms_done;
wire signed [15:0] rms_scale_out;
wire attn_div_busy;
wire attn_div_done;
wire signed [15:0] attn_div_quotient;

systolic_matvec16_tile #(
    .DATA_WIDTH(16),
    .ACC_WIDTH(64)
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

sat_div16_engine attn_div_inst (
    .clk(clk),
    .resetn(resetn),
    .start(attn_div_start_reg),
    .numerator(attn_div_num_reg),
    .denominator(attn_div_den_reg),
    .busy(attn_div_busy),
    .done(attn_div_done),
    .quotient(attn_div_quotient)
);

initial begin
    $readmemh("generated/wte_q12.hex", wte_rom);
    $readmemh("generated/wpe_q12.hex", wpe_rom);
    $readmemh("generated/lm_head_q12.hex", lm_head_rom);
    $readmemh("generated/layer0_attn_wq_q12.hex", attn_wq_rom);
    $readmemh("generated/layer0_attn_wk_q12.hex", attn_wk_rom);
    $readmemh("generated/layer0_attn_wv_q12.hex", attn_wv_rom);
    $readmemh("generated/layer0_attn_wo_q12.hex", attn_wo_rom);
    $readmemh("generated/layer0_mlp_fc1_q12.hex", mlp_fc1_rom);
    $readmemh("generated/layer0_mlp_fc2_q12.hex", mlp_fc2_rom);
end

always @(*) begin
    systolic_vector_value = 16'sd0;
    systolic_weights_flat = '0;

    case (state_reg)
        ST_Q_LINEAR: begin
            systolic_vector_value = norm_vec[systolic_col_idx];
            for (i = 0; i < 4; i = i + 1)
                systolic_weights_flat[(i*16) +: 16] = attn_wq_rom[(row_reg + i) * EMBED_DIM + systolic_col_idx];
        end

        ST_K_LINEAR: begin
            systolic_vector_value = norm_vec[systolic_col_idx];
            for (i = 0; i < 4; i = i + 1)
                systolic_weights_flat[(i*16) +: 16] = attn_wk_rom[(row_reg + i) * EMBED_DIM + systolic_col_idx];
        end

        ST_V_LINEAR: begin
            systolic_vector_value = norm_vec[systolic_col_idx];
            for (i = 0; i < 4; i = i + 1)
                systolic_weights_flat[(i*16) +: 16] = attn_wv_rom[(row_reg + i) * EMBED_DIM + systolic_col_idx];
        end

        ST_ATTN_WO: begin
            systolic_vector_value = x_attn[systolic_col_idx];
            for (i = 0; i < 4; i = i + 1)
                systolic_weights_flat[(i*16) +: 16] = attn_wo_rom[(row_reg + i) * EMBED_DIM + systolic_col_idx];
        end

        ST_FC1: begin
            systolic_vector_value = norm_vec[systolic_col_idx];
            for (i = 0; i < 4; i = i + 1)
                systolic_weights_flat[(i*16) +: 16] = mlp_fc1_rom[((row_reg + i) * EMBED_DIM) + systolic_col_idx];
        end

        ST_FC2: begin
            systolic_vector_value = mlp_vec[col_reg + systolic_col_idx];
            for (i = 0; i < 4; i = i + 1)
                systolic_weights_flat[(i*16) +: 16] = mlp_fc2_rom[((row_reg + i) * MLP_DIM) + col_reg + systolic_col_idx];
        end

        ST_LM_HEAD: begin
            systolic_vector_value = x_vec[systolic_col_idx];
            for (i = 0; i < 4; i = i + 1) begin
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

function signed [15:0] sat16;
    input signed [63:0] value;
    begin
        if (value > 64'sd32767)
            sat16 = 16'sd32767;
        else if (value < -64'sd32768)
            sat16 = 16'sh8000;
        else
            sat16 = value[15:0];
    end
endfunction

function signed [15:0] mul_q12;
    input signed [15:0] a;
    input signed [15:0] b;
    reg signed [63:0] p;
    begin
        p = $signed(a) * $signed(b);
        mul_q12 = sat16(p >>> FRAC_BITS);
    end
endfunction

function [31:0] xorshift32;
    input [31:0] value;
    reg [31:0] x;
    begin
        x = value;
        x = x ^ (x << 13);
        x = x ^ (x >> 17);
        x = x ^ (x << 5);
        xorshift32 = x;
    end
endfunction

function [31:0] isqrt64;
    input [63:0] value;
    reg [65:0] rem;
    reg [32:0] root;
    reg [33:0] cand;
    integer bit_idx;
    begin
        rem = 66'd0;
        root = 33'd0;
        for (bit_idx = 31; bit_idx >= 0; bit_idx = bit_idx - 1) begin
            rem = (rem << 2) | ((value >> (bit_idx * 2)) & 64'd3);
            root = root << 1;
            cand = (root << 1) | 34'd1;
            if (rem >= cand) begin
                rem = rem - cand;
                root = root + 33'd1;
            end
        end
        isqrt64 = root[31:0];
    end
endfunction

function signed [15:0] rms_scale_from_sum;
    input signed [63:0] sumsq;
    reg [63:0] ms_q12;
    reg [31:0] denom_q12;
    reg [63:0] scale_q12;
    begin
        ms_q12 = (sumsq / EMBED_DIM) + 64'd1;
        denom_q12 = isqrt64(ms_q12 * SCALE);
        if (denom_q12 == 0)
            scale_q12 = 64'd32767;
        else
            scale_q12 = (64'd4096 * 64'd4096) / denom_q12;
        rms_scale_from_sum = sat16(scale_q12);
    end
endfunction

function [31:0] exp_neg_q12;
    input signed [31:0] delta_q12;
    reg [5:0] index;
    begin
        if (delta_q12 >= 0) begin
            exp_neg_q12 = 32'd4096;
        end else begin
            index = ((-delta_q12) + 32'sd511) >>> 10;
            case (index)
                6'd0:  exp_neg_q12 = 32'd4096;
                6'd1:  exp_neg_q12 = 32'd3189;
                6'd2:  exp_neg_q12 = 32'd2484;
                6'd3:  exp_neg_q12 = 32'd1935;
                6'd4:  exp_neg_q12 = 32'd1507;
                6'd5:  exp_neg_q12 = 32'd1174;
                6'd6:  exp_neg_q12 = 32'd914;
                6'd7:  exp_neg_q12 = 32'd712;
                6'd8:  exp_neg_q12 = 32'd555;
                6'd9:  exp_neg_q12 = 32'd432;
                6'd10: exp_neg_q12 = 32'd337;
                6'd11: exp_neg_q12 = 32'd262;
                6'd12: exp_neg_q12 = 32'd204;
                6'd13: exp_neg_q12 = 32'd159;
                6'd14: exp_neg_q12 = 32'd124;
                6'd15: exp_neg_q12 = 32'd97;
                6'd16: exp_neg_q12 = 32'd75;
                6'd17: exp_neg_q12 = 32'd59;
                6'd18: exp_neg_q12 = 32'd46;
                6'd19: exp_neg_q12 = 32'd36;
                6'd20: exp_neg_q12 = 32'd28;
                6'd21: exp_neg_q12 = 32'd22;
                6'd22: exp_neg_q12 = 32'd17;
                6'd23: exp_neg_q12 = 32'd13;
                6'd24: exp_neg_q12 = 32'd10;
                6'd25: exp_neg_q12 = 32'd8;
                6'd26: exp_neg_q12 = 32'd6;
                6'd27: exp_neg_q12 = 32'd5;
                6'd28: exp_neg_q12 = 32'd4;
                6'd29: exp_neg_q12 = 32'd3;
                6'd30: exp_neg_q12 = 32'd2;
                default: exp_neg_q12 = 32'd1;
            endcase
        end
    end
endfunction

function signed [31:0] apply_temperature_delta;
    input signed [31:0] delta_q12;
    input [15:0] temp_q8_8;
    begin
        apply_temperature_delta = delta_q12;
        if (temp_q8_8 <= 16'd128)
            apply_temperature_delta = delta_q12 <<< 1;
        else if (temp_q8_8 > 16'd256 && temp_q8_8 <= 16'd512)
            apply_temperature_delta = delta_q12 >>> 1;
        else if (temp_q8_8 > 16'd512)
            apply_temperature_delta = delta_q12 >>> 2;
    end
endfunction

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
        head_reg <= 2'd0;
        time_reg <= 5'd0;
        acc_reg <= 64'sd0;
        sumsq_reg <= 64'sd0;
        systolic_start_reg <= 1'b0;
        rms_start_reg <= 1'b0;
        attn_div_start_reg <= 1'b0;
        rms_scale_reg <= 16'sd0;
        attn_max_reg <= 16'sd0;
        attn_weight_sum_reg <= 32'd0;
        sample_weight_sum_reg <= 32'd0;
        sample_cut_reg <= 32'd0;
        sample_acc_reg <= 32'd0;
        sample_choice_reg <= 8'd0;
        sample_found_reg <= 1'b0;
        rms_sumsq_reg <= 64'd0;
        attn_div_num_reg <= 64'sd0;
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
        for (i = 0; i < 16; i = i + 1)
            linear_acc[i] <= 64'sd0;
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
        rms_start_reg <= 1'b0;
        attn_div_start_reg <= 1'b0;
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
                x_vec[idx_reg] <= sat16($signed(wte_rom[token_reg * EMBED_DIM + idx_reg]) + $signed(wpe_rom[pos_reg * EMBED_DIM + idx_reg]));
                if (idx_reg == EMBED_DIM - 1) begin
                    idx_reg <= 4'd0;
                    sumsq_reg <= 64'sd0;
                    state_reg <= ST_RMS0_SUM;
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
                    state_reg <= ST_RMS0_APPLY;
                end
            end

            ST_RMS0_APPLY: begin
                x_vec[idx_reg] <= mul_q12(x_vec[idx_reg], rms_scale_reg);
                if (idx_reg == EMBED_DIM - 1) begin
                    state_reg <= ST_ATTN_SAVE_RES;
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
                    for (i = 0; i < 4; i = i + 1)
                        q_vec[row_reg + i] <= sat16($signed(systolic_result_flat[(i*64) +: 64]) >>> FRAC_BITS);
                    if (row_reg == 7'd12) begin
                        row_reg <= 7'd0;
                        state_reg <= ST_K_LINEAR;
                    end else begin
                        row_reg <= row_reg + 7'd4;
                    end
                end
            end

            ST_K_LINEAR: begin
                if (!systolic_busy && !systolic_done)
                    systolic_start_reg <= 1'b1;
                if (systolic_done) begin
                    for (i = 0; i < 4; i = i + 1)
                        k_vec[row_reg + i] <= sat16($signed(systolic_result_flat[(i*64) +: 64]) >>> FRAC_BITS);
                    if (row_reg == 7'd12) begin
                        row_reg <= 7'd0;
                        state_reg <= ST_V_LINEAR;
                    end else begin
                        row_reg <= row_reg + 7'd4;
                    end
                end
            end

            ST_V_LINEAR: begin
                if (!systolic_busy && !systolic_done)
                    systolic_start_reg <= 1'b1;
                if (systolic_done) begin
                    for (i = 0; i < 4; i = i + 1)
                        v_vec[row_reg + i] <= sat16($signed(systolic_result_flat[(i*64) +: 64]) >>> FRAC_BITS);
                    if (row_reg == 7'd12) begin
                        row_reg <= 7'd0;
                        state_reg <= ST_CACHE_QKV;
                    end else begin
                        row_reg <= row_reg + 7'd4;
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
                acc_next = acc_reg + ($signed(q_vec[head_reg * HEAD_DIM + col_reg]) * $signed(k_cache[time_reg][head_reg * HEAD_DIM + col_reg]));
                if (col_reg == HEAD_DIM - 1) begin
                    attn_scores[time_reg] <= sat16((acc_next >>> FRAC_BITS) >>> 1);
                    acc_reg <= 64'sd0;
                    col_reg <= 7'd0;
                    if (time_reg == pos_reg[4:0]) begin
                        state_reg <= ST_ATTN_SOFT;
                    end else begin
                        time_reg <= time_reg + 5'd1;
                    end
                end else begin
                    acc_reg <= acc_next;
                    col_reg <= col_reg + 7'd1;
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
                    state_reg <= ST_ATTN_WEIGHT;
                end else begin
                    time_reg <= time_reg + 5'd1;
                end
            end

            ST_ATTN_WEIGHT: begin
                delta_tmp = $signed(attn_scores[time_reg]) - $signed(attn_max_reg);
                weight_tmp = exp_neg_q12(delta_tmp);
                acc_next = acc_reg + ($signed({1'b0, weight_tmp[30:0]}) * $signed(v_cache[time_reg][head_reg * HEAD_DIM + col_reg]));
                if (time_reg == pos_reg[4:0]) begin
                    attn_div_num_reg <= acc_next;
                    attn_div_den_reg <= attn_weight_sum_reg;
                    acc_reg <= 64'sd0;
                    time_reg <= 5'd0;
                    state_reg <= ST_ATTN_DIV_WAIT;
                end else begin
                    acc_reg <= acc_next;
                    time_reg <= time_reg + 5'd1;
                end
            end

            ST_ATTN_DIV_WAIT: begin
                if (!attn_div_busy && !attn_div_done)
                    attn_div_start_reg <= 1'b1;
                if (attn_div_done) begin
                    x_attn[head_reg * HEAD_DIM + col_reg] <= attn_div_quotient;
                    if (col_reg == HEAD_DIM - 1) begin
                        col_reg <= 7'd0;
                        if (head_reg == N_HEAD - 1) begin
                            row_reg <= 7'd0;
                            col_reg <= 7'd0;
                            state_reg <= ST_ATTN_WO;
                        end else begin
                            head_reg <= head_reg + 2'd1;
                            state_reg <= ST_ATTN_DOT;
                        end
                    end else begin
                        col_reg <= col_reg + 7'd1;
                        state_reg <= ST_ATTN_WEIGHT;
                    end
                end
            end

            ST_ATTN_WO: begin
                if (!systolic_busy && !systolic_done)
                    systolic_start_reg <= 1'b1;
                if (systolic_done) begin
                    for (i = 0; i < 4; i = i + 1)
                        norm_vec[row_reg + i] <= sat16($signed(systolic_result_flat[(i*64) +: 64]) >>> FRAC_BITS);
                    if (row_reg == 7'd12) begin
                        row_reg <= 7'd0;
                        idx_reg <= 4'd0;
                        state_reg <= ST_ATTN_ADD;
                    end else begin
                        row_reg <= row_reg + 7'd4;
                    end
                end
            end

            ST_ATTN_ADD: begin
                x_vec[idx_reg] <= sat16($signed(norm_vec[idx_reg]) + $signed(residual_vec[idx_reg]));
                if (idx_reg == EMBED_DIM - 1) begin
                    state_reg <= ST_MLP_SAVE_RES;
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
                    for (i = 0; i < 4; i = i + 1) begin
                        value16 = sat16($signed(systolic_result_flat[(i*64) +: 64]) >>> FRAC_BITS);
                        mlp_vec[row_reg + i] <= value16[15] ? 16'sd0 : value16;
                    end
                    if (row_reg == 7'd60) begin
                        row_reg <= 7'd0;
                        col_reg <= 7'd0;
                        for (i = 0; i < 16; i = i + 1)
                            linear_acc[i] <= 64'sd0;
                        state_reg <= ST_FC2;
                    end else begin
                        row_reg <= row_reg + 7'd4;
                    end
                end
            end

            ST_FC2: begin
                if (!systolic_busy && !systolic_done)
                    systolic_start_reg <= 1'b1;
                if (systolic_done) begin
                    if (col_reg == 7'd48) begin
                        for (i = 0; i < 4; i = i + 1) begin
                            acc_next = linear_acc[row_reg + i] + $signed(systolic_result_flat[(i*64) +: 64]);
                            norm_vec[row_reg + i] <= sat16(acc_next >>> FRAC_BITS);
                            linear_acc[row_reg + i] <= 64'sd0;
                        end
                        if (row_reg == 7'd12) begin
                            row_reg <= 7'd0;
                            col_reg <= 7'd0;
                            idx_reg <= 4'd0;
                            state_reg <= ST_MLP_ADD;
                        end else begin
                            row_reg <= row_reg + 7'd4;
                            col_reg <= 7'd0;
                        end
                    end else begin
                        for (i = 0; i < 4; i = i + 1)
                            linear_acc[row_reg + i] <= linear_acc[row_reg + i] + $signed(systolic_result_flat[(i*64) +: 64]);
                        col_reg <= col_reg + 7'd16;
                    end
                end
            end

            ST_MLP_ADD: begin
                x_vec[idx_reg] <= sat16($signed(norm_vec[idx_reg]) + $signed(residual_vec[idx_reg]));
                if (idx_reg == EMBED_DIM - 1) begin
                    row_reg <= 7'd0;
                    col_reg <= 7'd0;
                    state_reg <= ST_LM_HEAD;
                end else begin
                    idx_reg <= idx_reg + 4'd1;
                end
            end

            ST_LM_HEAD: begin
                if (!systolic_busy && !systolic_done)
                    systolic_start_reg <= 1'b1;
                if (systolic_done) begin
                    for (i = 0; i < 4; i = i + 1) begin
                        if ((row_reg + i) < VOCAB_SIZE)
                            logits[row_reg + i] <= sat16($signed(systolic_result_flat[(i*64) +: 64]) >>> FRAC_BITS);
                    end
                    if (row_reg == 7'd24) begin
                        state_reg <= ST_SAMPLE;
                    end else begin
                        row_reg <= row_reg + 7'd4;
                    end
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
                        sample_weight_sum_reg <= 32'd0;
                        row_reg <= 7'd0;
                        state_reg <= ST_SAMPLE_SUM;
                    end else begin
                        next_token <= best_token_tmp;
                        state_reg <= ST_DONE;
                    end
                end else begin
                    row_reg <= row_reg + 7'd1;
                end
            end

            ST_SAMPLE_SUM: begin
                delta_tmp = apply_temperature_delta($signed(logits[row_reg]) - $signed(top_logit_q12), temperature_q8_8);
                weight_tmp = exp_neg_q12(delta_tmp);
                if (row_reg == VOCAB_SIZE - 1) begin
                    weight_sum_tmp = sample_weight_sum_reg + weight_tmp;
                    if (weight_sum_tmp == 32'd0)
                        weight_sum_tmp = 32'd1;
                    sample_weight_sum_reg <= weight_sum_tmp;
                    rng_tmp = rng_state_out;
                    sample_cut_tmp = {16'd0, rng_tmp[15:0]};
                    if (sample_cut_tmp >= weight_sum_tmp)
                        sample_cut_tmp = sample_cut_tmp - weight_sum_tmp;
                    sample_cut_reg <= sample_cut_tmp;
                    sample_acc_reg <= 32'd0;
                    sample_choice_reg <= argmax_token;
                    sample_found_reg <= 1'b0;
                    row_reg <= 7'd0;
                    state_reg <= ST_SAMPLE_PICK;
                end else begin
                    sample_weight_sum_reg <= sample_weight_sum_reg + weight_tmp;
                    row_reg <= row_reg + 7'd1;
                end
            end

            ST_SAMPLE_PICK: begin
                delta_tmp = apply_temperature_delta($signed(logits[row_reg]) - $signed(top_logit_q12), temperature_q8_8);
                weight_tmp = exp_neg_q12(delta_tmp);
                sample_acc_tmp = sample_acc_reg + weight_tmp;
                token_choice_tmp = sample_choice_reg;
                sample_found_tmp = sample_found_reg;
                if (!sample_found_tmp && (sample_acc_tmp > sample_cut_reg)) begin
                    token_choice_tmp = {1'b0, row_reg};
                    sample_found_tmp = 1'b1;
                end
                sample_acc_reg <= sample_acc_tmp;
                sample_choice_reg <= token_choice_tmp;
                sample_found_reg <= sample_found_tmp;
                if (row_reg == VOCAB_SIZE - 1) begin
                    next_token <= token_choice_tmp;
                    state_reg <= ST_DONE;
                end else begin
                    row_reg <= row_reg + 7'd1;
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
