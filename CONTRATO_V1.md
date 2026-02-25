\# CONTRATO\_V1 — STUDIO PACK V1 (Studio puro, sin VCS)



\## 0) Principio

\- Objetivo: Generar un \*\*content\_pack\*\* listo para producción (guion + clips + storyboard + prompts + metadata) desde 1 o varios nichos/ideas.

\- \*\*NO incluye\*\*: kernel VCS, hashchain, certificados, hashes, evidencia, ZIP reproducible.

\- \*\*SÍ incluye\*\*: estructura estable, coherencia narrativa, prompts listos para IA (imagen/música) y paquetes listos para publicar (captions/hashtags/description).



---



\## 1) Entrada (inputs)

El usuario provee:



\- `topics` (list\[str]): 1+ nichos/ideas (ej: `\["finanzas personales", "hábitos", "ansiedad"]`)

\- `target\_format` (str): `reel\_short` | `video\_long`

\- `language` (str): ej `es`

\- `style\_id` (str): ej `infografia`, `cartoon\_educativo`, `cinematic`, etc.

\- `voice\_pacing` (str): `rapido` | `medio` | `lento`

\- `audience\_level` (str): `principiante` | `intermedio` | `avanzado`

\- `constraints` (list\[str], opcional): límites (ej. “sin humor”, “sin jerga”, “sin marcas”)

\- `seed` (int, opcional): para consistencia de estructura del plan (no garantiza determinismo en IA)



---



\## 2) Reglas narrativas obligatorias

\- El sistema crea una \*\*Narrativa Unificada\*\* a partir de `topics`:

&nbsp; - define 1 \*\*tema troncal\*\*

&nbsp; - define 2–5 \*\*subtemas\*\* (si aplica)

\- La voz guía el ritmo:

&nbsp; - el guion se divide en \*\*clips\*\* (segmentos) con duración estimada

\- Las escenas NO son fijas:

&nbsp; - `scene\_count` se deriva de clips: \*\*1 escena por clip\*\* (por defecto)

\- Coherencia y continuidad:

&nbsp; - estilo consistente en todo el pack

&nbsp; - si hay personajes/elementos recurrentes, se mantienen consistentes

\- Estructura mínima:

&nbsp; - `hook` → `develop` (uno o más) → `close`



---



\## 3) Salida (output) — Carpeta `content\_pack/`

La ejecución siempre produce la carpeta:



`content\_pack/`



\### Archivos obligatorios

1\) `manifest.json`

2\) `story\_bible.json`

3\) `script\_by\_clips.json`

4\) `storyboard.json`

5\) `captions.txt`

6\) `hashtags.txt`

7\) `description.txt`

8\) `music\_prompt.txt`

9\) `image\_prompts/scene\_XX.txt` (uno por escena)



> Nota V1: \*\*no se generan imágenes reales\*\*. Solo prompts listos (para no depender de APIs y no gastar).



---



\## 4) Especificación de cada archivo



\### 4.1 `manifest.json`

Debe contener:

\- `schema`: `"STUDIO\_PACK\_V1"`

\- `created\_at\_utc`

\- `inputs`: los valores usados (topics, formato, idioma, estilo, seed, etc.)

\- `topic\_summary`:

&nbsp; - `core\_topic`

&nbsp; - `subtopics`

\- `counts`:

&nbsp; - `clips`

&nbsp; - `scenes`

&nbsp; - `image\_prompts`



\### 4.2 `story\_bible.json`

Debe contener:

\- `tone`: ej (educativo, inspirador, directo, emocional-controlado)

\- `core\_message`: 1 frase

\- `continuity\_rules`: lista corta (3–7 reglas)

\- `visual\_rules`:

&nbsp; - densidad de texto

&nbsp; - iconografía

&nbsp; - layout/jerarquía

&nbsp; - áreas seguras para subtítulos

\- `characters` (opcional):

&nbsp; - solo si el estilo requiere personajes recurrentes



\### 4.3 `script\_by\_clips.json`

Debe ser un array de clips. Cada clip contiene:

\- `clip\_id` (ej: `clip\_01`)

\- `purpose`: `hook` | `develop` | `proof` | `example` | `close` | etc.

\- `voiceover`: texto de voz

\- `estimated\_duration\_s`: estimación según `voice\_pacing`

\- `on\_screen\_text`: texto corto (si aplica)

\- `key\_points`: bullets (máx 3)



\### 4.4 `storyboard.json`

Debe ser un array de escenas. Cada escena contiene:

\- `scene\_id` (ej: `scene\_01`)

\- `from\_clip\_id`: clip asociado

\- `visual\_type`: `static\_image` | `motion\_ready`

\- `camera\_motion\_notes`: si `motion\_ready` (ej: “slow zoom”, “parallax”, “pan left”)

\- `composition\_notes`: layout, jerarquía, dónde va el texto

\- `asset\_notes`: iconos, gráficos, elementos sugeridos

\- `image\_prompt\_ref`: ruta a `image\_prompts/scene\_XX.txt`



\### 4.5 `image\_prompts/scene\_XX.txt`

Prompt por escena con:

\- estilo (`style\_id`)

\- tema/subtema del clip

\- texto en pantalla (si aplica)

\- consistencia (tipografía, iconos, paleta conceptual, etc.)

\- si es `motion\_ready`:

&nbsp; - capas sugeridas (background/mid/foreground)

&nbsp; - áreas seguras para subtítulos



\### 4.6 `captions.txt`

3–5 captions variantes (corto/medio/largo).



\### 4.7 `hashtags.txt`

Hashtags en una línea, 10–25 (mezcla general + nicho).



\### 4.8 `description.txt`

Descripción lista para publicar (1–2 párrafos), incluye CTA.



\### 4.9 `music\_prompt.txt`

Prompt para IA de música:

\- mood

\- bpm aproximado

\- instrumentos sugeridos

\- duración recomendada según formato

\- “no vocals” por defecto (si no se pide lo contrario)



---



\## 5) Criterios de éxito (funciona de verdad)

V1 es exitoso si:

\- siempre genera el pack completo con todos los archivos obligatorios

\- clips y escenas mantienen coherencia (hook→desarrollo→cierre)

\- prompts por escena están alineados con guion y ritmo de voz

\- la salida es utilizable sin reestructurar (solo producir assets con IAs luego)



---



\## 6) Regla operativa para no caer en caos

\- V1 es \*\*dry-run\*\*: sin APIs, sin gasto, sin dependencias externas.

\- Una sola pantalla (GUI) con botón “Generar pack”.

\- Cambios y mejoras en V2/V3, sin romper el contrato V1.



