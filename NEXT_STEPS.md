# NEXT_STEPS

## Estado de referencia al 2026-03-18

Contexto operativo ya validado y publicado:

- HEAD publicado en `main`: `c8b2648`
- `run_validation_stack_v03.ps1` FULL: PASS
- `smoke_export_pack_contract_v03.ps1`: PASS
- `smoke_release_handoff_contract_v03.ps1`: PASS
- `smoke_live_intent_image_fallback_v03.ps1`: PASS
- `smoke_live_intent_video_fallback_v03.ps1`: PASS
- `negative_live_suite_v03.ps1`: PASS

### Contratos ya cerrados
- contract de manifest/pack compat
- autoridad temporal de subtítulos
- mixed visuals
- provider contract upstream
- fallback de audio/imagen en pipeline
- export-pack contract
- release/handoff contract end-to-end

---

## Objetivo inmediato

Cerrar la fase documental y de limpieza conservadora del MVP, sin tocar bloques sensibles del pipeline que ya están validados.

---

## Paso 1 - commit documental agrupado

Ahora que `SCENE_BUILDER_DIAGNOSIS.md` ya quedó alineado, cerrar un commit documental agrupado con:

- `ROADMAP_STATUS.md`
- `NEXT_STEPS.md`
- `README.md`
- `README_RELEASE.md`
- `SCENE_BUILDER_DIAGNOSIS.md`

Resultado esperado:

- bloque documental consistente
- baseline documental alineado con `c8b2648`
- base limpia para pasar a la fase de limpieza conservadora

---

## Paso 2 - limpieza controlada del repo

Después del ajuste documental, revisar y depurar con criterio conservador:

- backups `.bak*` de parches ya integrados
- backups específicos creados en este cierre
- `__pycache__` residuales
- logs puntuales no necesarios para baseline
- probes transitorios ya superados

No tocar todavía sin revisión explícita:

- bundles o zips que sirvan como referencia
- distribuciones thirdparty
- fixtures útiles
- documentación viva
- scripts activos del baseline

Resultado esperado:

- árbol más limpio
- menos ruido para auditoría y freeze

---

## Paso 3 - limpieza controlada del workspace

Revisar y depurar con criterio conservador:

- runs de prueba temporales ya cerrados
- `_tmp_render` residuales
- salidas intermedias redundantes
- clones negativos o de smoke que no sea necesario conservar

No borrar sin revisar:

- `smoke_live_latest`
- runs que sigan actuando como referencia viva
- artefactos necesarios para comparar regresiones

---

## Paso 4 - checklist de freeze final del MVP

Preparar un cierre operativo claro con:

- baseline publicado
- FULL PASS real
- documentación alineada
- árbol razonablemente limpio
- lista explícita de contratos cerrados
- lista explícita de frentes aún abiertos pero no bloqueantes

---

## Paso 5 - siguiente foco técnico real después del freeze

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

## Regla operativa vigente

Seguir trabajando con la metodología actual:

- PowerShell como vía principal
- reemplazos por bloques completos
- inspección real antes de modificar
- smoke/validación después de tocar contratos o bloques sensibles

---

## Siguiente acción recomendada

Cerrar ahora el commit documental agrupado y, a continuación, ejecutar una limpieza segura fase 1 sobre `__pycache__`, `.pyc`, `.log` residuales y `_tmp_render`, sin tocar todavía `.bak*`, bundles, fixtures ni runs de referencia.
