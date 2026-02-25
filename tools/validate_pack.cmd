@echo off
setlocal enabledelayedexpansion
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
python tools\validate_pack.py --pack-dir "%PD%" %REST%
endlocal
