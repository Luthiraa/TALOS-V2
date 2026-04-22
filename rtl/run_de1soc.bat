@echo off
call compile_only.bat
if errorlevel 1 exit /b %ERRORLEVEL%
call program_fpga.bat
