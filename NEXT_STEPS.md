# NEXT_STEPS

## Estado de referencia al 2026-03-19

Contexto operativo ya validado y publicado:

- referencia documental previa al cierre: `be2a2df`
- baseline técnico/contractual validado: `26fefcd`
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
- persistencia explícita de flags cross-media en runtime/asset meta
- fallback de audio/imagen en pipeline
- export-pack contract
- release/handoff contract end-to-end

### Limpieza ya ejecutada
- `__pycache__` removidos del repo
- compilados `.pyc/.pyo` removidos del repo
- runs negativos temporales removidos del workspace
- run legacy `20260308_232312` archivado en `archive\legacy_runs\20260308_232312`

---

## Objetivo inmediato

Cerrar el freeze documental/operativo del MVP sin tocar bloques sensibles del pipeline que ya están validados.

---

## Paso 1 - resincronización documental final
Dejar consistentes entre sí:

- `README.md`
- `ROADMAP_STATUS.md`
- `NEXT_STEPS.md`
- `README_RELEASE.md`

Resultado esperado:

- documentos vivos sin contradicciones
- diferencia explícita entre HEAD documental y baseline técnico
- limpieza conservadora ya reflejada en docs

---

## Paso 2 - checklist corto de freeze
El freeze documental/operativo debe dejar explícito:

- baseline técnico validado
- FULL PASS real
- contratos cerrados
- limpieza conservadora ya ejecutada
- frentes aún abiertos pero no bloqueantes

---

## Paso 3 - siguiente foco técnico real después del freeze
Una vez cerrado el freeze, el siguiente foco no es rehacer el pipeline, sino endurecer el flujo upstream de selección visual por escena.

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

## Acción recomendada ahora
Aplicar esta resincronización documental final, verificar diff limpio y cerrar un commit documental único de freeze.