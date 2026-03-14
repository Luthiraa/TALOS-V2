@echo off
setlocal

pushd "%~dp0"

echo [1/3] Rebuilding HLS IP...
call "%~dp0run_hls_build.bat"
if errorlevel 1 goto :fail

echo [2/3] Compiling Quartus project...
"C:\intelFPGA\18.1\quartus\bin64\quartus_sh.exe" --flow compile de1_soc_hls_leds
if errorlevel 1 goto :fail

echo [3/3] Programming FPGA...
call "%~dp0program_fpga.bat"
if errorlevel 1 goto :fail

echo Done.
popd
exit /b 0

:fail
echo Flow failed.
popd
exit /b 1
