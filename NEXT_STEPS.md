# NEXT_STEPS

## Estado de referencia al 2026-03-17

Contexto operativo ya validado:

- `apply_scene_builder_v03.ps1` ya respeta autoridad temporal previa al fallback sintético
- `README.md` ya fue actualizado con el estado real del baseline
- `ROADMAP_STATUS.md` ya fue actualizado con prioridades vigentes
- `docs\CONTRACT_manifest_v03.md` ya fue actualizado con contrato temporal y visual real
- baseline FULL validado:
  - `run_validation_stack_v03.ps1`: PASS
  - mixed visuals: PASS
  - fallbacks simétricos: PASS
  - negative suite: PASS

---

## Objetivo inmediato

Cerrar la actualización documental restante y luego pasar a una limpieza controlada, sin tocar artefactos útiles del baseline ni abrir regresiones.

---

## Paso 1 - actualizar `SCENE_BUILDER_DIAGNOSIS.md`

Ese documento ya no debe describir al builder como si siempre impusiera timings sintéticos por encima del estado existente.

Debe reflejar explícitamente:

- que el builder conserva timings explícitos válidos cuando ya existen
- que `audio_clips[]` puede actuar como autoridad temporal
- que el fallback sintético sigue existiendo, pero solo como última opción
- que el comportamiento actual ya convive con `requested_media_type`, `visual_request_kind`, `visual_kind` y escenas mixed visuals

Resultado esperado del paso:

- documento alineado con el comportamiento real actual
- sin contradicciones con `README.md`, `ROADMAP_STATUS.md` y `docs\CONTRACT_manifest_v03.md`

---

## Paso 2 - commit documental agrupado

Cuando `SCENE_BUILDER_DIAGNOSIS.md` quede alineado, hacer un commit de documentación que agrupe:

- `ROADMAP_STATUS.md`
- `docs\CONTRACT_manifest_v03.md`
- `NEXT_STEPS.md`
- `SCENE_BUILDER_DIAGNOSIS.md`

Meta:

- dejar un bloque documental consistente y fácil de auditar

---

## Paso 3 - limpieza controlada del repo

Después del commit documental, hacer limpieza conservadora en el repo.

Eliminar primero candidatos claramente residuales:

- backups `.bak*` ya obsoletos de parches intermedios
- probes puntuales ya superados
- artefactos temporales que no formen parte del baseline ni del flujo activo

No tocar todavía sin revisión explícita:

- distribuciones thirdparty
- fixtures o bundles que puedan servir de referencia
- scripts activos
- documentación viva

Resultado esperado:

- árbol más limpio
- menos ruido para futuras auditorías

---

## Paso 4 - limpieza controlada del workspace

Revisar y depurar con criterio conservador:

- runs de probe temporales
- `_tmp_render` residuales
- `.bak` acumulados dentro de runs clonados
- salidas intermedias redundantes de casos smoke ya cerrados

No borrar sin revisar:

- `smoke_live_latest` operativo
- runs que todavía se estén usando como referencia viva
- artefactos necesarios para validar o comparar regresiones

---

## Paso 5 - siguiente foco técnico real

Una vez cerrada documentación + limpieza, el siguiente foco no es rehacer el pipeline, sino endurecer el flujo upstream de selección visual por escena.

Auditoría objetivo:

- dónde nace la query final por escena
- cómo se preserva la intención visual
- cómo se decide el provider real
- cómo se justifica el fallback cuando ocurre
- cómo reducir mismatch entre guion e imagen/video resuelto

---

## Riesgos a evitar

- tocar archivos sensibles sin inspección previa
- borrar evidencia útil de validaciones reales
- romper compatibilidad entre `manifest_v03.json` y `pack.json`
- reintroducir duraciones fijas por plantilla
- volver a una visión image-only del pipeline
- atar la arquitectura mentalmente a un único proveedor visual

---

## Regla operativa para el siguiente bloque

Seguir trabajando con la metodología actual:

- PowerShell como vía principal
- reemplazos por bloques completos
- inspección real antes de modificar
- smoke/validación después de tocar contratos o bloques sensibles

---

## Siguiente acción recomendada

Actualizar ahora `SCENE_BUILDER_DIAGNOSIS.md` y dejarlo alineado con la nueva autoridad temporal del builder.
