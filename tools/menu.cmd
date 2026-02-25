@echo off
setlocal

:MENU
echo.
echo ============================
echo        STUDIO_MVP MENU
echo ============================
echo 1) SMOKE v0.3 (offline)
echo 2) LIVE v0.3 (A1111 API)
echo 3) A1111 CHECK (ping + models)
echo 4) A1111 START (webui-user.bat --api)
echo 0) Salir
echo.
set /p CH=Elige opcion: 

if "%CH%"=="1" goto SMOKE
if "%CH%"=="2" goto LIVE
if "%CH%"=="3" goto CHECK
if "%CH%"=="4" goto START
if "%CH%"=="0" goto END

echo Opcion invalida.
goto MENU

:SMOKE
echo.
echo == Running SMOKE ==
call "%~dp0smoke_v03.cmd"
goto MENU

:CHECK
echo.
echo == A1111 CHECK ==
call "%~dp0a1111_ping.cmd"
call "%~dp0a1111_models.cmd"
goto MENU

:START
echo.
echo == Starting A1111 (new window) ==
if exist "C:\stable-diffusion-webui\webui-user.bat" (
  start "" cmd /c ""C:\stable-diffusion-webui\webui-user.bat" --api"
  echo Started. Wait until it shows http://127.0.0.1:7860
) else (
  echo ERROR: No encuentro C:\stable-diffusion-webui\webui-user.bat
)
goto MENU

:LIVE
echo.
echo == LIVE v0.3 ==
call "%~dp0a1111_ping.cmd" || (
  echo A1111 no responde. Usa opcion 4 para arrancar y vuelve.
  goto MENU
)

echo.
echo (Opcional) Elegir modelo por NUMERO:
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0a1111_choose_model.ps1"
echo.

set /p SCRIPT=Texto para --script (enter=hola live): 
if "%SCRIPT%"=="" set "SCRIPT=hola live"

REM Pasamos como 1 argumento (quoted) para conservar espacios
call "%~dp0run_live_v03.cmd" "%SCRIPT%"
goto MENU

:END
endlocal
