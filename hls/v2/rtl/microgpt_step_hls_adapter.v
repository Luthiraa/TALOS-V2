module microgpt_step_hls_adapter (
    input  wire        clock,
    input  wire        resetn,
    input  wire        start,
    output wire        busy,
    output wire        done,
    input  wire        stall,
    input  wire [7:0]  token_in,
    input  wire [7:0]  pos_in,
    input  wire        clear_cache,
    input  wire        sample_mode,
    input  wire [15:0] temperature_q8_8,
    input  wire [31:0] rng_state_in,
    output wire [7:0]  next_token,
    output wire [7:0]  argmax_token,
    output wire [31:0] rng_state_out,
    output wire signed [15:0] top1_logit_q11,
    output wire [7:0]  top2_token,
    output wire signed [15:0] top2_logit_q11
);

wire         hls_busy;
wire [79:0]  hls_in_stream_data;
wire [79:0]  hls_in_stream_data_mux;
wire         hls_in_stream_ready;
wire [87:0]  hls_out_stream_data;
wire         hls_out_stream_valid;
wire         hls_out_stream_ready;
wire         launch_req;
reg          start_pending;
reg  [79:0]  hls_in_stream_data_reg;
reg          hls_out_stream_ready_reg;
reg          hls_stall_reg;
reg          hls_in_stream_ready_reg;
reg          hls_busy_reg;
reg  [2:0]   sync_resetn;
reg  [7:0]   next_token_reg;
reg  [7:0]   argmax_token_reg;
reg  [31:0]  rng_state_out_reg;
reg  signed [15:0] top1_logit_q11_reg;
reg  [7:0]   top2_token_reg;
reg  signed [15:0] top2_logit_q11_reg;

assign launch_req = start | start_pending;
assign busy = hls_busy_reg | launch_req;
assign done = hls_out_stream_valid;
assign hls_in_stream_data = {
    rng_state_in,
    temperature_q8_8,
    {7'd0, sample_mode},
    {7'd0, clear_cache},
    pos_in,
    token_in
};
assign hls_in_stream_data_mux = start_pending ? hls_in_stream_data_reg : hls_in_stream_data;
assign hls_out_stream_ready = 1'b1;
assign next_token = hls_out_stream_valid ? hls_out_stream_data[7:0] : next_token_reg;
assign argmax_token = hls_out_stream_valid ? hls_out_stream_data[15:8] : argmax_token_reg;
assign rng_state_out = hls_out_stream_valid ? hls_out_stream_data[47:16] : rng_state_out_reg;
assign top1_logit_q11 = hls_out_stream_valid ? hls_out_stream_data[63:48] : top1_logit_q11_reg;
assign top2_token = hls_out_stream_valid ? hls_out_stream_data[71:64] : top2_token_reg;
assign top2_logit_q11 = hls_out_stream_valid ? hls_out_stream_data[87:72] : top2_logit_q11_reg;

always @(posedge clock or negedge resetn) begin
    if (!resetn) begin
        sync_resetn <= 3'b0;
        start_pending <= 1'b0;
        hls_in_stream_data_reg <= 80'd0;
        hls_out_stream_ready_reg <= 1'b0;
        hls_stall_reg <= 1'b0;
        hls_in_stream_ready_reg <= 1'b0;
        hls_busy_reg <= 1'b0;
        next_token_reg <= 8'd0;
        argmax_token_reg <= 8'd0;
        rng_state_out_reg <= 32'd0;
        top1_logit_q11_reg <= 16'sd0;
        top2_token_reg <= 8'd0;
        top2_logit_q11_reg <= 16'sd0;
    end else begin
        sync_resetn <= {sync_resetn[1:0], 1'b1};

        if (start) begin
            start_pending <= 1'b1;
            hls_in_stream_data_reg <= hls_in_stream_data;
        end

        if (launch_req && hls_in_stream_ready) begin
            start_pending <= 1'b0;
        end

        hls_out_stream_ready_reg <= hls_out_stream_ready;
        hls_stall_reg <= stall;
        hls_in_stream_ready_reg <= hls_in_stream_ready;
        hls_busy_reg <= hls_busy;

        if (hls_out_stream_valid) begin
            next_token_reg <= hls_out_stream_data[7:0];
            argmax_token_reg <= hls_out_stream_data[15:8];
            rng_state_out_reg <= hls_out_stream_data[47:16];
            top1_logit_q11_reg <= hls_out_stream_data[63:48];
            top2_token_reg <= hls_out_stream_data[71:64];
            top2_logit_q11_reg <= hls_out_stream_data[87:72];
        end
    end
end

microgpt_step_internal microgpt_step_hls_inst (
    .start(launch_req),
    .busy(hls_busy),
    .clock(clock),
    .in_stream_data(hls_in_stream_data_mux),
    .in_stream_ready(hls_in_stream_ready),
    .in_stream_valid(launch_req),
    .out_stream_data(hls_out_stream_data),
    .out_stream_ready(hls_out_stream_ready_reg),
    .out_stream_valid(hls_out_stream_valid),
    .resetn(sync_resetn[2]),
    .done(),
    .stall(hls_stall_reg)
);

endmodule
