# -*- coding: utf-8 -*-
# app/music_picker.py
from __future__ import annotations

import os, re, hashlib, random
from typing import List, Tuple

AUDIO_EXTS = (".mp3", ".wav", ".m4a", ".aac")

def _sha_int(s: str) -> int:
    h = hashlib.sha256(s.encode("utf-8")).hexdigest()
    return int(h[:16], 16)

def _tokens(s: str) -> List[str]:
    s = s.lower()
    s = re.sub(r"[^a-z0-9áéíóúüñ]+", " ", s, flags=re.I)
    return [t for t in s.split() if t]

def _list_music_files(music_dir: str) -> List[str]:
    if not music_dir or not os.path.isdir(music_dir):
        return []
    out = []
    for name in os.listdir(music_dir):
        if name.startswith("_"):
            continue
        p = os.path.join(music_dir, name)
        if os.path.isfile(p) and name.lower().endswith(AUDIO_EXTS):
            out.append(p)
    out.sort(key=lambda x: os.path.basename(x).lower())
    return out

def _topic_to_tags(topic: str) -> List[str]:
    t = " ".join(_tokens(topic))
    tags = []
    if any(k in t for k in ["disciplina","hábitos","habitos","motiv","mentalidad","productividad","enfoque","rutina","éxito","exito"]):
        tags += ["motiv","uplift","lofi","ambient","inspire","positive"]
    if any(k in t for k in ["educa","tutorial","aprender","datos","ciencia","historia","explica","cómo","como"]):
        tags += ["calm","ambient","documentary","soft","corporate"]
    if any(k in t for k in ["negocio","empresa","marketing","ventas","cliente","dinero","startup"]):
        tags += ["corporate","clean","upbeat","modern"]
    if any(k in t for k in ["misterio","terror","suspenso","suspense","oscuro"]):
        tags += ["dark","suspense","cinematic"]
    if not tags:
        tags = ["lofi","ambient","calm"]
    # únicos
    seen=set(); out=[]
    for x in tags:
        if x not in seen:
            seen.add(x); out.append(x)
    return out

def _match_score(path: str, wanted: List[str]) -> int:
    base = os.path.basename(path).lower()
    toks = set(_tokens(base))
    score = 0
    for w in wanted:
        w2 = w.lower()
        if w2 in toks or w2 in base:
            score += 2
    return score

def pick_music_path(*, topic: str, seed: int, mode: str, music_path: str, music_dir: str="music", tag: str="") -> str:
    mode = (mode or "fixed").strip().lower()
    if mode == "off":
        return ""

    if mode == "fixed":
        mp = (music_path or "").strip()
        if mp and os.path.isfile(mp):
            return mp
        # fallback
        bg = os.path.join(music_dir, "bg.mp3")
        if os.path.isfile(bg):
            return bg
        files = _list_music_files(music_dir)
        return files[0] if files else ""

    files = _list_music_files(music_dir)
    if not files:
        return ""

    if mode == "menu":
        print("\n Música disponible:")
        for i, p in enumerate(files, 1):
            print(f"  {i:02d}) {os.path.basename(p)}")
        try:
            raw = input("Elige número (Enter cancela): ").strip()
        except Exception:
            return ""
        if not raw:
            return ""
        try:
            n = int(raw)
        except Exception:
            return ""
        if 1 <= n <= len(files):
            return files[n-1]
        return ""

    wanted = []
    if tag:
        wanted += _tokens(tag)
    if mode == "topic":
        wanted += _topic_to_tags(topic)

    if wanted:
        scored: List[Tuple[int,str]] = [(_match_score(p, wanted), p) for p in files]
        scored.sort(key=lambda x: (-x[0], os.path.basename(x[1]).lower()))
        best = scored[0][0]
        pool = [p for s, p in scored if s == best and s > 0]
        if pool:
            r = random.Random(_sha_int(f"{seed}|{topic}|{mode}|{tag}|pool"))
            return pool[r.randrange(len(pool))]

    r = random.Random(_sha_int(f"{seed}|{mode}|{tag}"))
    return files[r.randrange(len(files))]
