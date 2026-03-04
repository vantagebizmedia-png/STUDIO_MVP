# -*- coding: utf-8 -*-
"""
Scene Builder v0.3 (determinista)

Objetivo:
- Convertir un guion "libre" o un storyboard con etiquetas en una lista de escenas estructuradas.
- NO depende de ningún provider externo (solo parsing y reglas).
- Soporta separadores de escena:
  - '---' en línea sola (modo recomendado)
  - líneas en blanco (fallback)
  - oraciones agrupadas (último fallback)

Soporta (opcional) etiquetas por escena:
- NARRACION: ...
- ONSCREEN: ...
- STOCK_QUERY: ...

Si no hay etiquetas, la escena se interpreta como narración completa y se genera un
stock_query determinista (muy simple) para ayudar a búsquedas de stock.
"""

from __future__ import annotations

import re
import hashlib
from dataclasses import dataclass
from typing import List, Dict, Optional


def _sha8(text: str) -> str:
    return hashlib.sha256((text or "").encode("utf-8")).hexdigest()[:8]

def _normalize_newlines(text: str) -> str:
    t = text or ""
    # Si vienen saltos escapados "\\n" / "\\r\\n", conviértelos a saltos reales
    if "\\n" in t or "\\r" in t:
        t = t.replace("\\r\\n", "\n").replace("\\n", "\n").replace("\\r", "\n")
    # Normaliza CRLF reales también
    t = t.replace("\r\n", "\n").replace("\r", "\n")
    return t


def split_raw_scenes(text: str, max_scenes: int, mode: str = "auto") -> List[str]:
    t = _normalize_newlines(text or "").strip()
    if not t:
        return []
    n = max(1, int(max_scenes or 1))
    mode = (mode or "auto").strip().lower()

    # 1) '---' explícito
    if mode in ("auto", "dash", "---") and re.search(r"\n\s*---\s*\n", t):
        parts = [p.strip() for p in re.split(r"\n\s*---\s*\n", t) if p.strip()]
        return parts[:n] if parts else [t]

    # 2) bloques por líneas en blanco
    if mode in ("auto", "blank", "blankline", "paragraph"):
        parts = [p.strip() for p in re.split(r"\n\s*\n+", t) if p.strip()]
        if len(parts) >= 2:
            return parts[:n]

    # 3) oraciones (fallback)
    sents = [p.strip() for p in re.split(r"(?<=[\.\!\?])\s+", t) if p.strip()]
    if len(sents) <= 1:
        return [t]

    groups: List[str] = []
    per = max(1, (len(sents) + n - 1) // n)
    for i in range(0, len(sents), per):
        groups.append(" ".join(sents[i:i + per]).strip())
        if len(groups) >= n:
            break
    return groups if groups else [t]


_TAG_RE = re.compile(r"^(NARRACION|ONSCREEN|STOCK_QUERY)\s*:\s*(.*)$", re.IGNORECASE)
_SCENE_HDR_RE = re.compile(r"^ESCENA\s+\d+\s*$", re.IGNORECASE)


def _clean_text(s: str) -> str:
    s = re.sub(r"\s+", " ", (s or "").strip())
    return s


def _split_sentences(text: str) -> List[str]:
    out = [s.strip() for s in re.split(r"(?<=[\.\!\?])\s+", _clean_text(text)) if s.strip()]
    if out:
        return out
    t = _clean_text(text)
    return [t] if t else []


def _truncate_sentences(text: str, max_sentences: int) -> str:
    sent = _split_sentences(text)
    if not sent:
        return ""
    return " ".join(sent[:max(1, int(max_sentences or 1))]).strip()


def _truncate_words(text: str, max_words: int) -> str:
    words = [w for w in _clean_text(text).split(" ") if w]
    if not words:
        return ""
    return " ".join(words[:max(1, int(max_words or 1))]).strip()


def _sanitize_stock_query(text: str) -> str:
    t = (text or "").lower()
    t = t.replace('"', " ").replace("'", " ")
    t = re.sub(r"[^a-z0-9áéíóúüñ ]+", " ", t)
    return _clean_text(t)


def _fallback_narration(seed: str) -> str:
    base = _truncate_words(_clean_text(seed), 6)
    if not base:
        base = "idea principal del tema"
    txt = f"{base} guía esta escena. El mensaje se explica con claridad."
    return _truncate_sentences(txt, 2)


def _fallback_onscreen(seed: str) -> str:
    _ = seed
    return _truncate_words("Idea clave enfoque claro uso practico", 6)


def _fallback_stock_query(seed: str) -> str:
    base = _sanitize_stock_query(seed)
    if base:
        return _truncate_words(base, 4)
    return "persona explicando tema estudio"


@dataclass
class SceneSpec:
    index: int
    tag: str
    narration: str
    onscreen: str
    stock_query: str

    @property
    def audio_text(self) -> str:
        return self.narration or ""

    @property
    def image_prompt(self) -> str:
        return self.stock_query or self.narration or ""


def parse_scene_block(block: str) -> Dict[str, str]:
    narration_lines = []
    onscreen = ""
    stock_query = ""

    for raw in _normalize_newlines(block or "").splitlines():
        line = raw.strip()
        if not line:
            continue
        if line == "---":
            continue
        if _SCENE_HDR_RE.match(line):
            continue
        m = _TAG_RE.match(line)
        if m:
            key = m.group(1).upper()
            val = m.group(2).strip()
            if key == "NARRACION":
                narration_lines.append(val)
            elif key == "ONSCREEN":
                onscreen = val
            elif key == "STOCK_QUERY":
                stock_query = val
            continue
        narration_lines.append(line)

    narration = _clean_text(" ".join(narration_lines))
    onscreen = _clean_text(onscreen)
    stock_query = _sanitize_stock_query(stock_query)

    if not narration:
        narration = _fallback_narration(block)
    if not onscreen:
        onscreen = _fallback_onscreen(narration or block)
    if not stock_query:
        stock_query = _fallback_stock_query(narration or onscreen or block)

    narration = _truncate_sentences(narration, 3)
    onscreen = _truncate_words(onscreen, 10)
    stock_query = _truncate_words(_sanitize_stock_query(stock_query), 6)

    if not narration:
        narration = _truncate_sentences(_fallback_narration(block), 3)
    if not onscreen:
        onscreen = _truncate_words(_fallback_onscreen(block), 10)
    if not stock_query:
        stock_query = _truncate_words(_sanitize_stock_query(_fallback_stock_query(block)), 6)

    return {"narration": narration, "onscreen": onscreen, "stock_query": stock_query}


def build_scenes(script: str, *, max_scenes: int, split_mode: str = "auto", base_tag: Optional[str] = None) -> List[SceneSpec]:
    raw = split_raw_scenes(script, max_scenes=max_scenes, mode=split_mode)
    if not raw:
        return []

    if base_tag is None:
        base_tag = _sha8(script or "")

    scenes: List[SceneSpec] = []
    for idx, block in enumerate(raw, start=1):
        p = parse_scene_block(block)
        stag = f"{base_tag}_s{idx:02d}"
        scenes.append(SceneSpec(
            index=idx,
            tag=stag,
            narration=p["narration"],
            onscreen=p["onscreen"],
            stock_query=p["stock_query"],
        ))
    return scenes


def render_scenes_strict(scenes: List[SceneSpec]) -> str:
    blocks: List[str] = []
    for s in scenes or []:
        blocks.append(
            "\n".join(
                [
                    f"ESCENA {int(s.index):02d}",
                    f"NARRACION: {s.narration}",
                    f"ONSCREEN: {s.onscreen}",
                    f"STOCK_QUERY: {s.stock_query}",
                ]
            ).strip()
        )
    return "\n---\n".join([b for b in blocks if b]).strip()
