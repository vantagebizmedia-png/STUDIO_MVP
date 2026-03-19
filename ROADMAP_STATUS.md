# ROADMAP_STATUS

## Estado actual confirmado al 2026-03-18

### Baseline publicado vigente
- `main` publicado en `origin/main`
- HEAD confirmado: `c8b2648`
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

### Capacidades ya cerradas
- LIVE reproducible y estable para validación
- `Scene Builder v03` genera y normaliza `scenes_v03`
- `pack.json` queda resincronizado contra `manifest_v03.json`
- autoridad temporal de subtítulos desde `start_ms`, `end_ms`, `duration_ms`
- contrato explícito de intención visual:
  - `requested_media_type`
  - `visual_request_kind`
- soporte real para escenas `image` y `video`
- exclusividad visual por escena validada
- mixed visuals validados en render real
- fallback simétrico validado:
  - intención `video` con resolución efectiva a `image`
  - intención `image` con resolución efectiva a `video`
- fallback determinista de audio/imagen en multi-scene y single-scene
- contract smoke de export pack cerrado
- contract smoke de release/handoff end-to-end cerrado
- validación contractual de handoff final cerrada:
  - `video.mp4`
  - `video_music_auto.mp4`
  - `video_final.mp4`
  - `HANDOFF_READY.txt`
  - ZIP final + SHA256
- `export_v03_pack.py` ya soporta ids legacy tipo `s01`, `s02`, etc. en la derivación de índice de escena
- suite negativa validando conflictos, fugas estructurales y desalineaciones reales

### Cambio técnico más reciente ya integrado
- nuevo `tools\validate_handoff.py`
- nuevo `tools\smoke_release_handoff_contract_v03.ps1`
- `validate_live_suite_v03.ps1` ya integra `RELEASE_HANDOFF_CONTRACT`
- `run_validation_stack_v03.ps1` ya resume `RELEASE_HANDOFF_CONTRACT=PASS`
- `export_v03_pack.py` endurecido para ids legacy de escenas en la ruta de release/export
- smokes de intent fallback ya son compatibles con runtimes PowerShell/.NET donde `Path.GetRelativePath()` no está disponible

---

## Componentes operativos del baseline
- `smoke_live_to_workspace_v03.ps1`
- `apply_scene_builder_v03.ps1`
- `normalize_scene_assets_v03.ps1`
- `write_pack_compat_v03.ps1`
- `smoke_live_manifest_v03.ps1`
- `finalize_pack_v03.ps1`
- `apply_subtitles_live_v03.ps1`
- `smoke_subtitles_live_v03.ps1`
- `smoke_live_video_case_v03.ps1`
- `smoke_live_mixed_visuals_v03.ps1`
- `smoke_export_pack_contract_v03.ps1`
- `validate_pack.py`
- `release_pack_v03.py`
- `finalize_handoff_v03.py`
- `validate_handoff.py`
- `smoke_release_handoff_contract_v03.ps1`
- `smoke_live_intent_image_fallback_v03.ps1`
- `smoke_live_intent_video_fallback_v03.ps1`
- `negative_live_suite_v03.ps1`
- `ensure_outputs_live_v03.ps1`
- `handoff_pack_v03.ps1`

---

## Lectura honesta del estado actual

El pipeline base y sus capas contractuales ya no están abiertas como problema principal.

A esta altura, el sistema ya tiene resueltos:

- baseline reproducible
- validación FULL estable
- export contractual
- release/handoff contractual
- fallbacks simétricos validados
- suite negativa útil

El frente abierto real ya no es "hacer que funcione", sino cerrar bien la fase de freeze del MVP y después seguir endureciendo la calidad upstream de selección visual.

---

## Decisión funcional vigente
La dirección correcta del sistema sigue siendo:

- que el contenido defina la duración
- que el guion influya realmente en las escenas
- que el pipeline soporte `image` y `video` como visuales de primera clase
- que el baseline no dependa mental ni técnicamente de un único proveedor visual
- que todo siga siendo determinista, controlable y auditable

---

## Prioridades vigentes

### Prioridad A - freeze documental y operativo
- resincronizar documentación viva con el estado real `c8b2648`
- dejar explícitos los contratos ya cerrados
- evitar que README/roadmap/next steps contradigan el baseline real

### Prioridad B - limpieza controlada
- depurar backups y probes residuales con criterio conservador
- no borrar fixtures, bundles o artefactos útiles de auditoría
- mantener el árbol legible para la fase final del MVP

### Prioridad C - endurecimiento upstream de selección visual por escena
- auditar dónde se decide la query final por escena
- endurecer trazabilidad de decisión visual
- reducir dependencia en fallback no ideal
- mantener coherencia entre intención visual y asset efectivo

### Prioridad D - duración dinámica end-to-end
- seguir auditando rutas heredadas donde todavía pueda sobrevivir lógica fija
- asegurar que `start_ms`, `end_ms`, `duration_ms` sean autoridad real de punta a punta
- preparar mejor soporte para videos de duración variable según contenido

### Prioridad E - arquitectura multi-provider
- mantener baseline desacoplado de un único proveedor
- permitir expansión futura hacia backends adicionales
- no romper determinismo ni contrato del manifest

---

## Qué no debe cambiar
- determinismo del sistema
- cambios solo por parche/versionado explícito
- inspección real antes de modificar bloques sensibles
- validación reproducible después de cambios importantes
- control manual del operador
- tratamiento de `image` y `video` como ciudadanos de primera clase

---

## Siguiente paso recomendado inmediato
1. cerrar commit documental agrupado
2. ejecutar limpieza segura fase 1 sobre residuos claramente descartables
3. luego revisar `.bak*`, runs viejos y probes con criterio conservador
4. preparar checklist de freeze final del MVP
