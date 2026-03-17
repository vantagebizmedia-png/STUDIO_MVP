# SCENE_BUILDER_DIAGNOSIS

## Diagnóstico actualizado al 2026-03-17

Este documento resume el comportamiento real vigente de `apply_scene_builder_v03.ps1` después del endurecimiento reciente de autoridad temporal.

---

## Resumen ejecutivo

El problema actual del Scene Builder ya no es que fuerce siempre un timeline sintético por encima del estado previo. Esa descripción quedó desactualizada.

El comportamiento vigente es:

- el builder intenta conservar un timeline explícito de escenas cuando ya es válido
- si ese timeline no es válido, puede tomar `audio_clips[]` como autoridad temporal
- solo si ninguna de esas rutas sirve, genera un timeline sintético determinista
- después normaliza estructura de escena, assets y campos operativos para mantener compatibilidad con `manifest_v03.json` y `pack.json`

En consecuencia, el builder actual está más alineado con la regla del proyecto: respetar primero la autoridad temporal efectiva y usar el fallback sintético únicamente como última opción.

---

## Qué sí hace hoy el builder

Dentro del baseline validado, `apply_scene_builder_v03.ps1` ya participa correctamente en estas responsabilidades:

- asegurar `scenes_v03`
- normalizar estructura mínima por escena
- garantizar `start_ms`, `end_ms`, `duration_ms`
- asegurar `assets.audio_clip` por escena
- preservar compatibilidad con `pack.json` vía resincronización
- convivir con intención visual explícita y con escenas de tipo `image` o `video`
- operar dentro de una suite de validación que ya cubre mixed visuals, fallbacks simétricos y casos negativos

---

## Autoridad temporal vigente

El orden real de autoridad temporal al 2026-03-17 es:

1. timings explícitos válidos ya presentes en `scenes_v03`
2. `audio_clips[]` con timeline válido y consistente
3. fallback sintético determinista

Esto significa que el builder no debería recalcular tiempos sintéticos si ya existe un timeline correcto y usable.

---

## Flujo conceptual actual del builder

De forma resumida, el flujo vigente puede entenderse así:

1. leer manifest y estado LIVE
2. asegurar/normalizar `scenes_v03`
3. inspeccionar si las escenas ya traen timeline válido
4. si no, inspeccionar si `audio_clips[]` trae timeline válido
5. si tampoco sirve, construir timeline sintético determinista
6. aplicar el timeline resuelto a cada escena
7. asegurar campos visuales, assets y estructura mínima
8. dejar `manifest_v03.json` listo para resincronizar `pack.json`

La clave del cambio reciente está en el paso 3/4/5: ahora hay una resolución explícita de autoridad temporal antes de caer en reparto sintético.

---

## Qué parte del diagnóstico viejo quedó obsoleta

Quedó obsoleto afirmar que:

- el builder siempre impone duraciones sintéticas por diseño
- el timeline sintético domina incluso cuando ya existe timeline válido
- la lectura de audio solo sirve para calcular cantidad de escenas pero no para autoridad temporal

Eso ya no describe fielmente el comportamiento actual.

---

## Qué sigue siendo cierto

Aunque el builder mejoró, todavía siguen siendo válidas estas observaciones:

- el baseline prioriza estabilidad y determinismo
- la calidad semántica/visual por escena todavía necesita más endurecimiento upstream
- el split narrativo del guion todavía puede seguir mejorándose
- todavía conviene auditar rutas heredadas donde pueda sobrevivir lógica antigua

O sea: el problema ya no es “el builder pisa todo con timeline sintético”, sino que el sistema todavía necesita más calidad upstream en selección visual y más profundidad en duración dinámica end-to-end.

---

## Relación con intención visual

El builder actual ya convive con el contrato visual explícito y con el baseline mixto:

- `requested_media_type`
- `visual_request_kind`
- `visual_kind`
- `visual_source_kind`
- `visual_capability`

Esto es importante porque el diagnóstico del builder ya no puede analizar tiempos aislados del resto del contrato LIVE. Hoy el builder forma parte de un flujo donde también importa:

- coherencia entre intención y asset efectivo
- compatibilidad image/video por escena
- resincronización manifest/pack
- subtítulos alineados al timeline final

---

## Evidencia práctica del estado actual

El comportamiento actual no se toma como supuesto teórico, sino como parte de un baseline ya validado con:

- `run_validation_stack_v03.ps1` FULL
- `validate_live_suite_v03.ps1`
- `smoke_live_manifest_v03.ps1`
- `smoke_subtitles_live_v03.ps1`
- `smoke_live_video_case_v03.ps1`
- `smoke_live_mixed_visuals_v03.ps1`
- `smoke_live_intent_image_fallback_v03.ps1`
- `smoke_live_intent_video_fallback_v03.ps1`
- `negative_live_suite_v03.ps1`

Por eso este diagnóstico debe alinearse a ese estado real y no a una foto vieja del builder.

---

## Riesgos todavía abiertos

Los riesgos técnicos vigentes alrededor del builder son ahora estos:

- rutas heredadas que todavía puedan asumir duraciones fijas o defaults antiguos
- desalineación futura entre autoridad temporal real y documentación si se siguen haciendo cambios
- mejoras de relevancia visual que terminen rompiendo el baseline determinista
- introducir multi-provider sin preservar el contrato estructural actual

---

## Conclusión

Diagnóstico actualizado:

- el Scene Builder ya no debe entenderse como un módulo que simplemente reparte tiempos sintéticos y luego rellena escenas
- ahora debe entenderse como un resolvedor de timeline con prioridad por autoridad temporal explícita
- el fallback sintético sigue existiendo, pero ya no es la primera verdad del sistema
- el siguiente foco real no es rehacer este bloque, sino seguir endureciendo selección visual upstream, duración dinámica end-to-end y arquitectura multi-provider sin romper determinismo
