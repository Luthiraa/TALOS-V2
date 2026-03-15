@echo off
"C:\intelFPGA\18.1\quartus\bin64\quartus_pgm.exe" -c "DE-SoC [USB-1]" -m jtag -o "s;SOCVHPS@1" -o "p;de1_soc_microgpt.sof@2"
