module processing_element #(
    parameter int DATA_WIDTH = 32,
    parameter int ACC_WIDTH  = 64
) (
    input  logic                             clk,
    input  logic                             rst_n,
    input  logic                             en,
    input  logic                             clear,
    input  logic signed [DATA_WIDTH-1:0]     a_in,
    input  logic signed [DATA_WIDTH-1:0]     b_in,
    output logic signed [DATA_WIDTH-1:0]     a_out,
    output logic signed [DATA_WIDTH-1:0]     b_out,
    output logic signed [ACC_WIDTH-1:0]      acc_out
);

    logic signed [(2*DATA_WIDTH)-1:0] mul_full;
    logic signed [ACC_WIDTH-1:0] mul_ext;

    always_comb begin
        mul_full = a_in * b_in;
        mul_ext  = {{(ACC_WIDTH-(2*DATA_WIDTH)){mul_full[(2*DATA_WIDTH)-1]}}, mul_full};
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_out   <= '0;
            b_out   <= '0;
            acc_out <= '0;
        end else if (clear) begin
            a_out   <= '0;
            b_out   <= '0;
            acc_out <= '0;
        end else if (en) begin
            a_out   <= a_in;
            b_out   <= b_in;
            acc_out <= acc_out + mul_ext;
        end
    end

endmodule
