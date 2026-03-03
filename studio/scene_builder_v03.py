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
def split_script_into_scenes(script_text: str, max_scenes: int) -> list[str]:
    """
    Split determinista en hasta N escenas, aunque venga en 1 párrafo.
    Regla: troceo contiguo por palabras, repartiendo casi-equitativo.
    - No usa heurísticas que colapsen a 1 escena.
    - Si hay pocas palabras, devuelve <= max_scenes (nunca 0).
    """
    txt = (script_text or "").strip()
    if max_scenes < 1:
        max_scenes = 1

    if not txt:
        return [""]

    if max_scenes == 1:
        return [txt]

    words = txt.split()
    if not words:
        return [""]

    # n escenas objetivo (pero no más que #words para evitar escenas vacías)
    n = min(int(max_scenes), len(words))
    if n < 1:
        n = 1

    # tamaño base + reparto de rem
    base = len(words) // n
    rem = len(words) - (base * n)

    out: list[str] = []
    i = 0
    for k in range(1, n + 1):
        take = base + (1 if k <= rem else 0)
        if take < 1:
            take = 1
        chunk_words = words[i : i + take]
        i += take
        out.append(" ".join(chunk_words).strip())

    # Si quedaron palabras (por seguridad), se agregan a la última escena
    if i < len(words) and out:
        out[-1] = (out[-1] + " " + " ".join(words[i:])).strip()

    # Garantía: nunca devolver lista vacía
    if not out:
        return [txt]

    return out
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


