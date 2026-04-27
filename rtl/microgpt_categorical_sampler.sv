module microgpt_categorical_sampler #(
    parameter integer VOCAB_SIZE = 27
) (
    input  wire                             clk,
    input  wire                             resetn,
    input  wire                             start,
    input  wire [15:0]                      temperature_q8_8,
    input  wire [31:0]                      rng_state,
    input  wire [7:0]                       argmax_token,
    input  wire signed [15:0]               top_logit_q12,
    input  wire signed [(VOCAB_SIZE*16)-1:0] logits_flat,
    output reg                              busy,
    output reg                              done,
    output reg [7:0]                        next_token
);

localparam [3:0]
    ST_IDLE       = 4'd0,
    ST_SUM        = 4'd1,
    ST_SUM_WEIGHT = 4'd2,
    ST_SUM_ACC    = 4'd3,
    ST_MIX        = 4'd4,
    ST_SCALE      = 4'd5,
    ST_CUT        = 4'd6,
    ST_PICK       = 4'd7,
    ST_DONE       = 4'd8;

reg [3:0] state_reg;
reg [6:0] row_reg;
reg [6:0] sum_row_reg;
reg [31:0] weight_sum_reg;
reg [31:0] cut_reg;
reg [31:0] acc_reg;
reg [31:0] mixed_rng_reg;
reg [63:0] scaled_cut_reg;
reg [7:0] choice_reg;
reg found_reg;
reg [31:0] sample_weight [0:VOCAB_SIZE-1];
reg [31:0] weight_pipe_reg;
reg [7:0] fine_index_reg;
reg delta_nonneg_reg;
reg sum_last_reg;

reg signed [31:0] delta_tmp;
reg [31:0] weight_tmp;
reg [31:0] sum_tmp;
reg [31:0] acc_tmp;
reg [7:0] choice_tmp;
reg found_tmp;
reg [5:0] coarse_index_tmp;
reg [1:0] frac_index_tmp;
reg [31:0] w0_tmp;
reg [31:0] w1_tmp;
reg [31:0] diff_tmp;
integer i;

wire signed [15:0] current_logit =
    logits_flat[(row_reg * 16) +: 16];

function automatic signed [31:0] apply_temperature_delta;
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

function automatic [31:0] exp_neg_coarse_q12;
    input [5:0] index;
    begin
        case (index)
            6'd0:  exp_neg_coarse_q12 = 32'd4096;
            6'd1:  exp_neg_coarse_q12 = 32'd3189;
            6'd2:  exp_neg_coarse_q12 = 32'd2484;
            6'd3:  exp_neg_coarse_q12 = 32'd1935;
            6'd4:  exp_neg_coarse_q12 = 32'd1507;
            6'd5:  exp_neg_coarse_q12 = 32'd1174;
            6'd6:  exp_neg_coarse_q12 = 32'd914;
            6'd7:  exp_neg_coarse_q12 = 32'd712;
            6'd8:  exp_neg_coarse_q12 = 32'd555;
            6'd9:  exp_neg_coarse_q12 = 32'd432;
            6'd10: exp_neg_coarse_q12 = 32'd337;
            6'd11: exp_neg_coarse_q12 = 32'd262;
            6'd12: exp_neg_coarse_q12 = 32'd204;
            6'd13: exp_neg_coarse_q12 = 32'd159;
            6'd14: exp_neg_coarse_q12 = 32'd124;
            6'd15: exp_neg_coarse_q12 = 32'd97;
            6'd16: exp_neg_coarse_q12 = 32'd75;
            6'd17: exp_neg_coarse_q12 = 32'd59;
            6'd18: exp_neg_coarse_q12 = 32'd46;
            6'd19: exp_neg_coarse_q12 = 32'd36;
            6'd20: exp_neg_coarse_q12 = 32'd28;
            6'd21: exp_neg_coarse_q12 = 32'd22;
            6'd22: exp_neg_coarse_q12 = 32'd17;
            6'd23: exp_neg_coarse_q12 = 32'd13;
            6'd24: exp_neg_coarse_q12 = 32'd10;
            6'd25: exp_neg_coarse_q12 = 32'd8;
            6'd26: exp_neg_coarse_q12 = 32'd6;
            6'd27: exp_neg_coarse_q12 = 32'd5;
            6'd28: exp_neg_coarse_q12 = 32'd4;
            6'd29: exp_neg_coarse_q12 = 32'd3;
            6'd30: exp_neg_coarse_q12 = 32'd2;
            default: exp_neg_coarse_q12 = 32'd1;
        endcase
    end
endfunction

function automatic [31:0] exp_neg_sample_q12;
    input signed [31:0] delta_q12;
    reg [7:0] fine_index;
    reg [5:0] coarse_index;
    reg [1:0] frac_index;
    reg [31:0] w0;
    reg [31:0] w1;
    reg [31:0] diff;
    begin
        if (delta_q12 >= 0) begin
            exp_neg_sample_q12 = 32'd4096;
        end else begin
            fine_index = ((-delta_q12) + 32'sd127) >>> 8;
            coarse_index = fine_index[7:2];
            frac_index = fine_index[1:0];
            w0 = exp_neg_coarse_q12(coarse_index);
            w1 = exp_neg_coarse_q12(coarse_index + 6'd1);
            diff = w0 - w1;
            exp_neg_sample_q12 = w0 - ((diff * {30'd0, frac_index}) >>> 2);
            if (exp_neg_sample_q12 == 32'd0)
                exp_neg_sample_q12 = 32'd1;
        end
    end
endfunction

always @(posedge clk) begin
    if (!resetn) begin
        state_reg <= ST_IDLE;
        row_reg <= 7'd0;
        sum_row_reg <= 7'd0;
        weight_sum_reg <= 32'd0;
        cut_reg <= 32'd0;
        acc_reg <= 32'd0;
        mixed_rng_reg <= 32'd0;
        scaled_cut_reg <= 64'd0;
        choice_reg <= 8'd0;
        found_reg <= 1'b0;
        weight_pipe_reg <= 32'd0;
        fine_index_reg <= 8'd0;
        delta_nonneg_reg <= 1'b0;
        sum_last_reg <= 1'b0;
        next_token <= 8'd0;
        busy <= 1'b0;
        done <= 1'b0;
        for (i = 0; i < VOCAB_SIZE; i = i + 1)
            sample_weight[i] <= 32'd0;
    end else begin
        done <= 1'b0;

        case (state_reg)
            ST_IDLE: begin
                busy <= 1'b0;
                if (start) begin
                    row_reg <= 7'd0;
                    sum_row_reg <= 7'd0;
                    weight_sum_reg <= 32'd0;
                    cut_reg <= 32'd0;
                    acc_reg <= 32'd0;
                    choice_reg <= argmax_token;
                    found_reg <= 1'b0;
                    weight_pipe_reg <= 32'd0;
                    fine_index_reg <= 8'd0;
                    delta_nonneg_reg <= 1'b0;
                    sum_last_reg <= 1'b0;
                    busy <= 1'b1;
                    state_reg <= ST_SUM;
                end
            end

            ST_SUM: begin
                delta_tmp = apply_temperature_delta(
                    $signed(current_logit) - $signed(top_logit_q12),
                    temperature_q8_8
                );
                sum_row_reg <= row_reg;
                sum_last_reg <= (row_reg == VOCAB_SIZE - 1);
                if (delta_tmp >= 0) begin
                    delta_nonneg_reg <= 1'b1;
                    fine_index_reg <= 8'd0;
                end else begin
                    delta_nonneg_reg <= 1'b0;
                    fine_index_reg <= ((-delta_tmp) + 32'sd127) >>> 8;
                end
                state_reg <= ST_SUM_WEIGHT;
            end

            ST_SUM_WEIGHT: begin
                if (delta_nonneg_reg) begin
                    weight_pipe_reg <= 32'd4096;
                end else begin
                    coarse_index_tmp = fine_index_reg[7:2];
                    frac_index_tmp = fine_index_reg[1:0];
                    w0_tmp = exp_neg_coarse_q12(coarse_index_tmp);
                    w1_tmp = exp_neg_coarse_q12(coarse_index_tmp + 6'd1);
                    diff_tmp = w0_tmp - w1_tmp;
                    weight_pipe_reg <= w0_tmp - ((diff_tmp * {30'd0, frac_index_tmp}) >>> 2);
                    if ((w0_tmp - ((diff_tmp * {30'd0, frac_index_tmp}) >>> 2)) == 32'd0)
                        weight_pipe_reg <= 32'd1;
                end
                state_reg <= ST_SUM_ACC;
            end

            ST_SUM_ACC: begin
                weight_tmp = weight_pipe_reg;
                sum_tmp = weight_sum_reg + weight_tmp;
                sample_weight[sum_row_reg] <= weight_tmp;
                weight_sum_reg <= sum_tmp;
                if (sum_last_reg) begin
                    if (sum_tmp == 32'd0)
                        weight_sum_reg <= 32'd1;
                    row_reg <= 7'd0;
                    state_reg <= ST_MIX;
                end else begin
                    row_reg <= sum_row_reg + 7'd1;
                    state_reg <= ST_SUM;
                end
            end

            ST_MIX: begin
                mixed_rng_reg <= rng_state * 32'h000149FB;
                state_reg <= ST_SCALE;
            end

            ST_SCALE: begin
                scaled_cut_reg <= {40'd0, mixed_rng_reg[31:8]} * {32'd0, weight_sum_reg};
                state_reg <= ST_CUT;
            end

            ST_CUT: begin
                cut_reg <= scaled_cut_reg[55:24];
                if (scaled_cut_reg[55:24] >= weight_sum_reg)
                    cut_reg <= weight_sum_reg - 32'd1;
                acc_reg <= 32'd0;
                choice_reg <= argmax_token;
                found_reg <= 1'b0;
                row_reg <= 7'd0;
                state_reg <= ST_PICK;
            end

            ST_PICK: begin
                weight_tmp = sample_weight[row_reg];
                acc_tmp = acc_reg + weight_tmp;
                choice_tmp = choice_reg;
                found_tmp = found_reg;
                if (!found_tmp && (acc_tmp > cut_reg)) begin
                    choice_tmp = {1'b0, row_reg};
                    found_tmp = 1'b1;
                end
                acc_reg <= acc_tmp;
                choice_reg <= choice_tmp;
                found_reg <= found_tmp;
                if (row_reg == VOCAB_SIZE - 1) begin
                    next_token <= choice_tmp;
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
