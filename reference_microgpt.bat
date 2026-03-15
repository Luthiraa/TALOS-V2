@echo off
pushd "%~dp0hls\v2"
python tools\reference_microgpt.py %*
set ERR=%ERRORLEVEL%
popd
exit /b %ERR%
