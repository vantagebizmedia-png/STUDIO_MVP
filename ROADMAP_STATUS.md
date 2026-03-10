# ROADMAP_STATUS

## Estado actual confirmado

### Base estable
- smoke E2E v0.3 limpio
- smoke E2E v0.3 con handoff limpio
- `video.mp4` generado correctamente
- `video_final.mp4` generado correctamente
- `captions_v03.srt` presente
- `handoff_v03.zip` presente
- `HASHES_SHA256.txt` presente
- `HANDOFF_READY.txt` presente

### Componentes ya operativos
- `smoke_live_to_workspace_v03.ps1`
- `apply_scene_builder_v03.ps1`
- `normalize_scene_assets_v03.ps1`
- `smoke_live_manifest_v03.ps1`
- `finalize_pack_v03.ps1`
- `apply_subtitles_live_v03.ps1`
- `smoke_subtitles_live_v03.ps1`
- `smoke_quality_live_v03.ps1`
- `ensure_outputs_live_v03.ps1`
- `finalize_handoff_v03.ps1`
- `handoff_pack_v03.ps1`

---

## Problema principal actual

La arquitectura ya funciona, pero la selección visual por escena todavía cae con frecuencia en:

- `FALLBACK(artifacts.image)`

Eso significa que el cuello de botella actual no es el pipeline base, sino la relevancia visual/fetch real de imágenes por escena.

---

## Decisión funcional vigente

La meta del sistema sigue siendo:

- que el guion defina las escenas
- que la duración de cada escena sea flexible
- que la duración total del video pueda variar según el guion
- que el smoke mantenga segmentación determinista controlada solo como prueba

---

## Prioridades reales ahora

### PRIORIDAD A — relevancia visual real por escena
Objetivo:
- mejorar queries por escena
- mejorar anchors semánticos
- reducir residuos narrativos en queries
- lograr menos fallback legacy
- acercar la imagen final a lo que pide el guion

### PRIORIDAD B — escenas guiadas mejor por guion
Objetivo:
- refinar split del guion en escenas
- desacoplar más la prueba smoke de la lógica final
- preparar evolución hacia escenas de duración más natural según contenido

### PRIORIDAD C — calidad visual/render
Objetivo:
- fit más fino
- safe margins
- tamaño de texto más robusto
- mejor consistencia estética de salida

### PRIORIDAD D — música automática real
Objetivo:
- dejar `video_music_auto.mp4` con música efectiva cuando exista input
- mantener fallback limpio cuando no exista
- no romper baseline

### PRIORIDAD E — publicación privada / orden del repo
Objetivo:
- documentación clara
- rama limpia
- commit entendible
- push privado / PR
- feedback externo

---

## Qué no hay que romper

- determinismo
- replay estricto
- smoke E2E limpio
- outputs estándar
- handoff final
- compatibilidad con `manifest_v03.json`
- compatibilidad con `pack.json`

---

## Criterio de avance

Solo se considera mejora válida si:
- no rompe smoke
- no rompe handoff
- no rompe subtítulos
- no rompe outputs finales
- mejora relevancia o claridad del sistema