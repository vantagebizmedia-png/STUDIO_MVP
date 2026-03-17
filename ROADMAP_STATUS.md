# ROADMAP_STATUS

## Estado actual confirmado al 2026-03-17

### Baseline validado
- `run_validation_stack_v03.ps1` FULL: PASS
- `validate_live_suite_v03.ps1`: PASS
- `smoke_live_manifest_v03.ps1`: PASS
- `smoke_subtitles_live_v03.ps1`: PASS
- `smoke_live_video_case_v03.ps1`: PASS
- `smoke_live_mixed_visuals_v03.ps1`: PASS
- `smoke_live_intent_image_fallback_v03.ps1`: PASS
- `smoke_live_intent_video_fallback_v03.ps1`: PASS
- `negative_live_suite_v03.ps1`: PASS

### Capacidades ya cerradas
- LIVE reproducible y estable para validación
- `Scene Builder v03` genera `scenes_v03` y normaliza estructura
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
- suite negativa validando conflictos y fugas estructurales

### Cambio técnico más reciente ya integrado
- `apply_scene_builder_v03.ps1` ahora respeta autoridad temporal antes del fallback sintético
- orden de autoridad temporal vigente:
  1. timings explícitos de escena válidos
  2. `audio_clips` con timeline válido y consistente
  3. fallback sintético determinista como última opción

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
- `smoke_live_intent_image_fallback_v03.ps1`
- `smoke_live_intent_video_fallback_v03.ps1`
- `negative_live_suite_v03.ps1`
- `ensure_outputs_live_v03.ps1`
- `finalize_handoff_v03.ps1`
- `handoff_pack_v03.ps1`

---

## Problema principal actual

El problema principal ya no es que el pipeline base esté roto. El baseline está estable. El frente abierto real es endurecer la capa upstream que decide y resuelve visuales por escena, para mejorar correspondencia entre:

- guion / narrativa
- intención visual explícita
- tipo de asset finalmente resuelto
- proveedor visual utilizado

En otras palabras: el cuello de botella actual es de calidad semántica/visual y de endurecimiento arquitectónico, no de viabilidad del pipeline.

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

### Prioridad A — endurecimiento upstream de selección visual por escena
- auditar dónde se decide la query final por escena
- endurecer trazabilidad de decisión visual
- reducir dependencia en fallback no ideal
- mantener coherencia entre intención visual y asset efectivo

### Prioridad B — duración dinámica end-to-end
- auditar más rutas donde todavía pueda sobrevivir lógica heredada
- asegurar que `start_ms`, `end_ms`, `duration_ms` sean autoridad real de punta a punta
- preparar mejor soporte para videos de duración variable según contenido

### Prioridad C — arquitectura multi-provider
- mantener baseline desacoplado de un único proveedor
- permitir expansión futura hacia backends adicionales
- no romper determinismo ni contrato del manifest

### Prioridad D — calidad estética y narrativa
- relevancia visual por escena
- layout visual
- safe margins
- fit contain/crop más fino
- tamaño de texto automático
- mejor calidad del guion LIVE

### Prioridad E — limpieza controlada
- depurar backups y probes residuales
- conservar únicamente lo útil para baseline, auditoría o recuperación real
- evitar borrar artefactos activos de validación

---

## Qué no debe cambiar
- determinismo del sistema
- cambios solo por parche/versionado explícito
- inspección real antes de modificar bloques sensibles
- validación reproducible después de cambios importantes
- control manual del operador

---

## Siguiente paso recomendado inmediato
1. actualizar `docs\CONTRACT_manifest_v03.md` con autoridad temporal e intención visual
2. actualizar `NEXT_STEPS.md` para reflejar el roadmap real actual
3. actualizar `SCENE_BUILDER_DIAGNOSIS.md` para que no contradiga el nuevo comportamiento del builder
4. luego ejecutar limpieza controlada de backups/probes con criterio conservador
