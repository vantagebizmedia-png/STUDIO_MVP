# CONTRACT: manifest_v03 (STUDIO_MVP)

## Objetivo

Definir el contrato operativo rígido y determinista para `manifest_v03.json`, su relación con `pack.json` y la validación estructural de escenas LIVE dentro del baseline v0.3, incluyendo preservación contractual de intención, visual efectivo, capacidad visual y origen visual a través de runtime, export y handoff final.

---

## Principios del contrato

- el contrato debe ser determinista
- no depende de auto-mutaciones del sistema
- `manifest_v03.json` es la fuente estructural principal de escenas LIVE
- `pack.json` debe quedar resincronizado contra el estado efectivo del manifest
- los campos temporales y visuales deben ser coherentes entre manifest y pack
- export y handoff final no deben degradar ni perder campos contractuales relevantes

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
- `visual_capability` (string descriptivo de la capacidad efectiva cuando aplique)

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

## Contrato temporal global

A nivel global, el timeline efectivo debe ser coherente con el cierre del manifest:

- `last_end` debe coincidir con el final efectivo de la última escena válida
- la suma lógica de escenas no puede producir gaps o solapes inválidos fuera de los casos explícitamente permitidos
- si existe audio total, la relación con la duración efectiva debe permanecer dentro de tolerancias del smoke correspondiente

---

## Contrato de audio por escena

Cada escena válida en flujo LIVE v03 debe mantener audio utilizable y alineado:

- `assets.audio_clip` debe apuntar a un clip resoluble
- la escena no debe quedar sin audio efectivo salvo caso de prueba negativa explícita
- los smokes de duración/voice fallback son autoridad práctica sobre la tolerancia aceptable
- `duration_ms` debe derivarse de la pareja temporal `start_ms` / `end_ms`

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

## Contrato de trazabilidad visual

Cuando aplique, la escena debe preservar además:

- `visual_source_kind` como descripción del origen efectivo del visual resuelto
- `visual_capability` como descripción de la capacidad efectiva involucrada en la resolución
- coherencia entre intención visual, visual efectivo y trazabilidad del fallback

Esto aplica especialmente a rutas donde:

- una solicitud `image` termina resolviendo a `video`
- una solicitud `video` termina resolviendo a `image`
- provider/runtime reescriben la resolución efectiva
- export/handoff deben reflejar el mismo estado contractual efectivo

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
- `visual_capability` cuando aplique
- asset visual efectivo

El smoke debe fallar si manifest y pack divergen en campos contractuales relevantes.

---

## Contrato de preservación en export y handoff

Los artefactos finales derivados del pack no deben degradar el contrato visual ya endurecido.

Cuando aplique, deben preservarse de forma coherente:

- `visual_kind`
- `visual_source_kind`
- `visual_capability`

La validación final de handoff/export debe fallar si esos campos divergen entre manifest, pack y artefactos contractuales finales en rutas donde el baseline exige su conservación.

---

## Contrato de consistencia global

El LIVE válido debe cumplir simultáneamente:

- estructura temporal válida
- coherencia visual por escena
- coherencia entre intención y visual efectivo
- preservación de trazabilidad visual cuando aplique
- coherencia entre manifest y pack
- coherencia entre duración de escena y audio dentro de tolerancias del smoke cuando aplique
- coherencia de subtítulos respecto al timeline de escenas
- preservación contractual en export y handoff final

---

## Validaciones de referencia

Los siguientes scripts forman parte de la validación práctica de este contrato:

- `tools\smoke_manifest_contract_v03.ps1`
- `tools\smoke_live_manifest_v03.ps1`
- `tools\smoke_live_provider_contract_v03.ps1`
- `tools\smoke_subtitles_live_v03.ps1`
- `tools\smoke_live_video_case_v03.ps1`
- `tools\smoke_live_mixed_visuals_v03.ps1`
- `tools\smoke_live_intent_image_fallback_v03.ps1`
- `tools\smoke_live_intent_video_fallback_v03.ps1`
- `tools\smoke_export_pack_contract_v03.ps1`
- `tools\smoke_release_handoff_contract_v03.ps1`
- `tools\negative_live_suite_v03.ps1`
- `tools\run_validation_stack_v03.ps1`

La autoridad final del comportamiento válido es el baseline validado por estas pruebas, no definiciones teóricas que contradigan el comportamiento ya endurecido del sistema.

---

## Resumen contractual

Un `manifest_v03.json` válido en STUDIO_MVP v0.3 debe conservar un timeline coherente, intención visual no conflictiva, visual efectivo consistente, trazabilidad visual cuando aplique, audio por escena alineado y sincronización real con `pack.json`, preservando además `visual_kind`, `visual_source_kind` y `visual_capability` en las rutas donde el baseline exige su conservación, todo bajo reglas deterministas y auditables.
