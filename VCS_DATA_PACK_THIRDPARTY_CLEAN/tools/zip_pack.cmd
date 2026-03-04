@echo off
setlocal
REM Uso:
REM   tools\zip_pack.cmd "<pack_dir>" [--overwrite]
REM Ej:
REM   tools\zip_pack.cmd "_v03_smoke_cfg\workspace\exports\pack_v03_xxxx" --overwrite

set "PD=%~1"
if "%PD%"=="" (
  echo ERROR: falta pack_dir
  exit /b 1
)

shift
set "REST="
:LOOP
if "%~1"=="" goto RUN
set "REST=%REST% %~1"
shift
goto LOOP

:RUN
python tools\zip_pack.py --pack-dir "%PD%" %REST%
endlocal
