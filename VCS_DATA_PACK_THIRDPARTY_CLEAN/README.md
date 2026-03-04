# VCS_DATA_PACK_THIRDPARTY_CLEAN — STUDIO v0.3 (Clean Pack)

Este directorio es una distribución "clean" del pipeline v0.3 para terceros.
Incluye herramientas, configs y tests necesarios para validar el baseline determinista.

## Quickstart (Smoke)
Desde la raíz del repo (o dentro del pack, ajustando rutas):

### 1) Smoke Core
- `VCS_DATA_PACK_THIRDPARTY_CLEAN/tools/smoke_v03.ps1`

### 2) Smoke E2E (con handoff)
- `VCS_DATA_PACK_THIRDPARTY_CLEAN/tools/smoke_e2e_v03.ps1 -WorkspaceRoot $env:STUDIO_WORKSPACE -MaxScenes 6 -DoHandoff`

## Handoff (salida esperada)
En:
`$env:STUDIO_WORKSPACE\runs\smoke_live_latest\handoff_v03\`

Incluye:
- `video.mp4`
- `video_music_auto.mp4`
- `video_final.mp4`
- `handoff_v03.zip`
- `HASHES_SHA256.txt`
- `HANDOFF_READY.txt`

## Política de placeholders (pre-commit)
El pack incluye un guard para bloquear commits con placeholders comunes.
Ver:
- `VCS_DATA_PACK_THIRDPARTY_CLEAN/tools/guard_no_placeholders.ps1`

## Licencia
Ver `VCS_DATA_PACK_THIRDPARTY_CLEAN/LICENSE`.
