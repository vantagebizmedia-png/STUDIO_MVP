@echo off
setlocal
python -m pytest %*
set RC=%ERRORLEVEL%
if not "%RC%"=="0" (
  echo FAIL: pytest exit=%RC%
  exit /b %RC%
)
echo OK: pytest
endlocal
