module microgpt_step (
    input  wire        clock,
    input  wire        resetn,
    input  wire        start,
    output reg         busy,
    output reg         done,
    input  wire        stall,
    input  wire [7:0]  token_in,
    input  wire [7:0]  pos_in,
    input  wire        clear_cache,
    input  wire        sample_mode,
    input  wire [15:0] temperature_q8_8,
    input  wire [31:0] rng_state_in,
    output reg  [7:0]  next_token,
    output reg  [7:0]  argmax_token,
    output reg  [31:0] rng_state_out,
    output reg  signed [15:0] top1_logit_q11,
    output reg  [7:0]  top2_token,
    output reg  signed [15:0] top2_logit_q11,
    output reg  [63:0] logits_pack0,
    output reg  [63:0] logits_pack1,
    output reg  [63:0] logits_pack2,
    output reg  [63:0] logits_pack3,
    output reg  [63:0] logits_pack4,
    output reg  [63:0] logits_pack5,
    output reg  [63:0] logits_pack6
);

localparam integer EMBED_DIM = 16;
localparam integer VOCAB_SIZE = 27;
localparam [7:0] BOS_TOKEN = 8'd26;
localparam integer LOAD_X = 3'd1;
localparam integer RECUR = 3'd2;
localparam integer LOGITS = 3'd3;
localparam integer FINISH = 3'd4;

reg [2:0] state_reg;
reg [7:0] token_reg;
reg [7:0] pos_reg;
reg [4:0] idx_reg;
reg [4:0] row_reg;
reg [4:0] col_reg;

reg signed [31:0] acc_reg;
reg signed [15:0] x_vec [0:15];
reg signed [15:0] hidden_state [0:15];
reg signed [15:0] hidden_next [0:15];
reg signed [15:0] logits [0:26];
reg [7:0] best_idx_reg;
reg [7:0] second_idx_reg;
reg signed [15:0] best_logit_reg;
reg signed [15:0] second_logit_reg;

reg signed [15:0] wte_rom [0:431];
reg signed [15:0] wpe_rom [0:255];
reg signed [7:0]  wq_rom [0:255];
reg [15:0] wq_scale_rom [0:15];
reg signed [7:0]  lm_rom [0:431];
reg [15:0] lm_scale_rom [0:26];

integer i;
reg signed [31:0] acc_next;
reg signed [15:0] value16;
reg signed [15:0] logit16;

function [31:0] xorshift32;
    input [31:0] value;
    reg [31:0] tmp;
    begin
        tmp = value;
        tmp = tmp ^ (tmp << 13);
        tmp = tmp ^ (tmp >> 17);
        tmp = tmp ^ (tmp << 5);
        xorshift32 = tmp;
    end
endfunction

function signed [15:0] sat16;
    input signed [31:0] value;
    begin
        if (value > 32767)
            sat16 = 16'sd32767;
        else if (value < -32768)
            sat16 = 16'sh8000;
        else
            sat16 = value[15:0];
    end
endfunction

function signed [15:0] scale_q16;
    input signed [31:0] acc;
    input [15:0] scale;
    reg signed [47:0] prod;
    reg signed [47:0] rounded;
    begin
        prod = acc * $signed({1'b0, scale});
        if (prod >= 0)
            rounded = prod + 48'sd32768;
        else
            rounded = prod - 48'sd32768;
        scale_q16 = sat16(rounded >>> 16);
    end
endfunction

initial begin
    $readmemh("generated/wte_q.hex", wte_rom);
    $readmemh("generated/wpe_q.hex", wpe_rom);
    $readmemh("generated/wq_q.hex", wq_rom);
    $readmemh("generated/wq_scale_q16.hex", wq_scale_rom);
    $readmemh("generated/lm_q.hex", lm_rom);
    $readmemh("generated/lm_scale_q16.hex", lm_scale_rom);
end

always @(posedge clock or negedge resetn) begin
    if (!resetn) begin
        state_reg <= 3'd0;
        token_reg <= 8'd0;
        pos_reg <= 8'd0;
        idx_reg <= 5'd0;
        row_reg <= 5'd0;
        col_reg <= 5'd0;
        acc_reg <= 32'sd0;
        busy <= 1'b0;
        done <= 1'b0;
        next_token <= 8'd0;
        argmax_token <= 8'd0;
        rng_state_out <= 32'd0;
        top1_logit_q11 <= 16'sd0;
        top2_token <= 8'd0;
        top2_logit_q11 <= 16'sd0;
        logits_pack0 <= 64'd0;
        logits_pack1 <= 64'd0;
        logits_pack2 <= 64'd0;
        logits_pack3 <= 64'd0;
        logits_pack4 <= 64'd0;
        logits_pack5 <= 64'd0;
        logits_pack6 <= 64'd0;
        best_idx_reg <= 8'd0;
        second_idx_reg <= 8'd1;
        best_logit_reg <= 16'sh8000;
        second_logit_reg <= 16'sh8000;
        for (i = 0; i < EMBED_DIM; i = i + 1) begin
            x_vec[i] <= 16'sd0;
            hidden_state[i] <= 16'sd0;
            hidden_next[i] <= 16'sd0;
        end
        for (i = 0; i < VOCAB_SIZE; i = i + 1) begin
            logits[i] <= 16'sd0;
        end
    end else begin
        done <= 1'b0;
        if (!stall) begin
            case (state_reg)
                3'd0: begin
                    busy <= 1'b0;
                    if (start) begin
                        token_reg <= token_in;
                        pos_reg <= pos_in;
                        idx_reg <= 5'd0;
                        row_reg <= 5'd0;
                        col_reg <= 5'd0;
                        acc_reg <= 32'sd0;
                        best_idx_reg <= 8'd0;
                        second_idx_reg <= 8'd1;
                        best_logit_reg <= 16'sh8000;
                        second_logit_reg <= 16'sh8000;
                        rng_state_out <= xorshift32(rng_state_in);
                        if (clear_cache) begin
                            for (i = 0; i < EMBED_DIM; i = i + 1) begin
                                hidden_state[i] <= 16'sd0;
                            end
                        end
                        busy <= 1'b1;
                        state_reg <= LOAD_X[2:0];
                    end
                end

                LOAD_X: begin
                    value16 = sat16(
                        $signed(wte_rom[token_reg * EMBED_DIM + idx_reg]) +
                        $signed(wpe_rom[pos_reg * EMBED_DIM + idx_reg]) +
                        ($signed(hidden_state[idx_reg]) >>> 1)
                    );
                    x_vec[idx_reg] <= value16;
                    if (idx_reg == EMBED_DIM - 1) begin
                        row_reg <= 5'd0;
                        col_reg <= 5'd0;
                        acc_reg <= 32'sd0;
                        state_reg <= RECUR[2:0];
                    end else begin
                        idx_reg <= idx_reg + 5'd1;
                    end
                end

                RECUR: begin
                    acc_next = acc_reg + ($signed(wq_rom[row_reg * EMBED_DIM + col_reg]) * $signed(x_vec[col_reg]));
                    if (col_reg == EMBED_DIM - 1) begin
                        hidden_next[row_reg] <= scale_q16(acc_next, wq_scale_rom[row_reg]);
                        acc_reg <= 32'sd0;
                        col_reg <= 5'd0;
                        if (row_reg == EMBED_DIM - 1) begin
                            row_reg <= 5'd0;
                            state_reg <= LOGITS[2:0];
                        end else begin
                            row_reg <= row_reg + 5'd1;
                        end
                    end else begin
                        acc_reg <= acc_next;
                        col_reg <= col_reg + 5'd1;
                    end
                end

                LOGITS: begin
                    acc_next = acc_reg + ($signed(lm_rom[row_reg * EMBED_DIM + col_reg]) * $signed(x_vec[col_reg]));
                    if (col_reg == EMBED_DIM - 1) begin
                        logit16 = scale_q16(acc_next, lm_scale_rom[row_reg]);
                        logits[row_reg] <= logit16;
                        if (logit16 > best_logit_reg) begin
                            second_logit_reg <= best_logit_reg;
                            second_idx_reg <= best_idx_reg;
                            best_logit_reg <= logit16;
                            best_idx_reg <= {3'd0, row_reg};
                        end else if (logit16 > second_logit_reg) begin
                            second_logit_reg <= logit16;
                            second_idx_reg <= {3'd0, row_reg};
                        end
                        acc_reg <= 32'sd0;
                        col_reg <= 5'd0;
                        if (row_reg == VOCAB_SIZE - 1) begin
                            state_reg <= FINISH[2:0];
                        end else begin
                            row_reg <= row_reg + 5'd1;
                        end
                    end else begin
                        acc_reg <= acc_next;
                        col_reg <= col_reg + 5'd1;
                    end
                end

                FINISH: begin
                    for (i = 0; i < EMBED_DIM; i = i + 1) begin
                        hidden_state[i] <= hidden_next[i];
                    end
                    argmax_token <= best_idx_reg;
                    if (best_idx_reg == BOS_TOKEN)
                        next_token <= second_idx_reg;
                    else
                        next_token <= best_idx_reg;
                    top1_logit_q11 <= best_logit_reg;
                    top2_token <= second_idx_reg;
                    top2_logit_q11 <= second_logit_reg;
                    logits_pack0 <= {logits[3][15:0], logits[2][15:0], logits[1][15:0], logits[0][15:0]};
                    logits_pack1 <= {logits[7][15:0], logits[6][15:0], logits[5][15:0], logits[4][15:0]};
                    logits_pack2 <= {logits[11][15:0], logits[10][15:0], logits[9][15:0], logits[8][15:0]};
                    logits_pack3 <= {logits[15][15:0], logits[14][15:0], logits[13][15:0], logits[12][15:0]};
                    logits_pack4 <= {logits[19][15:0], logits[18][15:0], logits[17][15:0], logits[16][15:0]};
                    logits_pack5 <= {logits[23][15:0], logits[22][15:0], logits[21][15:0], logits[20][15:0]};
                    logits_pack6 <= {16'd0, logits[26][15:0], logits[25][15:0], logits[24][15:0]};
                    busy <= 1'b0;
                    done <= 1'b1;
                    state_reg <= 3'd0;
                end

                default: begin
                    state_reg <= 3'd0;
                    busy <= 1'b0;
                end
            endcase
        end
    end
end

wire unused_sample_mode = sample_mode;
wire [15:0] unused_temperature_q8_8 = temperature_q8_8;

endmodule
