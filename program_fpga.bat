@echo off
set "QUARTUS_PGM=%QUARTUS_ROOTDIR%\bin64\quartus_pgm.exe"
if not exist "%QUARTUS_PGM%" set "QUARTUS_PGM=C:\intelFPGA_lite\18.1\quartus\bin64\quartus_pgm.exe"
if not exist "%QUARTUS_PGM%" set "QUARTUS_PGM=C:\intelFPGA\18.1\quartus\bin64\quartus_pgm.exe"
if not exist "%QUARTUS_PGM%" (
    echo quartus_pgm.exe not found. Set QUARTUS_ROOTDIR or install Intel Quartus 18.1.
    exit /b 1
)
"%QUARTUS_PGM%" -c "DE-SoC [USB-1]" -m jtag -o "p;%~dp0rtl\de1_soc_microgpt_rtl.sof@2"
set ERR=%ERRORLEVEL%
exit /b %ERR%
