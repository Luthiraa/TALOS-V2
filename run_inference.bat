@echo off
pushd "%~dp0hls\v2"
call run_inference.bat %*
set ERR=%ERRORLEVEL%
popd
exit /b %ERR%
