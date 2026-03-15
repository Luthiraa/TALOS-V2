python tools/export_microgpt_weights.py
python tools/export_microgpt_roms.py
& 'C:\intelFPGA\18.1\quartus\sopc_builder\bin\qsys-script.exe' --script=qsys\create_jtag_microgpt_bridge.tcl
& 'C:\intelFPGA\18.1\quartus\sopc_builder\bin\qsys-generate.exe' 'jtag_microgpt_bridge.qsys' --synthesis=VERILOG
