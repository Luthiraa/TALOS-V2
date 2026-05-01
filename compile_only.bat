@echo off
set "QUARTUS_SH=%QUARTUS_ROOTDIR%\bin64\quartus_sh.exe"
if not exist "%QUARTUS_SH%" set "QUARTUS_SH=C:\intelFPGA_lite\18.1\quartus\bin64\quartus_sh.exe"
if not exist "%QUARTUS_SH%" set "QUARTUS_SH=C:\intelFPGA\18.1\quartus\bin64\quartus_sh.exe"
if not exist "%QUARTUS_SH%" (
    echo quartus_sh.exe not found. Set QUARTUS_ROOTDIR or install Intel Quartus 18.1.
    exit /b 1
)
pushd "%~dp0rtl"
"%QUARTUS_SH%" --flow compile de1_soc_microgpt_rtl
set ERR=%ERRORLEVEL%
popd
exit /b %ERR%
