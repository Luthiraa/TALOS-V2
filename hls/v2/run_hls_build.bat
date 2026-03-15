@echo off
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul
set PATH=C:\intelFPGA\18.1\hls\bin;C:\intelFPGA\18.1\hls\host\windows64\bin;C:\intelFPGA\18.1\quartus\bin64;C:\intelFPGA\18.1\quartus\sopc_builder\bin;%PATH%
powershell -ExecutionPolicy Bypass -File scripts\build_hls.ps1
