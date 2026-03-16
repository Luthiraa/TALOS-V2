module microgpt_step_hls_adapter (
    input  wire        clock,
    input  wire        resetn,
    input  wire        start,
    output wire        busy,
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

wire         hls_busy;
wire [79:0]  hls_in_stream_data;
wire         hls_in_stream_ready;
wire [535:0] hls_out_stream_data;
wire         hls_out_stream_valid;
wire         hls_out_stream_ready;
reg          start_pending;
reg  [79:0]  hls_in_stream_data_reg;
reg          hls_in_stream_valid_reg;
reg          hls_out_stream_ready_reg;
reg          hls_start_reg;
reg          hls_stall_reg;
reg          hls_in_stream_ready_reg;
reg  [535:0] hls_out_stream_data_reg;
reg          hls_out_stream_valid_reg;
reg          hls_busy_reg;
reg  [2:0]   sync_resetn;

assign busy = hls_busy_reg | start_pending;
assign hls_in_stream_data = {
    rng_state_in,
    temperature_q8_8,
    {7'd0, sample_mode},
    {7'd0, clear_cache},
    pos_in,
    token_in
};
assign hls_out_stream_ready = 1'b1;

always @(posedge clock or negedge resetn) begin
    if (!resetn) begin
        sync_resetn <= 3'b0;
        done <= 1'b0;
        start_pending <= 1'b0;
        hls_in_stream_data_reg <= 80'd0;
        hls_in_stream_valid_reg <= 1'b0;
        hls_out_stream_ready_reg <= 1'b0;
        hls_start_reg <= 1'b0;
        hls_stall_reg <= 1'b0;
        hls_in_stream_ready_reg <= 1'b0;
        hls_out_stream_data_reg <= 536'd0;
        hls_out_stream_valid_reg <= 1'b0;
        hls_busy_reg <= 1'b0;
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
    end else begin
        sync_resetn <= {sync_resetn[1:0], 1'b1};
        done <= 1'b0;

        if (start) begin
            start_pending <= 1'b1;
            hls_in_stream_data_reg <= hls_in_stream_data;
        end

        hls_in_stream_valid_reg <= start_pending;
        hls_start_reg <= start_pending;
        if (start_pending && hls_in_stream_ready) begin
            start_pending <= 1'b0;
        end

        hls_out_stream_ready_reg <= hls_out_stream_ready;
        hls_stall_reg <= stall;
        hls_in_stream_ready_reg <= hls_in_stream_ready;
        hls_out_stream_data_reg <= hls_out_stream_data;
        hls_out_stream_valid_reg <= hls_out_stream_valid;
        hls_busy_reg <= hls_busy;

        if (hls_out_stream_valid_reg) begin
            done <= 1'b1;
            next_token <= hls_out_stream_data_reg[7:0];
            argmax_token <= hls_out_stream_data_reg[15:8];
            rng_state_out <= hls_out_stream_data_reg[47:16];
            top1_logit_q11 <= hls_out_stream_data_reg[63:48];
            top2_token <= hls_out_stream_data_reg[71:64];
            top2_logit_q11 <= hls_out_stream_data_reg[87:72];
            logits_pack0 <= hls_out_stream_data_reg[151:88];
            logits_pack1 <= hls_out_stream_data_reg[215:152];
            logits_pack2 <= hls_out_stream_data_reg[279:216];
            logits_pack3 <= hls_out_stream_data_reg[343:280];
            logits_pack4 <= hls_out_stream_data_reg[407:344];
            logits_pack5 <= hls_out_stream_data_reg[471:408];
            logits_pack6 <= hls_out_stream_data_reg[535:472];
        end
    end
end

microgpt_step_internal microgpt_step_hls_inst (
    .start(hls_start_reg),
    .busy(hls_busy),
    .clock(clock),
    .in_stream_data(hls_in_stream_data_reg),
    .in_stream_ready(hls_in_stream_ready),
    .in_stream_valid(hls_in_stream_valid_reg),
    .out_stream_data(hls_out_stream_data),
    .out_stream_ready(hls_out_stream_ready_reg),
    .out_stream_valid(hls_out_stream_valid),
    .resetn(sync_resetn[2]),
    .done(),
    .stall(hls_stall_reg)
);

endmodule
