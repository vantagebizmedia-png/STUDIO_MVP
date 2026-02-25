@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0a1111_set_model.ps1" %*
endlocal
