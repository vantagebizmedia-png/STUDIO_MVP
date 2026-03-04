# CONTRACT: manifest_v03 (STUDIO_MVP)

## Objetivo
Definir un contrato rígido (determinista) para validar el pack LIVE/EXPORT.

## Root
- Debe existir `manifest_v03.json`
- Debe existir `scenes_v03[]` (lista no vacía)

## Scene (scenes_v03[i])
Cada escena debe incluir:
- `id` (string) recomendado formato `s01`, `s02`, ...
- `index` (int) 0..N-1
- `start_ms` (int) >= 0
- `end_ms` (int) > start_ms
- `duration_ms` (int) == end_ms - start_ms (recomendado)
- `assets` (object)

Campos recomendados:
- `script_text` (string) (puede estar vacío)
- `image_query` (string) (puede estar vacío)

## Assets
`assets` debe contener:
- `assets.image` (lista) (puede ser vacía)
- `assets.video` (lista) (puede ser vacía)

### Requisito visual (MVP v0.3+)
Por escena debe existir AL MENOS UNO de:
- `assets.image[0].path` existe en disco
- `assets.video[0].path` existe en disco

(Se acepta `image|video` porque HYBRID puede inyectar video stock y fallback local.)

## Determinismo
- HYBRID debe ser cache-first: si existe cache, no toca red.
- Si falla proveedor o red, debe haber fallback local para mantener smoke verde.
