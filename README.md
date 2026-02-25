# STUDIO_MVP  Render + Final + Release (determinista)

STUDIO_MVP es un MVP en Windows (PowerShell + Python + FFmpeg) para renderizar videos cortos desde un `content_pack`, y exportar un release listo para terceros.

## Requisitos
- Windows 10/11
- PowerShell 7 (pwsh)
- Python 3.10+ (recomendado 3.11)
- FFmpeg + ffprobe en PATH (`ffmpeg -version` debe funcionar)

## Estructura recomendada (simple y clara)
- STUDIO_MVP (este repo)
  - tools\
  - workspace\
    - output\
    - release\
  - models\
- STUDIO_WORKSPACE (workspace externo donde viven los runs)
  - runs\
    - <RUN_ID>\content_pack\

Nota: el `PackDir` siempre es la carpeta `...\runs\<RUN_ID>\content_pack`.

## Outputs importantes
Durante el flujo se generan archivos en:
- `workspace\output\`
  - `video_FINAL_CINE_MUSIC_DYNAMIC_<PRESET>.mp4`
  - `video_FINAL_CINE_MUSIC_DYNAMIC_<PRESET>_PRO.mp4`
  - `video_FINAL_CINE_MUSIC_DYNAMIC_<PRESET>_PRO_EDIT.mp4` (si activas Edit)
- Release final:
  - `workspace\release\STUDIO_RELEASE_<RUN>_<PRESET>_<TIMESTAMP>\`
  - ZIP equivalente en la misma carpeta
- Alias en el release:
  - `release\...\video\video_latest.mp4` (prioridad: PRO_EDIT > PRO > EDIT > no-FAST)

## Comando 1-click (recomendado)
Ejemplo (Preset B, CINE, música fixed, ducking dynamic, PostPro + Denoise + Edit final):

pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\final.ps1 `
  -PackDir "C:\RUTA\A\STUDIO_WORKSPACE\runs\<RUN_ID>\content_pack" `
  -MaxScenes 4 -Preset B `
  -Mode CINE -MusicMode fixed -DuckingMode dynamic `
  -PostPro -PostProDenoise `
  -Edit -EditTrimEndSec 0.15 -EditFadeOutSec 0.12 -EditGainDb 1.5

Esto produce como salida principal:
- `workspace\output\video_FINAL_CINE_MUSIC_DYNAMIC_B_PRO_EDIT.mp4` (si Edit está ON)

## Exportar release (carpeta + ZIP)
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\export_release.ps1 `
  -PackDir "C:\RUTA\A\STUDIO_WORKSPACE\runs\<RUN_ID>\content_pack" `
  -Preset B

El release incluye:
- CINE, PRO, PRO_EDIT (si existe), FAST y `video_latest.mp4` dentro de `release\...\video\`

## Denoise (audio)
- PostPro soporta:
  - `afftdn` (simple, rápido)
  - `arnndn` con modelo local (RNNoise)

Modelo RNNoise recomendado (bd.rnnn):
- `models\rnnoise\bd.rnnn`

## Principio clave (determinista)
- Se prioriza reproducibilidad: mismos inputs/config  mismo output (hasta donde FFmpeg/hardware lo permita).
- Los cambios se hacen por parches explícitos (sin auto-mutación del sistema).

## Workspace externo obligatorio

Este proyecto **NO** debe guardar runs/output/cache dentro del repo.
Debes usar un workspace externo vía `STUDIO_WORKSPACE`.

### Setup (Windows / PowerShell)

```powershell
$ws = "$env:USERPROFILE\Documents\STUDIO_WORKSPACE"
[Environment]::SetEnvironmentVariable("STUDIO_WORKSPACE", $ws, "User")
$env:STUDIO_WORKSPACE = $ws
```

### Uso (entrypoint único)

```powershell
.\studio.ps1 doctor
.\studio.ps1 new   -Prompt "disciplina diaria" -- --seed 123 --max_scenes 6 --fit crop --music
.\studio.ps1 final -RunId latest -Mode CINE -Preset B -MusicMode off
```

## Modos de ejecucion: SMOKE (offline) vs LIVE (A1111)

### SMOKE v0.3 (offline, determinista, no requiere A1111)
> Usalo para verificar que el repo esta VERDE y que el pipeline no se rompio.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\smoke_v03.ps1
```

### LIVE v0.3 (A1111 real por API, mejor calidad)
> Requiere Automatic1111 corriendo con --api y confirmacion de LIVE.

1) Arranca A1111 (en otra ventana):
- C:\stable-diffusion-webui\webui-user.bat --api

2) Verifica conexion y (opcional) selecciona modelo:
```powershell
.\tools\a1111_ping.ps1
.\tools\a1111_models.ps1
.\tools\a1111_set_model.ps1 -Checkpoint "NOMBRE_DEL_MODELO"
```

3) Ejecuta el pipeline LIVE:
```powershell
$env:STUDIO_ALLOW_LIVE = "1"
python -m cli.main --v03-config .\config\studio_v03_live_a1111.json --script "hola live"
```

Para volver a modo seguro:
```powershell
Remove-Item Env:STUDIO_ALLOW_LIVE -ErrorAction SilentlyContinue
```

