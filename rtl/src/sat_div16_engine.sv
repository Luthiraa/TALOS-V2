module sat_div16_engine (
    input  logic               clk,
    input  logic               resetn,
    input  logic               start,
    input  logic signed [63:0] numerator,
    input  logic [31:0]        denominator,
    output logic               busy,
    output logic               done,
    output logic signed [15:0] quotient
);

    logic [63:0] num_reg;
    logic [31:0] denom_reg;
    logic [64:0] rem_reg;
    logic [63:0] quot_reg;
    logic [6:0] bit_reg;
    logic        neg_reg;

    logic [64:0] rem_next;
    logic [63:0] quot_next;
    logic signed [64:0] signed_quot_next;

    function automatic signed [15:0] sat16;
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

    always_ff @(posedge clk) begin
        if (!resetn) begin
            busy <= 1'b0;
            done <= 1'b0;
            quotient <= 16'sd0;
            num_reg <= 64'd0;
            denom_reg <= 32'd0;
            rem_reg <= 65'd0;
            quot_reg <= 64'd0;
            bit_reg <= 7'd0;
            neg_reg <= 1'b0;
        end else begin
            done <= 1'b0;

            if (!busy) begin
                if (start) begin
                    busy <= 1'b1;
                    neg_reg <= numerator[63];
                    num_reg <= numerator[63] ? (~numerator + 64'd1) : numerator[63:0];
                    denom_reg <= (denominator == 32'd0) ? 32'd1 : denominator;
                    rem_reg <= 65'd0;
                    quot_reg <= 64'd0;
                    // Attention numerator is sum(exp_q12 * value_q12) across at most
                    // 16 positions: 4096 * 32768 * 16 = 2^31. Starting at bit 31
                    // preserves the exact quotient and removes 32 dead divide cycles.
                    bit_reg <= 7'd31;
                end
            end else begin
                rem_next = {rem_reg[63:0], num_reg[bit_reg]};
                quot_next = quot_reg;
                if (rem_next >= {33'd0, denom_reg}) begin
                    rem_next = rem_next - {33'd0, denom_reg};
                    quot_next[bit_reg] = 1'b1;
                end

                rem_reg <= rem_next;
                quot_reg <= quot_next;

                if (bit_reg == 7'd0) begin
                    signed_quot_next = $signed({1'b0, quot_next});
                    if (neg_reg)
                        signed_quot_next = -signed_quot_next;
                    quotient <= sat16(signed_quot_next);
                    busy <= 1'b0;
                    done <= 1'b1;
                end else begin
                    bit_reg <= bit_reg - 7'd1;
                end
            end
        end
    end

endmodule
