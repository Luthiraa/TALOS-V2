module systolic_matvec16_tile #(
    parameter int DATA_WIDTH = 16,
    parameter int ACC_WIDTH  = 64
) (
    input  logic                                      clk,
    input  logic                                      resetn,
    input  logic                                      start,
    input  logic signed [DATA_WIDTH-1:0]              vector_value,
    input  logic signed [(4*DATA_WIDTH)-1:0]          weights_flat,
    output logic [4:0]                                col_idx,
    output logic                                      busy,
    output logic                                      done,
    output logic signed [(4*ACC_WIDTH)-1:0]           result_flat
);

    localparam int COLS = 16;

    logic signed [ACC_WIDTH-1:0] acc [0:3];

    genvar lane;
    generate
        for (lane = 0; lane < 4; lane = lane + 1) begin : GEN_MAC_LANE
            wire signed [DATA_WIDTH-1:0] lane_weight;
            wire signed [DATA_WIDTH-1:0] lane_value;
            wire signed [ACC_WIDTH-1:0] lane_product;

            assign lane_weight = weights_flat[(lane*DATA_WIDTH) +: DATA_WIDTH];
            assign lane_value = vector_value;
            assign lane_product = $signed(lane_weight) * $signed(lane_value);

            assign result_flat[(lane*ACC_WIDTH) +: ACC_WIDTH] = acc[lane];

            always_ff @(posedge clk) begin
                if (!resetn) begin
                    acc[lane] <= '0;
                end else if (start && !busy) begin
                    acc[lane] <= '0;
                end else if (busy && (col_idx < COLS[4:0])) begin
                    acc[lane] <= acc[lane] + lane_product;
                end
            end
        end
    endgenerate

    always_ff @(posedge clk) begin
        if (!resetn) begin
            busy <= 1'b0;
            done <= 1'b0;
            col_idx <= 5'd0;
        end else begin
            done <= 1'b0;
            if (start && !busy) begin
                busy <= 1'b1;
                col_idx <= 5'd0;
            end else if (busy) begin
                if (col_idx == COLS[4:0]) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end else begin
                    col_idx <= col_idx + 5'd1;
                end
            end
        end
    end

endmodule
