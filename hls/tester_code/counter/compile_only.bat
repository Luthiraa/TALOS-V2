@echo off
setlocal

pushd "%~dp0"

echo Compiling Quartus project...
"C:\intelFPGA\18.1\quartus\bin64\quartus_sh.exe" --flow compile de1_soc_hls_leds
set ERR=%ERRORLEVEL%

popd
exit /b %ERR%
