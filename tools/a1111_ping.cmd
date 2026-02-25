@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0a1111_ping.ps1" %*
endlocal
