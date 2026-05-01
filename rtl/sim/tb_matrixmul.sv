`timescale 1ns/1ps

module tb_matrixmul;
    localparam int M          = 3;
    localparam int DATA_WIDTH = 32;
    localparam int ACC_WIDTH  = 64;

    logic clk;
    logic rst_n;
    logic en;
    logic start;
    logic signed [(M*M*DATA_WIDTH)-1:0] matrix_a_flat;
    logic signed [(M*M*DATA_WIDTH)-1:0] matrix_b_flat;
    logic busy;
    logic done;
    logic signed [(M*M*ACC_WIDTH)-1:0] matrix_c_flat;

    logic signed [DATA_WIDTH-1:0] a_ref [0:M-1][0:M-1];
    logic signed [DATA_WIDTH-1:0] b_ref [0:M-1][0:M-1];
    logic signed [ACC_WIDTH-1:0]  c_exp [0:M-1][0:M-1];
    logic signed [ACC_WIDTH-1:0]  c_got [0:M-1][0:M-1];

    integer i;
    integer j;
    integer k;
    integer errors;

    matrixmul_unit #(
        .M(M),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .en(en),
        .start(start),
        .matrix_a_flat(matrix_a_flat),
        .matrix_b_flat(matrix_b_flat),
        .busy(busy),
        .done(done),
        .matrix_c_flat(matrix_c_flat)
    );

    always #5 clk = ~clk;

    task automatic pack_inputs;
        begin
            for (i = 0; i < M; i = i + 1) begin
                for (j = 0; j < M; j = j + 1) begin
                    matrix_a_flat[((i*M + j)*DATA_WIDTH) +: DATA_WIDTH] = a_ref[i][j];
                    matrix_b_flat[((i*M + j)*DATA_WIDTH) +: DATA_WIDTH] = b_ref[i][j];
                end
            end
        end
    endtask

    task automatic compute_expected;
        logic signed [ACC_WIDTH-1:0] acc;
        begin
            for (i = 0; i < M; i = i + 1) begin
                for (j = 0; j < M; j = j + 1) begin
                    acc = '0;
                    for (k = 0; k < M; k = k + 1) begin
                        acc = acc + (a_ref[i][k] * b_ref[k][j]);
                    end
                    c_exp[i][j] = acc;
                end
            end
        end
    endtask

    task automatic unpack_outputs;
        begin
            for (i = 0; i < M; i = i + 1) begin
                for (j = 0; j < M; j = j + 1) begin
                    c_got[i][j] = matrix_c_flat[((i*M + j)*ACC_WIDTH) +: ACC_WIDTH];
                end
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        en = 1'b0;
        start = 1'b0;
        matrix_a_flat = '0;
        matrix_b_flat = '0;
        errors = 0;

        a_ref[0][0] = 32'sd1;  a_ref[0][1] = 32'sd2;  a_ref[0][2] = 32'sd3;
        a_ref[1][0] = 32'sd4;  a_ref[1][1] = 32'sd5;  a_ref[1][2] = 32'sd6;
        a_ref[2][0] = 32'sd7;  a_ref[2][1] = 32'sd8;  a_ref[2][2] = 32'sd9;

        b_ref[0][0] = 32'sd9;  b_ref[0][1] = 32'sd8;  b_ref[0][2] = 32'sd7;
        b_ref[1][0] = 32'sd6;  b_ref[1][1] = 32'sd5;  b_ref[1][2] = 32'sd4;
        b_ref[2][0] = 32'sd3;  b_ref[2][1] = 32'sd2;  b_ref[2][2] = 32'sd1;

        compute_expected();
        pack_inputs();

        #20;
        en = 1'b1;
        rst_n = 1'b1;
        #10;

        start = 1'b1;
        #10;
        start = 1'b0;

        wait(done == 1'b1);
        #10;
        unpack_outputs();

        for (i = 0; i < M; i = i + 1) begin
            for (j = 0; j < M; j = j + 1) begin
                if (c_got[i][j] !== c_exp[i][j]) begin
                    $display("ERROR C[%0d][%0d]: got=%0d exp=%0d", i, j, c_got[i][j], c_exp[i][j]);
                    errors = errors + 1;
                end else begin
                    $display("OK C[%0d][%0d]=%0d", i, j, c_got[i][j]);
                end
            end
        end

        if (errors == 0) begin
            $display("PASS: matrix multiplication matches expected result.");
        end else begin
            $display("FAIL: %0d mismatches found.", errors);
        end

        #20;
        $finish;
    end

endmodule
