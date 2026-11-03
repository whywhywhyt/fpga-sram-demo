@echo off
setlocal
cd /d "%~dp0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\portable_sram.ps1"
set "FPGA_RESULT=%ERRORLEVEL%"
echo.
if not "%FPGA_RESULT%"=="0" echo FAILED. See message above and the logs folder.
pause
exit /b %FPGA_RESULT%
