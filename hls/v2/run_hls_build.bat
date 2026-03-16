@echo off
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul
set PATH=C:\intelFPGA\18.1\hls\bin;C:\intelFPGA\18.1\hls\host\windows64\bin;C:\intelFPGA\18.1\quartus\bin64;C:\intelFPGA\18.1\quartus\sopc_builder\bin;%PATH%
cmd /v:on /c "C:\intelFPGA\18.1\hls\bin\i++.exe -Isrc -march=5CSEMA5F31C6 src\microgpt_step.cpp -o microgpt_step_fpga.exe --simulator none"
if errorlevel 1 exit /b %errorlevel%
powershell -ExecutionPolicy Bypass -File scripts\build_hls.ps1
