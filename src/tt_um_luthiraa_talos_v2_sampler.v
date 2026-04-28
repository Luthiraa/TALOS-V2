/*
 * Copyright (c) 2026 Luthiraa
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_luthiraa_talos_v2_sampler (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
`ifdef USE_POWER_PINS
    input  wire       VPWR,
    input  wire       VGND,
`endif
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    localparam integer VOCAB_SIZE = 27;
    localparam [7:0] ARGMAX_TOKEN = 8'd0;
    localparam signed [15:0] TOP_LOGIT_Q12 = 16'sd4096;
    localparam [431:0] FIXED_LOGITS_FLAT = {
        16'sd0,
        16'sd128,
        16'sd256,
        16'sd384,
        16'sd512,
        16'sd640,
        16'sd768,
        16'sd832,
        16'sd896,
        16'sd1024,
        16'sd1088,
        16'sd1152,
        16'sd1216,
        16'sd1280,
        16'sd1408,
        16'sd1536,
        16'sd1664,
        16'sd1792,
        16'sd1920,
        16'sd2176,
        16'sd2432,
        16'sd2560,
        16'sd2816,
        16'sd3072,
        16'sd3328,
        16'sd3584,
        16'sd4096
    };

    reg start_d;
    reg start_q;
    wire start_pulse;

    wire [15:0] temperature_q8_8 = {8'h01, uio_in};
    wire [31:0] rng_state = {8'h53, ui_in[6:0], uio_in, 9'h12f};
    wire [431:0] logits_flat = FIXED_LOGITS_FLAT;

    wire sampler_busy;
    wire sampler_done;
    wire [7:0] next_token;

    assign start_pulse = start_d & ~start_q;

    always @(posedge clk) begin
        if (!rst_n) begin
            start_d <= 1'b0;
            start_q <= 1'b0;
        end else begin
            start_d <= ui_in[7] & ena;
            start_q <= start_d;
        end
    end

    microgpt_categorical_sampler #(
        .VOCAB_SIZE(VOCAB_SIZE)
    ) sampler_inst (
        .clk(clk),
        .resetn(rst_n),
        .start(start_pulse),
        .temperature_q8_8(temperature_q8_8),
        .rng_state(rng_state),
        .argmax_token(ARGMAX_TOKEN),
        .top_logit_q12(TOP_LOGIT_Q12),
        .logits_flat(logits_flat),
        .busy(sampler_busy),
        .done(sampler_done),
        .next_token(next_token)
    );

    assign uo_out[4:0] = next_token[4:0];
    assign uo_out[5] = sampler_busy;
    assign uo_out[6] = sampler_done;
    assign uo_out[7] = ARGMAX_TOKEN[0];

    assign uio_out = 8'h00;
    assign uio_oe  = 8'h00;

    wire _unused = &{
`ifdef USE_POWER_PINS
        VPWR,
        VGND,
`endif
        next_token[7:5],
        1'b0
    };

endmodule
