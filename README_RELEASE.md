# STUDIO_MVP - Release / Handoff v03

Documento de referencia del flujo vigente de release/handoff validado contractualmente en el baseline `c8b2648`.

## Estado actual
Al 2026-03-18, el flujo de release/handoff quedó validado de forma real con:

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
- `video.mp4`
- `video_music_auto.mp4`
- `video_final.mp4`
- `HANDOFF_READY.txt`

En el directorio padre del pack deben existir:
- `<pack>.final_delivery.zip`
- `<pack>.final_delivery.zip.sha256.txt`

Además:
- el SHA del sidecar debe coincidir con el ZIP real
- `HANDOFF_READY.txt` debe alinear con:
  - `PACK_ID`
  - `ZIP_FILE`
  - `ZIP_SHA256`
  - `VIDEO_BASE`
  - `VIDEO_MUSIC_AUTO`
  - `VIDEO_FINAL`
  - `AUTO_MUSIC_ENABLED`
  - `DETERMINISTIC`

## Nota operativa
El baseline actual es determinista y no debe mutarse automáticamente. Cualquier endurecimiento adicional del flujo release/handoff debe seguir la metodología vigente:
- inspección real
- reemplazos por bloques enteros
- validación reproducible después del cambio

## Próximo paso después de este bloque
1. cerrar commit documental de sincronización final
2. ejecutar limpieza segura del repo/workspace
3. preparar freeze operativo del MVP
4. luego pasar a auditoría upstream de selección visual por escena
