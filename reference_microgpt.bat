@echo off
python "%~dp0rtl\python\karpathy_exact_reference.py" %*
set ERR=%ERRORLEVEL%
exit /b %ERR%
