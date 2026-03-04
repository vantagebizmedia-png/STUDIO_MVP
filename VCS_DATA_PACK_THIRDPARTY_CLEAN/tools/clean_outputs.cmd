@echo off
setlocal
echo == CLEAN OUTPUTS ==
echo Esto borra SOLO carpetas de output locales:
echo   _demo_out*
echo   _v03_*
echo   _v03_smoke_cfg
echo   _v03_legacy_run
echo   _v03_from_config
echo.
set /p OK=Confirmar (escribe YES para borrar): 
if /I not "%OK%"=="YES" (
  echo Cancelado.
  exit /b 0
)

for %%D in (_demo_out _demo_out_legacy _v03_smoke_cfg _v03_legacy_run _v03_from_config) do (
  if exist "%%D" (
    echo Deleting %%D ...
    rmdir /s /q "%%D"
  )
)

REM Borra cualquier _v03_* extra
for /d %%D in (_v03_*) do (
  if exist "%%D" (
    echo Deleting %%D ...
    rmdir /s /q "%%D"
  )
)

echo OK: outputs borrados.
endlocal
