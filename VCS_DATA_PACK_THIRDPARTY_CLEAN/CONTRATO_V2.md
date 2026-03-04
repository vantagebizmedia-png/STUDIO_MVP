\# CONTRATO\_V2 — STUDIO\_MVP (Studio puro, multi-IA por capas)

Fecha: 2026-02-17



\## 0) Principios no negociables

1\) NO kernel / NO master / NO VCS.

2\) Cambios solo por reemplazo de archivo completo (sin parches frágiles).

3\) Determinismo práctico:

&nbsp;  - cache por pieza (guion, captions, hashtags, escenas, música, etc.)

&nbsp;  - parámetros fijos + seed cuando aplique

&nbsp;  - modo REPLAY = no llamar IA, reutilizar outputs guardados

4\) Plan maestro fijo:

&nbsp;  - manifest.json + story\_bible.json + storyboard.json + script\_by\_clips.json

&nbsp;  Son la fuente de verdad. Los renders derivan de esto.



\## 1) Flujo ideal (según sistema audiovisual)

Entrada mínima (idea/topics + pocas preferencias). El sistema:

\- toma decisiones creativas

\- genera TODO (guion, storyboard, prompts, metadata)

\- valida coherencia

\- permite regeneración selectiva (menú)

\- entrega 3 formatos finales



\## 2) Estructura de salida obligatoria (content\_pack)

content\_pack/

\- manifest.json (schema STUDIO\_PACK\_V2)

\- story\_bible.json

\- storyboard.json

\- script\_by\_clips.json

\- image\_prompts/scene\_XX.txt

\- music\_prompt.txt

\- captions.txt

\- hashtags.txt

\- description.txt



\### 2.1 Tres formatos finales obligatorios (además del pack)

\- final\_document.md  (documento completo listo para entregar)

\- production\_table.csv (tabla de producción por clip/escena)

\- prompts\_bundle/ (carpeta con prompts separados por modalidad)



\## 3) Validación cruzada mínima (antes de exportar)

Debe verificarse:

\- hook → develop → close presentes

\- cada escena tiene objetivo y texto en pantalla breve

\- safe area para subtítulos

\- coherencia de estilo (style\_id) a través de todas las escenas

\- constraints/presets se reflejan en story\_bible o prompts



\## 4) Menú 23 opciones (regeneración selectiva)

Regla: regenerar SOLO la parte elegida, mantener el resto intacto.

(En V2 se implementa el subconjunto “core” primero, y se ampliará sin romper numeración.)



1\. Regenerar idea/ángulo (topic\_summary)

2\. Regenerar story\_bible (reglas/tono)

3\. Regenerar guion completo (clips)

4\. Regenerar solo hook

5\. Regenerar solo cierre

6\. Regenerar storyboard (escenas y tipos visuales)

7\. Regenerar prompts de imagen (todas las escenas)

8\. Regenerar solo prompts de imagen de una escena (scene\_XX)

9\. Regenerar music\_prompt

10\. Regenerar captions

11\. Regenerar hashtags

12\. Regenerar description

13\. Generar 3 formatos finales (md/csv/prompts\_bundle)

14\. Exportar ZIP del pack

15\. Ver reporte/resumen

16\. Cambiar presets (estilo/emoción/cierre/subgénero) y re-hornear prompts

17\. Ajustar pacing (rápido/medio/lento) y recalcular duraciones

18\. Validar coherencia (run\_summary)

19\. “Freeze plan maestro” (marca en manifest como aprobado)

20\. REPLAY (no recalcular nada; solo re-exportar)

21\. Limpiar cache de una parte

22\. Limpiar cache total del run

23\. Todo OK → salida final lista



\## 5) Compatibilidad

\- V1 sigue funcionando.

\- V2 añade archivos sin romper los existentes.



