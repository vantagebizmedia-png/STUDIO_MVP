@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0a1111_models.ps1" %*
endlocal
