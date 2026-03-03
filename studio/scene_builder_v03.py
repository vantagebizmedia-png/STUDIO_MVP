# studio/scene_builder_v03.py
# Scene Builder v03 (determinista): guion -> N escenas + image_query + timestamps

from __future__ import annotations

from typing import List, Dict, Any
import re
import math


def _norm_space(s: str) -> str:
    s = (s or "").strip()
    s = re.sub(r"\s+", " ", s)
    return s


def split_script_into_scenes(script_text: str, max_scenes: int) -> List[str]:
    """
    Split determinista (v03):
      1) Preferir párrafos/líneas (si existen).
      2) Si no alcanza, dividir por frases.
      3) Si aún no alcanza y el texto es suficientemente largo, forzar N escenas por chunking de palabras.
      4) Recortar a max_scenes (merge del resto en la última).
    """
    if max_scenes < 1:
        max_scenes = 1

    raw_text = (script_text or "").strip()
    text = _norm_space(raw_text)
    if not text:
        return [""]

    # 1) Párrafos: doble salto, o múltiples líneas
    paras = [p.strip() for p in re.split(r"\n{2,}", raw_text) if p.strip()]
    if len(paras) <= 1:
        # si venía con varias líneas simples, úsalas como base
        lines = [ln.strip() for ln in re.split(r"\r?\n", raw_text) if ln.strip()]
        if len(lines) > 1:
            paras = lines

    chunks = [_norm_space(p) for p in paras if _norm_space(p)]

    # 2) Frases por puntuación (si aún es 1 bloque)
    if len(chunks) <= 1:
        parts = re.split(r"(?<=[\.\!\?])\s+", text)
        chunks = [_norm_space(p) for p in parts if _norm_space(p)]

    # 3) Forzar N escenas por palabras si no hay separadores útiles
    #    (solo si el texto es lo bastante largo como para justificarlo)
    if len(chunks) < max_scenes:
        words = [w for w in re.split(r"\s+", text) if w]
        # umbral mínimo para evitar dividir textos cortos sin sentido
        if len(words) >= 30:
            # objetivo: hasta max_scenes, con grupos contiguos casi iguales
            n = min(max_scenes, max(1, int(math.ceil(len(words) / 18.0))))
            n = max(n, len(chunks))  # no reducir lo ya detectado
            if n > 1:
                base = len(words) // n
                rem = len(words) % n
                forced = []
                idx = 0
                for i in range(n):
                    take = base + (1 if i < rem else 0)
                    seg = " ".join(words[idx: idx + take]).strip()
                    if seg:
                        forced.append(seg)
                    idx += take
                if forced:
                    chunks = forced

    # Si aún quedó vacío (caso raro), fallback
    if not chunks:
        chunks = [text]

    # 4) Recorte/merge determinista a max_scenes
    if len(chunks) <= max_scenes:
        return chunks

    head = chunks[: max_scenes - 1]
    tail = " ".join(chunks[max_scenes - 1 :]).strip()
    return head + [tail]

def make_image_query(scene_text: str) -> str:
    """
    Query simple y determinista:
    - toma hasta 10 palabras “útiles”
    - limpia símbolos
    """
    t = _norm_space(scene_text).lower()
    t = re.sub(r"[^a-z0-9áéíóúüñ\s]", " ", t, flags=re.IGNORECASE)
    t = re.sub(r"\s+", " ", t).strip()

    words = [w for w in t.split(" ") if len(w) >= 3]
    if not words:
        return "concepto abstracto"

    core = words[:10]
    return " ".join(core)


def allocate_timestamps(total_ms: int, scene_texts: List[str]) -> List[Dict[str, int]]:
    """
    Distribución determinista por “peso” (longitud de texto).
    Garantiza:
      - suma = total_ms
      - intervals consecutivos
      - cada escena >= 300 ms si es posible
    """
    n = max(1, len(scene_texts))
    total_ms = max(0, int(total_ms))

    weights = [max(1, len(_norm_space(t))) for t in scene_texts]
    wsum = sum(weights)

    raw = [int(math.floor(total_ms * (w / wsum))) for w in weights]
    diff = total_ms - sum(raw)
    i = 0
    while diff > 0 and n > 0:
        raw[i % n] += 1
        diff -= 1
        i += 1

    MIN_MS = 300
    if total_ms >= n * MIN_MS:
        deficit = 0
        for i in range(n):
            if raw[i] < MIN_MS:
                deficit += (MIN_MS - raw[i])
                raw[i] = MIN_MS

        j = 0
        while deficit > 0:
            k = j % n
            if raw[k] > MIN_MS:
                raw[k] -= 1
                deficit -= 1
            j += 1

    out = []
    cur = 0
    for dur in raw:
        start = cur
        end = min(total_ms, cur + dur)
        out.append({"start_ms": start, "end_ms": end})
        cur = end

    if out:
        out[-1]["end_ms"] = total_ms

    return out


def build_scenes_v03(
    script_text: str,
    max_scenes: int,
    total_audio_ms: int,
) -> List[Dict[str, Any]]:
    scene_texts = split_script_into_scenes(script_text, max_scenes=max_scenes)
    ts = allocate_timestamps(total_audio_ms, scene_texts)

    scenes: List[Dict[str, Any]] = []
    for i, text in enumerate(scene_texts):
        start_ms = ts[i]["start_ms"]
        end_ms = ts[i]["end_ms"]
        scenes.append(
            {
                "id": f"s{i+1:02d}",
                "index": i,
                "start_ms": int(start_ms),
                "end_ms": int(end_ms),
                "duration_ms": int(max(0, end_ms - start_ms)),
                "script_text": _norm_space(text),
                "image_query": make_image_query(text),
                "assets": {
                    "image": None,
                    "audio_clip": None,
                },
            }
        )
    return scenes

