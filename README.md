# STUDIO_MVP (v0.3)

Pipeline determinista para generar videos verticales tipo reels/shorts a partir de un flujo LIVE reproducible, con conversión a `scenes_v03`, resincronización de `pack.json`, subtítulos, export pack y handoff final validados contractualmente.

## Estado operativo del baseline `b699c88`

### Referencias oficiales del freeze
- rama publicada: `main`
- `origin/main` alineado con el baseline actual
- baseline operativo/documental vigente: `b699c88`

### Validación real cerrada
- `run_validation_stack_v03.ps1` FULL: PASS
- `run_validation_stack_v03.ps1` FULL en Docker: PASS
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
- trazabilidad contractual de `visual_query`
- preservación contractual de:
  - `visual_kind`
  - `visual_source_kind`
  - `visual_capability`
- coherencia contractual entre:
  - provider/runtime
  - `manifest_v03.json`
  - `pack.json`
  - export pack
  - release/handoff final
- preservación upstream explícita de `visual_source_kind` en:
  - `tools/apply_scene_builder_v03.ps1`
  - `tools/repair_live_manifest_v03.ps1`
- preservación de autoridad visual legacy antes del mixed asset fallback en:
  - `studio/live_manifest_patch_v03.py`
  - `_build_from_legacy_scenes(...)`
- preservación de prefijo temporal explícito válido en escenas legacy:
  - `_build_from_legacy_scenes(...)`
  - `tools/repair_live_manifest_v03.ps1`
  - prioridad: pares `start_ms/end_ms` válidos del prefijo → `audio_duration_ms` → `explicit_duration_ms` → weighted fallback
  - reconstrucción restante desplazada desde el último `end_ms` explícito válido
- Docker mínimo reproducible para finalize/export/handoff validation
- compatibilidad PowerShell UTF-8 homogénea vía `tools/ps_utf8_compat_v03.ps1`
- `.gitignore` ignora `workspace/exports/` dentro del repo sin ocultar `workspace/` completo
- `requirements.txt` declara `huggingface_hub` para el provider moderno `hf_image`, con validación FULL PASS en Docker
- validación final de:
  - `video.mp4`
  - `video_music_auto.mp4`
  - `video_final.mp4`
  - `HANDOFF_READY.txt`
  - ZIP final + SHA256

## Línea reciente del baseline
- `5f76c18` → Docker/portabilidad Linux para finalize/export handoff validation
- `043f7f5` → aplicación mecánica restante del helper UTF-8 a scripts PowerShell
- `bea8dd8` → `.gitignore` ignora `workspace/exports/` dentro del repo
- `d1f1031` → freeze documental sincronizado al baseline `bea8dd8`
- `1a34b36` → preservación de autoridad visual legacy antes del mixed asset fallback
- `2b18896` → freeze documental del contrato tras el ajuste legacy
- `f67a07f` → README sincronizado al baseline `1a34b36`
- `f601a4e` → preservación de prefijo temporal explícito válido en escenas legacy
- `1048f9c` → contrato sincronizado tras el ajuste temporal conservador
- `14043a3` → README sincronizado al baseline `f601a4e`
- `537b46c` → repair alineado con autoridad temporal por prefijo válido
- `6001591` → freeze documental sincronizado tras la alineación temporal en repair
- `b699c88` → `requirements.txt` declara `huggingface_hub` para `HFImageProvider`

## Limpieza conservadora ya ejecutada
- `__pycache__` y compilados `.pyc/.pyo` removidos del repo
- runs negativos temporales removidos del workspace cuando correspondía
- `_tmp/` fuera del repo
- `workspace/exports/` fuera del ruido del repo por política explícita de ignore
- bundles, distribuciones thirdparty y artefactos útiles de referencia preservados

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
- arquitectura visual multi-provider sin romper baseline
- `.ps1` y `.py` del repo en UTF-8 sin BOM y LF

## Estado honesto
El MVP base no está roto. El baseline técnico y contractual actual está operativo, validado, reproducible y publicado en `main`. El frente abierto real ya no es hacer funcionar el baseline, sino conservar el freeze operativo/documental y endurecer solo bordes upstream concretos sin romper el contrato visual ya cerrado.

## Siguiente foco
1. conservar freeze documental/operativo del baseline `b699c88`
2. auditar dependencias modernas restantes del path de texto (`openai`, `anthropic`) sin reabrir el contrato visual/temporal
3. mantener guardas de duración dinámica y arquitectura multi-provider sin romper baseline