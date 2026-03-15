@echo off
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul
set PATH=C:\intelFPGA\18.1\hls\bin;C:\intelFPGA\18.1\hls\host\windows64\bin;C:\intelFPGA\18.1\quartus\bin64;C:\intelFPGA\18.1\quartus\sopc_builder\bin;C:\intelFPGA\18.1\modelsim_ase\win32aloem;%PATH%
"C:\intelFPGA\18.1\hls\bin\i++.exe" -march=CycloneV -I"C:\intelFPGA\18.1\modelsim_ase\gcc-4.2.1-mingw32vc12\include" -I"C:\intelFPGA\18.1\modelsim_ase\gcc-4.2.1-mingw32vc12\lib\gcc\mingw32\4.2.1\include" hls_leds.cpp -o hls_leds_fpga.exe --simulator none
if exist "hls_leds_fpga.prj\components\switch_to_led" (
    if exist "components\switch_to_led" rmdir /S /Q "components\switch_to_led"
    xcopy /E /I /Y "hls_leds_fpga.prj\components\switch_to_led" "components\switch_to_led" >nul
)
if exist "components\switch_to_led\switch_to_led.qsys" (
    "C:\intelFPGA\18.1\quartus\sopc_builder\bin\qsys-generate.exe" "components\switch_to_led\switch_to_led.qsys" --synthesis=VERILOG
)
