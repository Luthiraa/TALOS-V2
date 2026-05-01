initial begin
    $readmemh("generated/wte_q12.hex", wte_rom);
    $readmemh("generated/wpe_q12.hex", wpe_rom);
    $readmemh("generated/lm_head_q12.hex", lm_head_rom);
    $readmemh("generated/layer0_attn_wq_q12.hex", attn_wq_rom);
    $readmemh("generated/layer0_attn_wk_q12.hex", attn_wk_rom);
    $readmemh("generated/layer0_attn_wv_q12.hex", attn_wv_rom);
    $readmemh("generated/layer0_attn_wo_q12.hex", attn_wo_rom);
    $readmemh("generated/layer0_mlp_fc1_q12.hex", mlp_fc1_rom);
    $readmemh("generated/layer0_mlp_fc2_q12.hex", mlp_fc2_rom);
end
