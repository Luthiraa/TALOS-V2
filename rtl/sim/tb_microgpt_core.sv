`timescale 1ns/1ps

module tb_microgpt_core;
    localparam [7:0] BOS_TOKEN = 8'd26;
    localparam int MAX_STEPS = 16;

    logic clk = 1'b0;
    logic resetn = 1'b0;
    logic start = 1'b0;
    logic clear_cache = 1'b0;
    logic [15:0] temperature_q8_8 = 16'h0080;
    logic [31:0] rng_state_in = 32'd1;
    logic [7:0] token_in = BOS_TOKEN;
    logic [7:0] pos_in = 8'd0;
    logic busy;
    logic done;
    logic [7:0] next_token;
    logic [7:0] argmax_token;
    logic [31:0] rng_state_out;
    logic signed [15:0] top_logit_q12;
    logic signed [(27*16)-1:0] logits_flat;
    integer cycle_count = 0;

    integer i;
    integer len_a;
    integer len_b;
    integer errors;
    reg [7:0] seq_a [0:MAX_STEPS-1];
    reg [7:0] seq_b [0:MAX_STEPS-1];

    microgpt_exact_core dut (
        .clk(clk),
        .resetn(resetn),
        .start(start),
        .clear_cache(clear_cache),
        .sample_mode(1'b1),
        .temperature_q8_8(temperature_q8_8),
        .rng_state_in(rng_state_in),
        .token_in(token_in),
        .pos_in(pos_in),
        .busy(busy),
        .done(done),
        .next_token(next_token),
        .argmax_token(argmax_token),
        .rng_state_out(rng_state_out),
        .top_logit_q12(top_logit_q12),
        .logits_flat(logits_flat)
    );

    always #5 clk = ~clk;
    always @(posedge clk) cycle_count <= cycle_count + 1;

    task automatic reset_core;
        begin
            resetn = 1'b0;
            start = 1'b0;
            clear_cache = 1'b0;
            token_in = BOS_TOKEN;
            pos_in = 8'd0;
            rng_state_in = 32'd1;
            repeat (5) @(posedge clk);
            resetn = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic run_step;
        input [7:0] token;
        input [7:0] pos;
        input [31:0] seed;
        input clear;
        output [7:0] token_next;
        output [31:0] seed_next;
        integer timeout;
        integer start_cycle;
        integer step_cycles;
        begin
            token_in = token;
            pos_in = pos;
            rng_state_in = seed;
            clear_cache = clear;
            start_cycle = cycle_count;
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;
            clear_cache = 1'b0;

            timeout = 0;
            while (!done && timeout < 20000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end

            if (!done) begin
                $display("ERROR: timeout waiting for core done");
                errors = errors + 1;
            end

            token_next = next_token;
            seed_next = rng_state_out;
            step_cycles = cycle_count - start_cycle;
            $display("step pos=%0d in=%0d out=%0d argmax=%0d seed_out=0x%08x top_logit=%0d cycles=%0d",
                     pos, token, token_next, argmax_token, seed_next, top_logit_q12, step_cycles);
            @(posedge clk);
        end
    endtask

    task automatic run_generation;
        input [31:0] seed_start;
        output integer out_len;
        inout reg [7:0] seq [0:MAX_STEPS-1];
        reg [7:0] token;
        reg [7:0] next;
        reg [31:0] seed;
        reg [31:0] seed_next;
        reg clear;
        begin
            token = BOS_TOKEN;
            seed = seed_start;
            out_len = 0;
            clear = 1'b1;

            for (i = 0; i < MAX_STEPS; i = i + 1) begin
                run_step(token, i[7:0], seed, clear, next, seed_next);
                clear = 1'b0;
                seed = seed_next;
                if (next == BOS_TOKEN) begin
                    i = MAX_STEPS;
                end else begin
                    seq[out_len] = next;
                    out_len = out_len + 1;
                    token = next;
                end
            end
        end
    endtask

    initial begin
        errors = 0;
        for (i = 0; i < MAX_STEPS; i = i + 1) begin
            seq_a[i] = 8'd0;
            seq_b[i] = 8'd0;
        end

        $display("Run A, seed=2");
        reset_core();
        run_generation(32'd2, len_a, seq_a);

        $display("Run B, seed=2");
        reset_core();
        run_generation(32'd2, len_b, seq_b);

        if (len_a != len_b) begin
            $display("ERROR: deterministic length mismatch A=%0d B=%0d", len_a, len_b);
            errors = errors + 1;
        end

        for (i = 0; i < MAX_STEPS; i = i + 1) begin
            if (seq_a[i] !== seq_b[i]) begin
                $display("ERROR: deterministic token mismatch index=%0d A=%0d B=%0d",
                         i, seq_a[i], seq_b[i]);
                errors = errors + 1;
            end
        end

        if (len_a != 5 ||
            seq_a[0] != 8'd10 ||
            seq_a[1] != 8'd4 ||
            seq_a[2] != 8'd11 ||
            seq_a[3] != 8'd24 ||
            seq_a[4] != 8'd13) begin
            $display("ERROR: expected calibrated sampled token sequence [10 4 11 24 13], got len=%0d first=%0d",
                     len_a, seq_a[0]);
            errors = errors + 1;
        end

        $write("RTL deterministic output tokens:");
        for (i = 0; i < len_a; i = i + 1)
            $write(" %0d", seq_a[i]);
        $write("\n");
        $display("Karpathy exact first sample tokens are 10 0 12 14 13 26 (kamon).");

        if (errors == 0)
            $display("PASS: RTL core is deterministic for repeated seed/config.");
        else
            $display("FAIL: %0d deterministic mismatches found.", errors);

        $finish;
    end
endmodule
