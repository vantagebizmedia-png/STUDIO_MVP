@echo off
setlocal enabledelayedexpansion
REM Uso:
REM   tools\release_pack_v03.cmd "<v03_config>" "<script...>" [--overwrite]
REM Ej:
REM   tools\release_pack_v03.cmd "config\studio_v03_text_smoke.json" "hola bundle" --overwrite

set "CFG=%~1"
set "SCRIPT=%~2"
if "%CFG%"=="" (
  echo ERROR: falta v03_config
  exit /b 1
)
if "%SCRIPT%"=="" set "SCRIPT=hola live"

shift
shift
set "REST="
:LOOP
if "%~1"=="" goto RUN
set "REST=%REST% %~1"
shift
goto LOOP

:RUN
python tools\release_pack_v03.py --v03-config "%CFG%" --script "%SCRIPT%" %REST%
endlocal
