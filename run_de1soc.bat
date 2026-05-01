@echo off
call "%~dp0compile_only.bat"
if errorlevel 1 exit /b %ERRORLEVEL%
call "%~dp0program_fpga.bat"
exit /b %ERRORLEVEL%
