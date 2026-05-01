@echo off
pushd "%~dp0rtl"
vsim -c -do "do sim/testbench_core.tcl"
set ERR=%ERRORLEVEL%
popd
exit /b %ERR%
