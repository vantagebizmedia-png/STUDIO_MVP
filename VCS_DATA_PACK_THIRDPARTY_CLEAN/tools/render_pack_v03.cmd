@echo off
setlocal EnableExtensions
chcp 65001 >nul

REM Llama al wrapper PowerShell (forward seguro)
where pwsh >nul 2>nul && (set "PWSH=pwsh") || (set "PWSH=powershell")

%PWSH% -NoProfile -ExecutionPolicy Bypass -File "%~dp0render_pack_v03.ps1" -- %*
exit /b %ERRORLEVEL%
