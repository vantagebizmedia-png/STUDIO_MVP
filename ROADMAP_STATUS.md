# ROADMAP_STATUS

## Estado actual confirmado al 2026-03-19

### Referencias oficiales
- rama publicada: `main`
- referencia documental previa al cierre: `be2a2df`
- baseline técnico/contractual validado: `26fefcd`

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
- persistencia explícita del contrato cross-media en provider/runtime cerrada:
  - `runtime_video_request_resolved_to_image`
  - `runtime_image_request_resolved_to_video`
  - `video_request_resolved_to_image`
  - `image_request_resolved_to_video`
- consistencia contractual entre resolver, manifest patch, scene builder y provider smoke validada
- validación contractual de handoff final cerrada:
  - `video.mp4`
  - `video_music_auto.mp4`
  - `video_final.mp4`
  - `HANDOFF_READY.txt`
  - ZIP final + SHA256
- suite negativa validando conflictos, fugas estructurales y desalineaciones reales

### Limpieza conservadora ya ejecutada
- repo sin `__pycache__`
- repo sin compilados `.pyc/.pyo`
- runs negativos temporales removidos del workspace
- run legacy `20260308_232312` archivado en `archive\legacy_runs`
- bundles, thirdparty packs y documentos históricos preservados

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

## Fase actual del proyecto
El MVP base técnico está cerrado. El frente abierto real ya no es "hacer que funcione", sino completar el freeze operativo/documental y, después, seguir endureciendo la calidad upstream de selección visual sin romper el baseline ya validado.

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
- dejar explícita la diferencia entre HEAD documental (`be2a2df`) y baseline técnico validado (`26fefcd`)
- mantener README/roadmap/next steps/release docs sin contradicciones
- dejar constancia de la limpieza conservadora ya ejecutada

### Prioridad B - endurecimiento upstream de selección visual por escena
- auditar dónde nace la query final por escena
- endurecer trazabilidad de decisión visual
- reducir dependencia en fallback no ideal
- mantener coherencia entre intención visual y asset efectivo

### Prioridad C - duración dinámica end-to-end
- seguir auditando rutas heredadas donde todavía pueda sobrevivir lógica fija
- asegurar que `start_ms`, `end_ms`, `duration_ms` sean autoridad real de punta a punta
- preparar mejor soporte para videos de duración variable según contenido

### Prioridad D - arquitectura multi-provider
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
1. cerrar el ajuste documental final del freeze
2. verificar `git diff --check` y consistencia textual
3. cerrar commit documental único
4. pasar después a auditoría/endurecimiento upstream de selección visual por escena