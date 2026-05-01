set LIB "work_microgpt_core_[pid]"
vlib $LIB

vlog -nolock -sv -work $LIB +incdir+src/include \
    src/systolic_matvec16_tile.sv \
    src/rms_scale_engine.sv \
    src/sat_div16_engine.sv \
    src/microgpt_categorical_sampler.sv \
    src/microgpt_exact_core.sv \
    sim/tb_microgpt_core.sv

vsim $LIB.tb_microgpt_core
run -all
quit -f
