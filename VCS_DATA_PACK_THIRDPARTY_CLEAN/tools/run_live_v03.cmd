@echo off
setlocal
set "STUDIO_ALLOW_LIVE=1"

REM Si no pasaron args, default con comillas (para espacios)
if "%~1"=="" (
  set SCRIPT="hola live"
) else (
  REM %* mantiene las comillas si el caller las puso
  set SCRIPT=%*
)

python -m cli.main --v03-config .\config\studio_v03_live_a1111.json --script %SCRIPT%
endlocal
