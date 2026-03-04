# STUDIO_MVP (v0.3) — Deterministic Video Pipeline (LIVE -> Scenes -> Subtitles -> HANDOFF)

Este repo contiene un pipeline determinista (replay/seed) para generar videos estilo short/reel a partir de un prompt.
El objetivo del MVP es mantener un baseline estable con smoke tests end-to-end.

## Estado actual (mar 2026)
- ✅ Smoke core v0.3 (tests + demos)
- ✅ Smoke E2E v0.3: LIVE -> workspace -> scenes_v03 -> subtitles (SRT + burn-in) -> handoff_v03 (ZIP + SHA256 + READY)

## Requisitos
- Windows + PowerShell 7 (`pwsh`)
- Python instalado (se usa el python en PATH)
- FFmpeg accesible en PATH (para render/subtítulos)

## Quickstart (Smoke)
Desde la raíz del repo:

### 1) Smoke Core
Ejecuta unit tests + demos:
- `tools/smoke_v03.ps1`

### 2) Smoke E2E (sin handoff)
Ejecuta LIVE -> workspace -> scenes -> subtítulos:
- `tools/smoke_e2e_v03.ps1 -WorkspaceRoot $env:STUDIO_WORKSPACE -MaxScenes 6`

### 3) Smoke E2E (con handoff)
Genera entrega final con hashes y marker de listo:
- `tools/smoke_e2e_v03.ps1 -WorkspaceRoot $env:STUDIO_WORKSPACE -MaxScenes 6 -DoHandoff`

Outputs esperados en:
`$env:STUDIO_WORKSPACE\runs\smoke_live_latest\handoff_v03\`
- `video.mp4` (sin música)
- `video_music_auto.mp4`
- `video_final.mp4`
- `handoff_v03.zip`
- `HASHES_SHA256.txt`
- `HANDOFF_READY.txt`

## Roadmap (STUDIO_MVP)
Prioridades (manteniendo baseline + smoke determinista):

1) Scene Builder (LIVE -> manifest_v03.json con scenes_v03 + assets por escena)
- Split guion -> N escenas
- Segmentación de audio por escena
- 1 imagen por escena vía Pixabay/stock_query

2) Subtítulos integrados
- Generación SRT + burn-in (safe margins / outline / tamaño controlado)

3) Calidad LIVE
- Guion más estructurado
- Imágenes más relevantes
- Evitar overflow de texto

4) Música automática (3 salidas)
- `video.mp4` (sin música)
- `video_music_auto.mp4`
- `video_final.mp4`

5) Finalize/Handoff
- ZIP final + hashes + `HANDOFF_READY.txt`
- Normalizar handoff para integraciones

## Notas de ingeniería
- Determinismo: el sistema debe ser reproducible (replay strict) y no auto-mutar.
- Cualquier cambio se valida con smoke tests para evitar regresiones.
- `.gitattributes` fuerza line endings consistentes (LF) en textos del repo.

## Licencia
Ver `LICENSE`.
