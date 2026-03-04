# STUDIO_MVP — Release (source clean)

Este repo está preparado para mantener el **código limpio** y enviar el **runtime** (runs/cache) fuera del repo.

## Requisitos
- Python instalado (usa el mismo que tú ya usas para correr STUDIO).
- Dependencias del proyecto instaladas (igual que en tu entorno actual).
- Si tu pipeline usa herramientas externas (ej. ffmpeg), deben estar disponibles en PATH.

## Variables de entorno

### STUDIO_WORKSPACE
Define dónde se guardan runs y cache.

PowerShell:

  $env:STUDIO_WORKSPACE = "$env:USERPROFILE\STUDIO_WORKSPACE"
  mkdir $env:STUDIO_WORKSPACE -Force | Out-Null

Si no defines STUDIO_WORKSPACE, STUDIO usa ./workspace (dentro del repo).

## Smoke test (1 comando)
Genera un video pequeño y valida que NO escribe runtime dentro del repo:

  powershell -ExecutionPolicy Bypass -File .\tools\smoke_end_to_end.ps1

Salida esperada:
- Video final en: %STUDIO_WORKSPACE%/runs/<run_id>/render/video_final.mp4
- workspace/runs y workspace/cache dentro del repo no cambian.

## Crear ZIP limpio (source clean)
Genera un ZIP sin .git/, workspace/, music/, _trash/, _vcs_extract/, outputs pesados, etc:

  python .\tools\make_release_zip.py

Archivo:
- .\releases\STUDIO_MVP_source_clean.zip

## Ejecutar
Ejemplo rápido:

  python run.py "tema del reel" --seed 123

Notas:
- El “producto estable” puede copiarse a .\output\video_final.mp4 según tu pipeline actual.

## Instalación reproducible (venv)
PowerShell:

  powershell -ExecutionPolicy Bypass -File .\tools\install_venv_and_smoke.ps1

Esto crea .\.venv, instala dependencias desde requirements.txt y corre el smoke test.
