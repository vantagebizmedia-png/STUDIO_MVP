# STUDIO_MVP

Pipeline determinista para generar videos verticales (9:16) tipo reels/shorts a partir de un guion, con escenas, audio, subtítulos y empaquetado final reproducible.

---

## Objetivo

Convertir un guion en un paquete final listo para publicación, manteniendo:

- determinismo
- reproducibilidad
- control manual del operador
- zero auto-learning
- cambios solo por parches/versionado explícito

---

## Estado actual del proyecto

### Ya funciona de forma estable en smoke E2E v0.3

- generación de workspace LIVE estable
- Scene Builder v03
- `manifest_v03.json` con `scenes_v03`
- sincronización de `pack.json`
- normalización de assets de escena
- render de `video.mp4`
- generación y resincronización de subtítulos (`captions_v03.srt`, `subtitles.srt`)
- burn-in de subtítulos a `video_subs.mp4`
- outputs asegurados:
  - `video.mp4`
  - `video_music_auto.mp4`
  - `video_final.mp4`
- handoff final:
  - `handoff_v03`
  - `HASHES_SHA256.txt`
  - `HANDOFF_READY.txt`
  - `handoff_v03.zip`

### Validado recientemente

Smoke E2E v0.3 limpio con:

- `video.mp4`
- `video_final.mp4`
- `captions_v03.srt`
- `handoff_v03.zip`

---

## Qué NO está completamente resuelto todavía

### 1. Selección visual real por escena
La estructura ya existe, pero en smoke todavía se observa fallback frecuente de imagen:

- `FALLBACK(artifacts.image)`

Eso significa que el pipeline corre bien, pero la capa de relevancia visual por escena todavía necesita mejora para poblar escenas con imágenes más correctas y menos heredadas.

### 2. Escenas guiadas por guion
La meta del proyecto sigue siendo:

- que las escenas las determine el guion
- que la duración por escena sea flexible
- que un video pueda durar desde 1 minuto hasta 5 minutos o más, según el guion

En el smoke actual se usan parámetros controlados para asegurar repetibilidad de prueba, no para fijar el comportamiento final del producto.

### 3. Calidad visual y estética
Pendiente de seguir puliendo:

- relevancia de imagen por escena
- layout visual
- márgenes seguros
- fit contain/crop más fino
- tamaño de texto automático
- mayor calidad narrativa del script LIVE

### 4. Música automática real
El sistema ya asegura outputs consistentes, pero cuando no hay música disponible:
- `video_music_auto.mp4`
- `video_final.mp4`

se generan a partir de la base subtitulada. Falta completar la integración final de música automática en el flujo deseado.

---

## Principios fuertes del sistema

1. El sistema debe ser 100% determinista.
2. No hay autoaprendizaje ni mutaciones automáticas.
3. Los cambios solo ocurren mediante parches/versionado explícito.
4. El operador controla el sistema manualmente.
5. La validación principal se hace con smoke tests reproducibles.

---

## Roadmap vigente

### Prioridad 1
Scene Builder entre LIVE y EXPORT para que LIVE produzca escenas reales en `manifest_v03.json`:

- `scenes_v03`
- assets por escena
- split de guion a N escenas
- segmentación de audio por escena
- una imagen por escena

### Prioridad 2
Subtítulos integrados:

- SRT
- burn-in
- sincronización limpia

### Prioridad 3
Mejorar calidad LIVE:

- guion más estructurado
- imágenes más relevantes
- texto que no se salga
- mejor lectura visual por escena

### Prioridad 4
Música automática y handoff final:

- `video.mp4` sin música
- `video_music_auto.mp4`
- `video_final.mp4`
- ZIP final
- hashes
- `HANDOFF_READY.txt`

### Prioridad 5
Mantener determinismo y evitar regresiones:

- smoke estándar estable
- replay estricto
- compatibilidad de handoff

---

## Estado honesto resumido

Hoy el proyecto ya no está “roto”.

Hoy el proyecto:

- sí genera video
- sí genera subtítulos
- sí empaqueta handoff
- sí pasa smoke E2E
- sí es utilizable como base técnica

Lo que falta no es rehacer el sistema, sino completar bien la capa visual/semántica y seguir refinando el comportamiento guiado por guion.

---

## Forma de trabajo

- sin edición manual directa
- cambios mediante PowerShell
- reemplazos por bloques enteros
- validación con smoke reproducible
- versionado explícito en Git

---

## Comandos de validación habituales

### Smoke E2E
`pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\smoke_e2e_v03.ps1 -WorkspaceRoot $env:STUDIO_WORKSPACE -MaxScenes 6 -Seed 123`

### Smoke E2E con handoff
`pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\smoke_e2e_v03.ps1 -WorkspaceRoot $env:STUDIO_WORKSPACE -MaxScenes 6 -Seed 123 -DoHandoff`

---

## Siguiente foco recomendado

1. dejar documentado el estado real
2. consolidar README
3. mejorar relevancia visual por escena sin romper smoke
4. revisar modo LIVE para que use mejor queries + fetch real de imágenes
5. luego preparar subida privada del repo
