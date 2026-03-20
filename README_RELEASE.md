# STUDIO_MVP - Release / Handoff v03

Documento de referencia del flujo vigente de release/handoff validado contractualmente en el baseline técnico `26fefcd` y resincronizado durante el cierre documental posterior a `be2a2df`.

## Estado actual
Al 2026-03-19, el flujo de release/handoff quedó validado de forma real con:

- `smoke_release_handoff_contract_v03.ps1`: PASS
- `validate_handoff.py`: PASS
- `run_validation_stack_v03.ps1` FULL: PASS

El baseline ya cubre:
- export pack real
- ZIP de release
- finalize handoff real
- validación contractual de artefactos finales
- negativo contractual del handoff

## Requisitos
- Python disponible en PATH
- dependencias del proyecto instaladas
- `ffmpeg` disponible en PATH
- workspace operativo del proyecto

Rutas típicas:
- repo: `C:\Users\vanta\Documents\STUDIO_MVP`
- workspace: `C:\Users\vanta\Documents\STUDIO_WORKSPACE`

## Flujo recomendado

### 1. Crear pack de release
Ejemplo:

`python .\tools\release_pack_v03.py --v03-config .\config\studio_v03_multiscene_text_smoke.json --script "mi guion o idea" --overwrite`

Salida esperada:
- `PACK_DIR: <ruta_del_pack>`
- ZIP inicial de release
- validación de pack OK

### 2. Finalizar handoff
`python .\tools\finalize_handoff_v03.py --pack-dir <PACK_DIR>`

Salida esperada dentro del pack:
- `video.mp4`
- `video_music_auto.mp4`
- `video_final.mp4`
- `HANDOFF_READY.txt`

Salida esperada en el parent del pack:
- `<pack>.final_delivery.zip`
- `<pack>.final_delivery.zip.sha256.txt`

### 3. Validar handoff
`python .\tools\validate_handoff.py --pack-dir <PACK_DIR>`

Resultado esperado:
- `RESULT: PASS`

## Smoke contractual recomendado
Para verificar el contrato end-to-end completo:

`powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\smoke_release_handoff_contract_v03.ps1 -RepoRoot C:\Users\vanta\Documents\STUDIO_MVP -WorkspaceRoot C:\Users\vanta\Documents\STUDIO_WORKSPACE`

Ese smoke ejecuta realmente:
1. `release_pack_v03.py`
2. `finalize_handoff_v03.py`
3. `validate_handoff.py`

Además verifica:
- artefactos obligatorios del handoff
- ZIP + SHA
- contenido mínimo dentro del ZIP final
- caso negativo contractual

## Contrato mínimo del handoff final

Dentro de `PACK_DIR` deben existir:
- `pack.json`
- `manifest_v03.json`
- `captions_v03.srt`
- `subtitles.srt`
- `video.mp4`
- `video_music_auto.mp4`
- `video_final.mp4`
- `HANDOFF_READY.txt`

En el parent del pack deben existir:
- `<pack>.final_delivery.zip`
- `<pack>.final_delivery.zip.sha256.txt`

## Nota operativa
La resincronización documental posterior al baseline `26fefcd` no cambia el contrato del handoff; solo deja explícita la referencia correcta entre baseline técnico validado y HEAD documental actual.