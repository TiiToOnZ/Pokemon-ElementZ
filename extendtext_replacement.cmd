@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0extendtext_replacement.ps1" %*
endlocal
