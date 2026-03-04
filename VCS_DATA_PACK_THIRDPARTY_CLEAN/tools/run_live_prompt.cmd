@echo off
setlocal
set "STUDIO_ALLOW_LIVE=1"

set /p SCRIPT=Escribe el texto para --script (enter=hola live): 
if "%SCRIPT%"=="" set "SCRIPT=hola live"

python -m cli.main --v03-config .\config\studio_v03_live_a1111.json --script "%SCRIPT%"
endlocal
