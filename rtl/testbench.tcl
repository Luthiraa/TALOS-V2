set LIB "work_[pid]"
vlib $LIB

vlog -nolock -sv -work $LIB processing_element.sv matrixmul_unit.sv tb_matrixmul.sv

vsim -c $LIB.tb_matrixmul -do "run -all; quit -f"
