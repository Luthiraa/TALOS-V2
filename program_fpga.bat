@echo off
pushd "%~dp0hls\v2"
call program_fpga.bat %*
set ERR=%ERRORLEVEL%
popd
exit /b %ERR%
