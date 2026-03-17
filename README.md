# STUDIO_MVP (v0.3)

Pipeline determinista para generar videos verticales tipo reels/shorts a partir de un flujo LIVE reproducible, con conversión a `scenes_v03`, resincronización de `pack.json`, subtítulos y render final, sin auto-mutaciones del sistema.

---

## Objetivo

Convertir un guion o idea en un pack final listo para publicación, manteniendo:

- determinismo
- reproducibilidad
- control manual del operador
- cero auto-learning
- cambios solo por parches/versionado explícito

---

## Estado operativo al 2026-03-17

### Validación real cerrada

- `run_validation_stack_v03.ps1` en modo FULL: PASS
- `validate_live_suite_v03.ps1`: PASS
- `smoke_live_manifest_v03.ps1`: PASS
- `smoke_subtitles_live_v03.ps1`: PASS
- `smoke_live_video_case_v03.ps1`: PASS
- `smoke_live_mixed_visuals_v03.ps1`: PASS
- `smoke_live_intent_image_fallback_v03.ps1`: PASS
- `smoke_live_intent_video_fallback_v03.ps1`: PASS
- `negative_live_suite_v03.ps1`: PASS

### Bloques técnicos ya cerrados

- `Scene Builder v03` genera y normaliza `scenes_v03`
- `pack.json` queda resincronizado contra `manifest_v03.json`
- contrato explícito de intención visual:
  - `requested_media_type`
  - `visual_request_kind`
- soporte real para `image` y `video`
- visuales mixtos por escena validados
- fallback simétrico validado:
  - intención `video` con resolución efectiva a `image`
  - intención `image` con resolución efectiva a `video`
- subtítulos con autoridad temporal desde `start_ms`, `end_ms`, `duration_ms`
- autoridad temporal del Scene Builder:
  1. timings explícitos de escena válidos
  2. `audio_clips` con timeline válido
  3. fallback sintético determinista como última opción

### Outputs asegurados en el baseline validado

- `manifest_v03.json`
- `pack.json`
- `captions_v03.srt`
- `subtitles.srt`
- `video.mp4`
- `video_music_auto.mp4`
- `video_final.mp4`
- `handoff_v03`
- `HASHES_SHA256.txt`
- `HANDOFF_READY.txt`
- `handoff_v03.zip`

---

## Qué sí está resuelto hoy

- LIVE estable para pruebas reproducibles
- segmentación temporal consistente por escena
- validación de coherencia entre manifest y pack
- exclusividad visual image/video por escena
- render real sobre casos con imágenes, videos y mezcla de ambos
- smoke negativo para detectar fugas, conflictos y desalineaciones

## Qué todavía sigue abierto

### 1. Calidad semántica/visual por escena

La arquitectura ya soporta selección visual por escena, pero todavía falta seguir endureciendo la relevancia real de la selección upstream para reducir dependencias en fallback y mejorar correspondencia entre guion, intención visual y asset resuelto.

### 2. Duración dinámica end-to-end

La regla del proyecto ya es correcta: la duración del video debe depender del contenido real y no de una plantilla fija. Aunque el baseline de validación está estable, todavía conviene seguir auditando y endureciendo el flujo completo para videos de duraciones variables más amplias.

### 3. Arquitectura multi-provider

El baseline ya no debe quedar atado mentalmente a Pixabay como único proveedor visual. La línea futura sigue siendo multi-provider, contemplando especialmente backends adicionales como ComfyUI y opciones candidatas equivalentes, sin romper determinismo.

### 4. Calidad estética final

Siguen como frente abierto:

- relevancia visual por escena
- layout visual
- safe margins
- fit contain/crop más fino
- tamaño de texto automático
- mejor calidad narrativa del guion LIVE

---

## Principios fuertes del sistema

1. El sistema debe ser 100% determinista.
2. No hay autoaprendizaje ni mutaciones automáticas.
3. Los cambios solo ocurren mediante parches/versionado explícito.
4. El operador conserva el control del sistema.
5. La validación principal se hace con smoke tests reproducibles.
6. Antes de parchear bloques sensibles, se inspecciona primero el archivo real.

---

## Reglas operativas de trabajo

- cambios por PowerShell
- evitar parches a ciegas
- inspección real antes de modificar
- preferencia por reemplazos de bloques enteros
- validación smoke/stack después de tocar bloques sensibles
- arquitectura compatible con `image` y `video`
- duración dependiente del contenido real
- línea futura multi-provider sin romper baseline

---

## Contrato operativo resumido

### Root

- `manifest_v03.json` debe existir
- `scenes_v03[]` debe existir y no estar vacío
- `pack.json` debe quedar sincronizado
- `total_audio_ms` / `audio_duration_ms` deben ser coherentes con el timeline efectivo

### Por escena

Cada escena operativa debe conservar o resolver correctamente:

- `id`
- `index`
- `start_ms`
- `end_ms`
- `duration_ms`
- `requested_media_type`
- `visual_request_kind`
- `visual_kind`
- `visual_source_kind`
- `visual_capability`
- `assets.audio_clip`

### Exclusividad visual

- si `visual_kind=image`, `assets.image` debe existir y `assets.video` debe estar vacío
- si `visual_kind=video`, `assets.video` debe existir y `assets.image` debe estar vacío

---

## Flujo operativo recomendado

### Validación rápida

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\run_validation_stack_v03.ps1 `
  -WorkspaceRoot C:\Users\vanta\Documents\STUDIO_WORKSPACE `
  -Quick
```

### Validación completa

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\run_validation_stack_v03.ps1 `
  -WorkspaceRoot C:\Users\vanta\Documents\STUDIO_WORKSPACE
```

### Smoke E2E

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\smoke_e2e_v03.ps1 `
  -WorkspaceRoot C:\Users\vanta\Documents\STUDIO_WORKSPACE `
  -MaxScenes 6 `
  -Seed 123
```

---

## Siguiente foco recomendado

1. actualizar documentación técnica y roadmap para reflejar autoridad temporal, fallback simétrico y mixed visuals
2. limpiar backups/probes residuales sin tocar artefactos útiles del baseline
3. auditar flujo upstream real de selección visual por escena
4. endurecer duración dinámica end-to-end
5. seguir abriendo la arquitectura multi-provider sin romper determinismo

---

## Estado honesto resumido

Hoy el proyecto no está roto. El baseline técnico está operativo, validado y reproducible. Lo que falta no es rehacer el sistema, sino seguir endureciendo la capa visual/semántica, la duración dinámica completa y la estrategia multi-provider manteniendo el comportamiento determinista.
