@echo off
setlocal enabledelayedexpansion

REM Uso:
REM   tools\export_v03_pack.cmd "<manifest_path>" [--overwrite] [--out-root "..."]
REM Ej:
REM   tools\export_v03_pack.cmd "_v03_smoke_cfg\artifacts\manifest_v03.json" --overwrite

set "MAN=%~1"
if "%MAN%"=="" (
  echo ERROR: falta manifest path
  echo Ej: tools\export_v03_pack.cmd "_v03_smoke_cfg\artifacts\manifest_v03.json" --overwrite
  exit /b 1
)

REM Construye RESTO args desde %2..%9 sin romper comillas
set "REST="
shift
:LOOP
if "%~1"=="" goto RUN
set "REST=%REST% %~1"
shift
goto LOOP

:RUN
python tools\export_v03_pack.py --manifest "%MAN%" %REST%
endlocal
