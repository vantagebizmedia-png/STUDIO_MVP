# STUDIO_MVP (v0.3)

Pipeline determinista para generar videos verticales tipo reels/shorts a partir de un flujo LIVE reproducible, con conversión a `scenes_v03`, resincronización de `pack.json`, subtítulos, export pack y handoff final validados contractualmente.

## Estado operativo al 2026-03-19

### Baseline publicado
- rama: `main`
- HEAD: `26fefcd`

### Validación real cerrada
- `run_validation_stack_v03.ps1` FULL: PASS
- `validate_live_suite_v03.ps1`: PASS
- `smoke_live_manifest_v03.ps1`: PASS
- `smoke_live_provider_contract_v03.ps1`: PASS
- `smoke_subtitles_live_v03.ps1`: PASS
- `smoke_pipeline_voice_fallback_duration_v03.ps1`: PASS
- `smoke_pipeline_single_scene_voice_fallback_duration_v03.ps1`: PASS
- `smoke_live_video_case_v03.ps1`: PASS
- `smoke_live_mixed_visuals_v03.ps1`: PASS
- `smoke_export_pack_contract_v03.ps1`: PASS
- `smoke_release_handoff_contract_v03.ps1`: PASS
- `smoke_live_intent_image_fallback_v03.ps1`: PASS
- `smoke_live_intent_video_fallback_v03.ps1`: PASS
- `negative_live_suite_v03.ps1`: PASS

## Capacidades ya cerradas
- `Scene Builder v03` genera y normaliza `scenes_v03`
- `pack.json` queda resincronizado contra `manifest_v03.json`
- subtítulos alineados con `start_ms`, `end_ms`, `duration_ms`
- contrato explícito de intención visual:
  - `requested_media_type`
  - `visual_request_kind`
- soporte real para escenas `image` y `video`
- exclusividad visual por escena
- mixed visuals validados en render real
- fallback simétrico validado:
  - intención `video` con resolución efectiva a `image`
  - intención `image` con resolución efectiva a `video`
- fallback determinista de audio/imagen en multi-scene y single-scene
- export pack contractual validado
- release/handoff contractual validado
- persistencia explícita del contrato cross-media en provider runtime:
  - `runtime_video_request_resolved_to_image`
  - `runtime_image_request_resolved_to_video`
  - `video_request_resolved_to_image`
  - `image_request_resolved_to_video`
- consistencia contractual de fallback entre:
  - `stock_resolver_v03.py`
  - `live_manifest_patch_v03.py`
  - `apply_scene_builder_v03.ps1`
  - `smoke_live_provider_contract_v03.ps1`
- validación final de:
  - `video.mp4`
  - `video_music_auto.mp4`
  - `video_final.mp4`
  - `HANDOFF_READY.txt`
  - ZIP final + SHA256

## Outputs asegurados en el baseline
- `manifest_v03.json`
- `pack.json`
- `captions_v03.srt`
- `subtitles.srt`
- `video.mp4`
- `video_music_auto.mp4`
- `video_final.mp4`
- `HANDOFF_READY.txt`
- `<pack>.final_delivery.zip`
- `<pack>.final_delivery.zip.sha256.txt`

## Principios fuertes
1. El sistema debe ser 100% determinista.
2. No hay autoaprendizaje ni mutaciones automáticas.
3. Los cambios solo ocurren mediante parches/versionado explícito.
4. El operador conserva el control del sistema.
5. La validación principal se hace con smoke tests reproducibles.
6. Antes de parchear bloques sensibles, se inspecciona primero el archivo real.

## Reglas operativas
- PowerShell como vía principal
- cambios por bloques completos
- no parchear a ciegas
- inspección real antes de modificar
- smoke/stack después de tocar bloques sensibles
- `image` y `video` como ciudadanos de primera clase
- duración dependiente del contenido real
- arquitectura visual lista para línea multi-provider sin romper baseline
- `.ps1` y `.py` del repo en UTF-8 sin BOM y LF

## Estado honesto
El proyecto no está roto. El baseline técnico y contractual está operativo, validado, reproducible y publicado en `main`. El frente abierto real ya no es hacer que funcione el MVP base, sino cerrar bien la fase documental/operativa, ejecutar limpieza conservadora y luego endurecer el flujo upstream real de selección visual por escena sin romper el baseline determinista.

## Siguiente foco
1. cerrar sincronización documental mínima del baseline `26fefcd`
2. ejecutar limpieza segura fase 1
3. revisar limpieza conservadora fase 2 sobre `.bak*` y runs antiguos
4. preparar freeze operativo/documental del MVP
5. luego auditar y endurecer flujo upstream real de selección visual por escena