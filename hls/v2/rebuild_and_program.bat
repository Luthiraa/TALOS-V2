@echo off
call run_hls_build.bat
call compile_only.bat
call generate_rbf.bat
call program_fpga.bat
