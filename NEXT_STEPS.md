# NEXT_STEPS

## Siguiente movimiento recomendado

### Paso 1
Consolidar documentación y subir rama actual al remoto privado.

### Paso 2
Entrar a la prioridad A:
- revisar `apply_scene_builder_v03.ps1`
- revisar `enrich_scenes_queries_v03.ps1`
- identificar exactamente dónde se decide:
  - query final
  - candidate list
  - intento de descarga
  - fallback a `artifacts.image`

### Paso 3
Agregar trazabilidad mínima de decisión visual por escena:
- query usada
- provider intentado
- motivo del fallback
- hit/no-hit
- asset final elegido

### Paso 4
Volver a correr:
- smoke E2E
- smoke E2E con handoff

### Paso 5
Si queda estable:
- commit técnico
- push a rama
- luego evaluar merge o PR

---

## Resultado esperado del próximo ciclo

No buscamos “perfección visual” todavía.
Buscamos esto:

- mismo smoke limpio
- mismos outputs correctos
- menos fallback heredado
- más evidencia clara de por qué cada escena eligió su imagen