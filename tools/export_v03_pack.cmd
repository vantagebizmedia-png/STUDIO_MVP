@echo off
setlocal
REM Uso:
REM   tools\export_v03_pack.cmd "<manifest_path>" [--overwrite]
REM Ej:
REM   tools\export_v03_pack.cmd "_v03_smoke_cfg\artifacts\manifest_v03.json" --overwrite

set "MAN=%~1"
if "%MAN%"=="" (
  echo ERROR: falta manifest path
  echo Ej: tools\export_v03_pack.cmd "_v03_smoke_cfg\artifacts\manifest_v03.json" --overwrite
  exit /b 1
)

shift
python tools\export_v03_pack.py --manifest "%MAN%" %*
endlocal
