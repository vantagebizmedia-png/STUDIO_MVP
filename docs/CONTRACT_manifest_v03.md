# CONTRACT: manifest_v03 (STUDIO_MVP)

## Objetivo

Definir el contrato operativo rígido y determinista para `manifest_v03.json`, su relación con `pack.json` y la validación estructural de escenas LIVE dentro del baseline v0.3.

---

## Principios del contrato

- el contrato debe ser determinista
- no depende de auto-mutaciones del sistema
- `manifest_v03.json` es la fuente estructural principal de escenas LIVE
- `pack.json` debe quedar resincronizado contra el estado efectivo del manifest
- los campos temporales y visuales deben ser coherentes entre manifest y pack

---

## Root obligatorio

El LIVE válido debe contener:

- `manifest_v03.json`
- `scenes_v03[]` no vacío
- `pack.json` sincronizado

Además, a nivel root, deben mantenerse coherentes cuando existan:

- `audio_duration_ms`
- `audio_clips[]`
- `script` o equivalente textual usado por el pipeline

---

## Contrato de `scenes_v03[]`

Cada escena `scenes_v03[i]` debe incluir o resolver correctamente:

- `id` (string)
- `index` (int, recomendado 0..N-1)
- `start_ms` (int >= 0)
- `end_ms` (int > start_ms)
- `duration_ms` (int == end_ms - start_ms)
- `assets` (object)

Campos visuales esperados en baseline actual:

- `requested_media_type` (string, puede ser vacío solo en casos legacy controlados)
- `visual_request_kind` (string, puede ser vacío solo en casos legacy controlados)
- `visual_kind` (string efectivo: `image` o `video`)
- `visual_source_kind` (string descriptivo del origen efectivo cuando aplique)
- `visual_capability` (string descriptivo cuando aplique)

Campo de audio esperado por escena:

- `assets.audio_clip` (string no vacío, ruta relativa válida esperada en flujo v03)

Campos visuales de assets:

- `assets.image`
- `assets.video`

---

## Invariantes temporales por escena

Para cada escena válida:

- `start_ms >= 0`
- `end_ms > start_ms`
- `duration_ms = end_ms - start_ms`
- el timeline debe ser monótono
- la escena siguiente no puede empezar antes del `end_ms` previo

En forma práctica:

- escena 0 comienza en `start_ms >= 0`
- para toda escena `i > 0`, `start_ms(i) >= end_ms(i-1)`
- el `last_end` final representa el final efectivo del timeline

---

## Autoridad temporal vigente del Scene Builder

El orden de autoridad temporal válido al 2026-03-17 es:

1. timings explícitos de escena ya válidos en `scenes_v03`
2. `audio_clips[]` con timeline válido y consistente
3. fallback sintético determinista como última opción

Esto implica que `apply_scene_builder_v03.ps1` no debe sobrescribir un timeline explícito válido solo por recalcular uno sintético.

---

## Contrato de `audio_clips[]`

Si `audio_clips[]` existe en root:

- debe poder normalizarse como arreglo
- idealmente su count debe corresponder al número de escenas cuando se use como autoridad temporal
- cada clip útil para timeline debe traer:
  - `start_ms`
  - `end_ms`
- su timeline debe ser válido, creciente y consistente

Cuando `audio_clips[]` sea la autoridad temporal efectiva:

- `scenes_v03[i].start_ms` debe alinearse con el clip correspondiente
- `scenes_v03[i].end_ms` debe alinearse con el clip correspondiente
- `duration_ms` debe derivarse de esa pareja temporal

---

## Contrato de intención visual

La intención visual explícita se expresa mediante:

- `requested_media_type`
- `visual_request_kind`

Reglas:

- si ambos existen y no están vacíos, no deben entrar en conflicto
- el smoke debe fallar si `requested_media_type` y `visual_request_kind` se contradicen
- la intención puede preservarse aunque el asset efectivo resuelto cambie por fallback controlado

Ejemplos válidos:

- intención `video` con `visual_kind=image` si hubo fallback efectivo controlado
- intención `image` con `visual_kind=video` si hubo fallback efectivo controlado

Ejemplo inválido:

- `requested_media_type=video` y `visual_request_kind=image` simultáneamente para la misma escena

---

## Contrato de visual efectivo

`visual_kind` define el asset visual efectivo de la escena y debe ser coherente con `assets`.

### Caso `visual_kind=image`

- `assets.image` debe existir y ser no vacío
- `assets.video` debe ser vacío, nulo o ausente de forma compatible

### Caso `visual_kind=video`

- `assets.video` debe existir y ser no vacío
- `assets.image` debe ser vacío, nulo o ausente de forma compatible

El smoke debe fallar si hay fuga de asset no permitido para el `visual_kind` efectivo.

---

## Contrato de sincronización con `pack.json`

`pack.json` debe reflejar el estado efectivo de `manifest_v03.json` en los campos operativos relevantes.

Por escena, pack debe mantenerse alineado al menos en:

- audio
- `start_ms`
- `end_ms`
- `duration_ms`
- `requested_media_type` cuando aplique
- `visual_request_kind` cuando aplique
- `visual_kind`
- `visual_source_kind` cuando aplique
- asset visual efectivo

El smoke debe fallar si manifest y pack divergen en campos contractuales relevantes.

---

## Contrato de consistencia global

El LIVE válido debe cumplir simultáneamente:

- estructura temporal válida
- coherencia visual por escena
- coherencia entre manifest y pack
- coherencia entre duración de escena y audio dentro de tolerancias del smoke cuando aplique
- coherencia de subtítulos respecto al timeline de escenas

---

## Validaciones de referencia

Los siguientes scripts forman parte de la validación práctica de este contrato:

- `tools\smoke_manifest_contract_v03.ps1`
- `tools\smoke_live_manifest_v03.ps1`
- `tools\smoke_subtitles_live_v03.ps1`
- `tools\smoke_live_video_case_v03.ps1`
- `tools\smoke_live_mixed_visuals_v03.ps1`
- `tools\smoke_live_intent_image_fallback_v03.ps1`
- `tools\smoke_live_intent_video_fallback_v03.ps1`
- `tools\negative_live_suite_v03.ps1`

La autoridad final del comportamiento válido es el baseline validado por estas pruebas, no definiciones teóricas que contradigan el comportamiento ya endurecido del sistema.

---

## Resumen contractual

Un `manifest_v03.json` válido en STUDIO_MVP v0.3 debe conservar un timeline coherente, intención visual no conflictiva, visual efectivo consistente, audio por escena alineado y sincronización real con `pack.json`, todo bajo reglas deterministas y auditables.
