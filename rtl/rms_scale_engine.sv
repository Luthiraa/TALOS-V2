module rms_scale_engine (
    input  logic               clk,
    input  logic               resetn,
    input  logic               start,
    input  logic [63:0]        sumsq,
    output logic               busy,
    output logic               done,
    output logic signed [15:0] scale_q12
);

    localparam logic [1:0]
        ST_IDLE = 2'd0,
        ST_SQRT = 2'd1,
        ST_DIV  = 2'd2;

    logic [1:0] state_reg;
    logic [63:0] radicand_reg;
    logic [65:0] rem_reg;
    logic [32:0] root_reg;
    logic [31:0] denom_reg;
    logic [5:0] iter_reg;

    logic [32:0] div_rem_reg;
    logic [24:0] div_quot_reg;
    logic [5:0] div_bit_reg;

    logic [65:0] rem_next;
    logic [32:0] root_shift;
    logic [33:0] cand_next;
    logic [32:0] div_rem_next;
    logic [24:0] div_quot_next;
    logic        div_in_bit;

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
            state_reg <= ST_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            scale_q12 <= 16'sd0;
            radicand_reg <= 64'd0;
            rem_reg <= 66'd0;
            root_reg <= 33'd0;
            denom_reg <= 32'd0;
            iter_reg <= 6'd0;
            div_rem_reg <= 33'd0;
            div_quot_reg <= 25'd0;
            div_bit_reg <= 6'd0;
        end else begin
            done <= 1'b0;

            case (state_reg)
                ST_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy <= 1'b1;
                        radicand_reg <= (((sumsq >> 4) + 64'd1) << 12);
                        rem_reg <= 66'd0;
                        root_reg <= 33'd0;
                        iter_reg <= 6'd31;
                        state_reg <= ST_SQRT;
                    end
                end

                ST_SQRT: begin
                    rem_next = (rem_reg << 2) | ((radicand_reg >> (iter_reg * 2)) & 64'd3);
                    root_shift = root_reg << 1;
                    cand_next = (root_shift << 1) | 34'd1;

                    if (rem_next >= cand_next) begin
                        rem_reg <= rem_next - cand_next;
                        root_reg <= root_shift + 33'd1;
                    end else begin
                        rem_reg <= rem_next;
                        root_reg <= root_shift;
                    end

                    if (iter_reg == 6'd0) begin
                        denom_reg <= (rem_next >= cand_next) ? (root_shift + 33'd1) : root_shift;
                        if (((rem_next >= cand_next) ? (root_shift + 33'd1) : root_shift) == 33'd0 ||
                            ((rem_next >= cand_next) ? (root_shift + 33'd1) : root_shift) <= 33'd512) begin
                            scale_q12 <= 16'sd32767;
                            busy <= 1'b0;
                            done <= 1'b1;
                            state_reg <= ST_IDLE;
                        end else begin
                            div_rem_reg <= 33'd0;
                            div_quot_reg <= 25'd0;
                            div_bit_reg <= 6'd24;
                            state_reg <= ST_DIV;
                        end
                    end else begin
                        iter_reg <= iter_reg - 6'd1;
                    end
                end

                ST_DIV: begin
                    div_in_bit = (div_bit_reg == 6'd24);
                    div_rem_next = {div_rem_reg[31:0], div_in_bit};
                    div_quot_next = div_quot_reg;

                    if (div_rem_next >= {1'b0, denom_reg}) begin
                        div_rem_next = div_rem_next - {1'b0, denom_reg};
                        div_quot_next[div_bit_reg] = 1'b1;
                    end

                    div_rem_reg <= div_rem_next;
                    div_quot_reg <= div_quot_next;

                    if (div_bit_reg == 6'd0) begin
                        scale_q12 <= sat16($signed({39'd0, div_quot_next}));
                        busy <= 1'b0;
                        done <= 1'b1;
                        state_reg <= ST_IDLE;
                    end else begin
                        div_bit_reg <= div_bit_reg - 6'd1;
                    end
                end

                default: begin
                    state_reg <= ST_IDLE;
                    busy <= 1'b0;
                end
            endcase
        end
    end

endmodule
