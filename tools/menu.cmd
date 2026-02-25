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
echo 5) LIVE rapido (A1111, sin preguntas)
echo 6) LIMPIAR outputs locales
echo 7) LIVE con prompt (A1111)
echo 8) LIVE con prompt + elegir modelo
echo 0) Salir
echo.
set /p CH=Elige opcion: 

if "%CH%"=="1" goto SMOKE
if "%CH%"=="2" goto LIVE
if "%CH%"=="3" goto CHECK
if "%CH%"=="4" goto START
if "%CH%"=="5" goto LIVERAPIDO
if "%CH%"=="6" goto CLEAN
if "%CH%"=="7" goto LIVEPROMPT
if "%CH%"=="8" goto LIVEPROMPTMODEL
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

:LIVERAPIDO
echo.
echo == LIVE rapido ==
call "%~dp0a1111_ping.cmd" || ( echo A1111 no responde. Usa opcion 4 y vuelve. & goto MENU )
call "%~dp0run_live_v03.cmd" "hola live"
goto MENU

:CLEAN
echo.
echo == CLEAN outputs ==
call "%~dp0clean_outputs.cmd"
goto MENU

:LIVEPROMPT
echo.
echo == LIVE con prompt ==
call "%~dp0a1111_ping.cmd" || ( echo A1111 no responde. Usa opcion 4 y vuelve. & goto MENU )
call "%~dp0run_live_prompt.cmd"
goto MENU

:LIVEPROMPTMODEL
echo.
echo == LIVE con prompt + elegir modelo ==
call "%~dp0a1111_ping.cmd" || ( echo A1111 no responde. Usa opcion 4 y vuelve. & goto MENU )
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0a1111_choose_model.ps1"
call "%~dp0run_live_prompt.cmd"
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
call "%~dp0run_live_v03.cmd" "%SCRIPT%"
goto MENU

:END
endlocal
