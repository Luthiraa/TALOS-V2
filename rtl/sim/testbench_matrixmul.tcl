set LIB "work_[pid]"
vlib $LIB

vlog -nolock -sv -work $LIB src/processing_element.sv src/matrixmul_unit.sv sim/tb_matrixmul.sv

vsim $LIB.tb_matrixmul
run -all
quit -f
