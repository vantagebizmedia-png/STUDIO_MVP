# STUDIO v0.3 — CORE STABLE (congelado)

Fecha: 2026-02-24

## Qué es “Core Stable”
El core estable es el conjunto mínimo y desacoplado que NO se toca al agregar providers o features.

Incluye:
- `studio/pipeline.py`
- `studio/core.py`
- `studio/config.py`
- `studio/exceptions.py`
- Interfaces en `studio/providers/*/base_*.py`
- Builders en `studio/builders.py`
- CLI v0.3 en `cli/main.py` (solo wiring; sin lógica del pipeline)

## Reglas (súper fuertes)
- `pipeline.py` NO imprime.
- `studio/` NO importa `cli/`.
- Providers se enchufan por interfaces; NO se modifica pipeline para agregar providers.
- Cualquier cambio al core requiere:
  1) parche explícito
  2) correr `tools\studio.ps1 -Mode smoke` y pasar

## Comandos oficiales
- Smoke total:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\studio.ps1 -Mode smoke`

- Demo core (sin API):
  - `powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\studio.ps1 -Mode demo -Script "hola"`

- Legacy demo (DRY seguro):
  - `powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\studio.ps1 -Mode legacy-demo -Script "hola"`

- Legacy con tu config real forzando DRY:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\studio.ps1 -Mode legacy -ForceMode DRY -Script "hola"`

## Nota
Todo lo que sea experimental va en `tools/_dev/` o fuera del árbol compilable.
## Provider Swapping (v0.3)
- Config JSON: `config\studio_v03.json`
- CLI:
  - `$env:STUDIO_ALLOW_LIVE="1"`
  - `python -m cli.main --v03-config .\config\studio_v03.json --script "hola"`
  - `Remove-Item Env:STUDIO_ALLOW_LIVE -ErrorAction SilentlyContinue`

Docs: `STUDIO_V03_PROVIDER_SWAPPING.md`
