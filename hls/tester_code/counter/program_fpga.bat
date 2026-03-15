@echo off
"C:\intelFPGA\18.1\quartus\bin64\quartus_pgm.exe" -m JTAG -c "DE-SoC [USB-1]" -o "p;%~dp0de1_soc_hls_leds.sof@2"
