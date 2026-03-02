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
    Split determinista:
      1) Preferir separadores de párrafo.
      2) Si no alcanza, dividir por frases.
      3) Recortar a max_scenes (merge del resto en la última).
    """
    text = _norm_space(script_text)
    if not text:
        return [""]

    # 1) Intento por párrafos (si venía con saltos)
    chunks = [c.strip() for c in re.split(r"\n{2,}", script_text or "") if c.strip()]
    if len(chunks) <= 1:
        # 2) fallback por frases
        parts = re.split(r"(?<=[\.\!\?])\s+", text)
        chunks = [p.strip() for p in parts if p.strip()]

    if max_scenes < 1:
        max_scenes = 1

    if len(chunks) <= max_scenes:
        return chunks

    # 3) Merge determinista: primeras max_scenes-1, el resto a la última
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
