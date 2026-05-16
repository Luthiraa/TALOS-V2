function signed [15:0] sat16;
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

function signed [15:0] mul_q12;
    input signed [15:0] a;
    input signed [15:0] b;
    reg signed [63:0] p;
    begin
        p = $signed(a) * $signed(b);
        mul_q12 = sat16(p >>> FRAC_BITS);
    end
endfunction

function [31:0] xorshift32;
    input [31:0] value;
    reg [31:0] x;
    begin
        x = value;
        x = x ^ (x << 13);
        x = x ^ (x >> 17);
        x = x ^ (x << 5);
        xorshift32 = x;
    end
endfunction

function [31:0] isqrt64;
    input [63:0] value;
    reg [65:0] rem;
    reg [32:0] root;
    reg [33:0] cand;
    integer bit_idx;
    begin
        rem = 66'd0;
        root = 33'd0;
        for (bit_idx = 31; bit_idx >= 0; bit_idx = bit_idx - 1) begin
            rem = (rem << 2) | ((value >> (bit_idx * 2)) & 64'd3);
            root = root << 1;
            cand = (root << 1) | 34'd1;
            if (rem >= cand) begin
                rem = rem - cand;
                root = root + 33'd1;
            end
        end
        isqrt64 = root[31:0];
    end
endfunction

function signed [15:0] rms_scale_from_sum;
    input signed [63:0] sumsq;
    reg [63:0] ms_q12;
    reg [31:0] denom_q12;
    reg [63:0] scale_q12;
    begin
        ms_q12 = (sumsq / EMBED_DIM) + 64'd1;
        denom_q12 = isqrt64(ms_q12 * SCALE);
        if (denom_q12 == 0)
            scale_q12 = 64'd32767;
        else
            scale_q12 = (64'd4096 * 64'd4096) / denom_q12;
        rms_scale_from_sum = sat16(scale_q12);
    end
endfunction

function [31:0] exp_neg_q12;
    input signed [31:0] delta_q12;
    reg [5:0] index;
    begin
        if (delta_q12 >= 0) begin
            exp_neg_q12 = 32'd4096;
        end else begin
            index = ((-delta_q12) + 32'sd511) >>> 10;
            case (index)
                6'd0:  exp_neg_q12 = 32'd4096;
                6'd1:  exp_neg_q12 = 32'd3189;
                6'd2:  exp_neg_q12 = 32'd2484;
                6'd3:  exp_neg_q12 = 32'd1935;
                6'd4:  exp_neg_q12 = 32'd1507;
                6'd5:  exp_neg_q12 = 32'd1174;
                6'd6:  exp_neg_q12 = 32'd914;
                6'd7:  exp_neg_q12 = 32'd712;
                6'd8:  exp_neg_q12 = 32'd555;
                6'd9:  exp_neg_q12 = 32'd432;
                6'd10: exp_neg_q12 = 32'd337;
                6'd11: exp_neg_q12 = 32'd262;
                6'd12: exp_neg_q12 = 32'd204;
                6'd13: exp_neg_q12 = 32'd159;
                6'd14: exp_neg_q12 = 32'd124;
                6'd15: exp_neg_q12 = 32'd97;
                6'd16: exp_neg_q12 = 32'd75;
                6'd17: exp_neg_q12 = 32'd59;
                6'd18: exp_neg_q12 = 32'd46;
                6'd19: exp_neg_q12 = 32'd36;
                6'd20: exp_neg_q12 = 32'd28;
                6'd21: exp_neg_q12 = 32'd22;
                6'd22: exp_neg_q12 = 32'd17;
                6'd23: exp_neg_q12 = 32'd13;
                6'd24: exp_neg_q12 = 32'd10;
                6'd25: exp_neg_q12 = 32'd8;
                6'd26: exp_neg_q12 = 32'd6;
                6'd27: exp_neg_q12 = 32'd5;
                6'd28: exp_neg_q12 = 32'd4;
                6'd29: exp_neg_q12 = 32'd3;
                6'd30: exp_neg_q12 = 32'd2;
                default: exp_neg_q12 = 32'd1;
            endcase
        end
    end
endfunction
