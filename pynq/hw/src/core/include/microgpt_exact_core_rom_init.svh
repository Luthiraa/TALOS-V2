// PYNQ-Z2 port deviation: original DE1 paths "generated/<file>.hex" replaced
// with bare filenames so Vivado resolves them via the hw/ip include search
// path (set by build.tcl). Functional contents are unchanged.
initial begin
    $readmemh("wte_q12.hex", wte_rom);
    $readmemh("wpe_q12.hex", wpe_rom);
    $readmemh("lm_head_q12.hex", lm_head_rom);
    $readmemh("layer0_attn_wq_q12.hex", attn_wq_rom);
    $readmemh("layer0_attn_wk_q12.hex", attn_wk_rom);
    $readmemh("layer0_attn_wv_q12.hex", attn_wv_rom);
    $readmemh("layer0_attn_wo_q12.hex", attn_wo_rom);
    $readmemh("layer0_mlp_fc1_q12.hex", mlp_fc1_rom);
    $readmemh("layer0_mlp_fc2_q12.hex", mlp_fc2_rom);
end
