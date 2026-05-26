@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%SCRIPT_DIR%ReadRite.ps1" %*
endlocal
