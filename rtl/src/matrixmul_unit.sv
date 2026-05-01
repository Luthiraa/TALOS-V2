module matrixmul_unit #(
    parameter int M          = 4,
    parameter int DATA_WIDTH = 32,
    parameter int ACC_WIDTH  = 64
) (
    input  logic                               clk,
    input  logic                               rst_n,
    input  logic                               en,
    input  logic                               start,
    input  logic signed [(M*M*DATA_WIDTH)-1:0] matrix_a_flat,
    input  logic signed [(M*M*DATA_WIDTH)-1:0] matrix_b_flat,
    output logic                               busy,
    output logic                               done,
    output logic signed [(M*M*ACC_WIDTH)-1:0]  matrix_c_flat
);

    localparam int TOTAL_CYCLES = (3 * M) - 2;
    localparam int COUNTER_W    = (TOTAL_CYCLES <= 1) ? 1 : $clog2(TOTAL_CYCLES + 1);

    logic [COUNTER_W-1:0] cycle_count;
    logic                 pe_clear;

    logic signed [DATA_WIDTH-1:0] a_mem [0:M-1][0:M-1];
    logic signed [DATA_WIDTH-1:0] b_mem [0:M-1][0:M-1];
    logic signed [DATA_WIDTH-1:0] a_inject [0:M-1];
    logic signed [DATA_WIDTH-1:0] b_inject [0:M-1];

    logic signed [DATA_WIDTH-1:0] pe_a_out [0:M-1][0:M-1];
    logic signed [DATA_WIDTH-1:0] pe_b_out [0:M-1][0:M-1];
    logic signed [ACC_WIDTH-1:0]  pe_acc_out [0:M-1][0:M-1];

    always_comb begin
        for (int i_c = 0; i_c < M; i_c = i_c + 1) begin
            int k_a;
            k_a = cycle_count - i_c;
            if (busy && (k_a >= 0) && (k_a < M)) begin
                a_inject[i_c] = a_mem[i_c][k_a];
            end else begin
                a_inject[i_c] = '0;
            end
        end

        for (int j_c = 0; j_c < M; j_c = j_c + 1) begin
            int k_b;
            k_b = cycle_count - j_c;
            if (busy && (k_b >= 0) && (k_b < M)) begin
                b_inject[j_c] = b_mem[k_b][j_c];
            end else begin
                b_inject[j_c] = '0;
            end
        end
    end

    genvar r;
    genvar c;
    generate
        for (r = 0; r < M; r = r + 1) begin : GEN_ROW
            for (c = 0; c < M; c = c + 1) begin : GEN_COL
                logic signed [DATA_WIDTH-1:0] a_in_wire;
                logic signed [DATA_WIDTH-1:0] b_in_wire;

                assign a_in_wire = (c == 0) ? a_inject[r] : pe_a_out[r][c-1];
                assign b_in_wire = (r == 0) ? b_inject[c] : pe_b_out[r-1][c];

                processing_element #(
                    .DATA_WIDTH(DATA_WIDTH),
                    .ACC_WIDTH(ACC_WIDTH)
                ) u_pe (
                    .clk(clk),
                    .rst_n(rst_n),
                    .en(en),
                    .clear(pe_clear),
                    .a_in(a_in_wire),
                    .b_in(b_in_wire),
                    .a_out(pe_a_out[r][c]),
                    .b_out(pe_b_out[r][c]),
                    .acc_out(pe_acc_out[r][c])
                );
            end
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy       <= 1'b0;
            done       <= 1'b0;
            pe_clear   <= 1'b0;
            cycle_count <= '0;
            matrix_c_flat <= '0;
            for (int i_s = 0; i_s < M; i_s = i_s + 1) begin
                for (int j_s = 0; j_s < M; j_s = j_s + 1) begin
                    a_mem[i_s][j_s] <= '0;
                    b_mem[i_s][j_s] <= '0;
                end
            end
        end else begin
            pe_clear <= 1'b0;

            if (en) begin
                if (start && !busy) begin
                    busy       <= 1'b1;
                    done       <= 1'b0;
                    pe_clear   <= 1'b1;
                    cycle_count <= '0;
                    matrix_c_flat <= '0;

                    for (int i_l = 0; i_l < M; i_l = i_l + 1) begin
                        for (int j_l = 0; j_l < M; j_l = j_l + 1) begin
                            a_mem[i_l][j_l] <= matrix_a_flat[((i_l*M + j_l)*DATA_WIDTH) +: DATA_WIDTH];
                            b_mem[i_l][j_l] <= matrix_b_flat[((i_l*M + j_l)*DATA_WIDTH) +: DATA_WIDTH];
                        end
                    end
                end else if (busy) begin
                    if (pe_clear) begin
                        pe_clear <= 1'b0;
                    end else if (cycle_count < TOTAL_CYCLES[COUNTER_W-1:0]) begin
                        cycle_count <= cycle_count + 1'b1;
                    end else begin
                        busy <= 1'b0;
                        done <= 1'b1;
                        for (int i_o = 0; i_o < M; i_o = i_o + 1) begin
                            for (int j_o = 0; j_o < M; j_o = j_o + 1) begin
                                matrix_c_flat[((i_o*M + j_o)*ACC_WIDTH) +: ACC_WIDTH] <= pe_acc_out[i_o][j_o];
                            end
                        end
                    end
                end
            end
        end
    end

endmodule
