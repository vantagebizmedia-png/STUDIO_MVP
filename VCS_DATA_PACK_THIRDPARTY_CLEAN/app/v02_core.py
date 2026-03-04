# -*- coding: utf-8 -*-
"""STUDIO v0.2 core: Input -> Generate -> Export -> Replay (verifiable)."""

from __future__ import annotations

import hashlib
import os
from pathlib import Path
from typing import Any, Dict, List, Tuple

from app.main import export_pack, generate_pack, read_json, write_json, split_topics, utc_now_iso

REPLAY_SCHEMA = "STUDIO_REPLAY_V1"




def write_social_exports(pack_dir: str) -> None:
    """
    Exporta archivos listos para pegar:
    - script.txt: guion completo
    - caption.txt: caption corto
    - hashtags.txt: hashtags simples
    """
    import json

    pack_dir = os.path.abspath(pack_dir)

    # Leer script_by_clips.json
    p = os.path.join(pack_dir, "script_by_clips.json")
    try:
        with open(p, "r", encoding="utf-8") as f:
            clips = json.load(f)
    except Exception:
        clips = None

    lines = []
    if isinstance(clips, list):
        for c in clips:
            if not isinstance(c, dict):
                continue
            cid = str(c.get("clip_id", "")).strip()
            purpose = str(c.get("purpose", "")).strip()
            vo = (c.get("voiceover", "") or "").strip()
            if not vo:
                continue
            head = f"{cid} [{purpose}]".strip()
            if head and head != "[]":
                lines.append(head)
            lines.append(vo)
            lines.append("")  # blank line between clips

    script_txt = "\n".join(lines).strip() + "\n" if lines else ""

    # Caption simple (determinista): usa el primer clip como base
    caption = ""
    if isinstance(clips, list) and clips:
        first = clips[0] if isinstance(clips[0], dict) else {}
        vo0 = (first.get("voiceover", "") or "").strip()
        if vo0:
            caption = vo0.split("\n")[0].strip()

    if caption:
        caption_txt = caption + "\n"
    else:
        caption_txt = ""

    # Hashtags simples (determinista): desde manifest topics si existen, si no del prompt split
    tags = []
    mp = os.path.join(pack_dir, "manifest.json")
    try:
        man = read_json(mp)
    except Exception:
        man = None

    topics = []
    if isinstance(man, dict):
        t = man.get("topics")
        if isinstance(t, list):
            topics = [str(x).strip() for x in t if str(x).strip()]

    # Normaliza hashtags
    for t in topics:
        t2 = t.lower()
        t2 = "".join(ch if (ch.isalnum() or ch == " ") else " " for ch in t2)
        t2 = "_".join([w for w in t2.split() if w])
        if t2:
            tags.append("#" + t2)

    # fallback mínimo
    if not tags:
        tags = ["#shorts", "#tips"]

    hashtags_txt = "\n".join(tags) + "\n"

    # Escribir archivos
    with open(os.path.join(pack_dir, "script.txt"), "w", encoding="utf-8-sig", newline="\n") as f:
        f.write(script_txt)

    with open(os.path.join(pack_dir, "caption.txt"), "w", encoding="utf-8-sig", newline="\n") as f:
        f.write(caption_txt)

    with open(os.path.join(pack_dir, "hashtags.txt"), "w", encoding="utf-8-sig", newline="\n") as f:
        f.write(hashtags_txt)
# --- mojibake repair (deterministic) ---
def _fix_mojibake(s: str) -> str:
    if not isinstance(s, str):
        return s

    # Use unicode escapes so this function never gets mojibake'd by the console/editor.
    MARK_A_TILDE = "\u00C3"  # U+00C3 marker
    MARK_A_CIRC  = "\u00C2"  # U+00C2 marker
    MARK_FLORIN  = "\u0192"  # U+0192 marker
    MARK_REPL    = "\uFFFD"  # U+FFFD replacement char

    if (MARK_A_TILDE not in s) and (MARK_A_CIRC not in s) and (MARK_FLORIN not in s) and (MARK_REPL not in s):
        return s

    import re

    def fix_token(tok: str) -> str:
        if (MARK_A_TILDE not in tok) and (MARK_A_CIRC not in tok) and (MARK_FLORIN not in tok) and (MARK_REPL not in tok):
            return tok

        t = tok
        for _ in range(3):
            try:
                t2 = t.encode("cp1252").decode("utf-8")
            except Exception:
                break
            if t2 == t:
                break
            t = t2
        return t

    parts = re.split(r"(\s+)", s)  # keep spaces/newlines
    for i, p in enumerate(parts):
        if p and (not p.isspace()):
            parts[i] = fix_token(p)

    return "".join(parts)

def _fix_obj(obj):
    if isinstance(obj, str):
        return _fix_mojibake(obj)
    if isinstance(obj, list):
        return [_fix_obj(x) for x in obj]
    if isinstance(obj, dict):
        return {k: _fix_obj(v) for k, v in obj.items()}
    return obj

def _repair_pack_text(pack_dir: str) -> None:
    import json
    for root, dirs, files in os.walk(pack_dir):
        dirs.sort()
        files.sort()
        for fn in files:
            if not fn.lower().endswith(".json"):
                continue
            if fn == "replay.json":
                continue
            p = os.path.join(root, fn)
            try:
                with open(p, "r", encoding="utf-8") as f:
                    obj = json.load(f)
            except Exception:
                continue
            fixed = _fix_obj(obj)
            if fixed != obj:
                txt = json.dumps(fixed, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
                with open(p, "w", encoding="utf-8", newline="\n") as f:
                    f.write(txt)
def _sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _collect_pack_files(pack_dir: str) -> List[Tuple[str, str]]:
    items: List[Tuple[str, str]] = []
    pack_dir = os.path.abspath(pack_dir)
    for root, dirs, files in os.walk(pack_dir):
        dirs.sort()
        files.sort()
        for fn in files:
            full = os.path.join(root, fn)
            rel = Path(full).relative_to(Path(pack_dir)).as_posix()
            items.append((os.path.abspath(full), rel))
    return items


def _pack_files_sha256(pack_dir: str) -> Dict[str, str]:
    out: Dict[str, str] = {}
    for full, rel in _collect_pack_files(pack_dir):
        if rel.lower().endswith(".zip") or rel == "replay.json":
            continue
        out[rel] = _sha256_file(full)
    return out


def _rewrite_manifest_created_at(pack_dir: str, created_at_utc: str) -> None:
    manifest_path = os.path.join(pack_dir, "manifest.json")
    manifest = read_json(manifest_path)
    if not isinstance(manifest, dict):
        raise ValueError("manifest.json invalid")
    manifest["created_at_utc"] = created_at_utc
    write_json(manifest_path, manifest)


def generate_v02(
    *,
    prompt: str,
    seed: int = 123,
    target_format: str = "reel_short",
    language: str = "es",
    style_id: str = "infografia",
    voice_pacing: str = "medio",
    audience_level: str = "principiante",
) -> Dict[str, Any]:
    created_at = utc_now_iso()
    topics = split_topics(prompt)

    pack_dir = generate_pack(
        topics=topics,
        target_format=target_format,
        language=language,
        style_id=style_id,
        voice_pacing=voice_pacing,
        audience_level=audience_level,
        constraints=[],
        seed=int(seed),
    )

    _repair_pack_text(pack_dir)



    _rewrite_manifest_created_at(pack_dir, created_at)

    zip_path = os.path.join(os.path.dirname(os.path.abspath(pack_dir)), "content_pack.zip")
    zip_out = export_pack(pack_dir, zip_path)

    # post-export repair (export_pack may rewrite JSON)
    _repair_pack_text(pack_dir)
    zip_out = export_pack(pack_dir, zip_path)

    # post-export repair (export_pack may rewrite JSON)
    _repair_pack_text(pack_dir)
    zip_out = export_pack(pack_dir, zip_path)


    write_social_exports(pack_dir)


    zip_out = export_pack(pack_dir, zip_path)

    files_sha = _pack_files_sha256(pack_dir)

    replay_obj = {
        "schema": REPLAY_SCHEMA,
        "created_at_utc": created_at,
        "inputs": {
            "prompt": prompt,
            "seed": int(seed),
            "target_format": target_format,
            "language": language,
            "style_id": style_id,
            "voice_pacing": voice_pacing,
            "audience_level": audience_level,
        },
        "evidence": {
            "pack_files_sha256": files_sha,
            "zip_sha256": zip_out.get("zip_sha256"),
        },
    }

    replay_path = os.path.join(pack_dir, "replay.json")
    write_json(replay_path, replay_obj)

    return {
        "ok": True,
        "pack_dir": os.path.abspath(pack_dir),
        "replay_path": os.path.abspath(replay_path),
        "zip_path": os.path.abspath(zip_out.get("zip_path", zip_path)),
        "zip_sha256": zip_out.get("zip_sha256"),
    }


def replay_v02(replay_path: str) -> Dict[str, Any]:
    replay_path = os.path.abspath(replay_path)
    obj = read_json(replay_path)
    if not isinstance(obj, dict) or obj.get("schema") != REPLAY_SCHEMA:
        raise ValueError("invalid replay.json or schema")

    inputs = obj.get("inputs") or {}
    evidence = obj.get("evidence") or {}

    prompt = str(inputs.get("prompt") or "").strip()
    if not prompt:
        raise ValueError("replay.json: inputs.prompt empty")

    seed = int(inputs.get("seed", 123))
    target_format = str(inputs.get("target_format") or "reel_short")
    language = str(inputs.get("language") or "es")
    style_id = str(inputs.get("style_id") or "infografia")
    voice_pacing = str(inputs.get("voice_pacing") or "medio")
    audience_level = str(inputs.get("audience_level") or "principiante")

    expected_files_sha = evidence.get("pack_files_sha256") or {}
    expected_zip_sha = str(evidence.get("zip_sha256") or "").strip()
    created_at = str(obj.get("created_at_utc") or "").strip() or utc_now_iso()

    pack_dir = generate_pack(
        topics=split_topics(prompt),
        target_format=target_format,
        language=language,
        style_id=style_id,
        voice_pacing=voice_pacing,
        audience_level=audience_level,
        constraints=[],
        seed=seed,
    )

    _repair_pack_text(pack_dir)



    _rewrite_manifest_created_at(pack_dir, created_at)

    zip_path = os.path.join(os.path.dirname(os.path.abspath(pack_dir)), "content_pack.zip")
    zip_out = export_pack(pack_dir, zip_path)


    write_social_exports(pack_dir)


    zip_out = export_pack(pack_dir, zip_path)

    files_sha = _pack_files_sha256(pack_dir)

    diffs: List[Dict[str, Any]] = []
    if isinstance(expected_files_sha, dict) and expected_files_sha:
        all_keys = sorted(set(files_sha.keys()) | set(expected_files_sha.keys()))
        for k in all_keys:
            a = expected_files_sha.get(k)
            b = files_sha.get(k)
            if a != b:
                diffs.append({"file": k, "expected": a, "got": b})

    zip_ok = True
    if expected_zip_sha:
        zip_ok = (expected_zip_sha == str(zip_out.get("zip_sha256") or ""))

    return {
        "ok": (len(diffs) == 0 and zip_ok),
        "pack_dir": os.path.abspath(pack_dir),
        "zip_path": os.path.abspath(zip_out.get("zip_path", zip_path)),
        "zip_sha256": zip_out.get("zip_sha256"),
        "zip_expected": expected_zip_sha or None,
        "zip_ok": zip_ok,
        "diffs": diffs,
    }


def extract_script_preview(pack_dir: str, max_chars: int = 4000) -> str:
    import json

    p = os.path.join(os.path.abspath(pack_dir), "script_by_clips.json")
    try:
        with open(p, "r", encoding="utf-8") as f:
            clips = json.load(f)
    except Exception:
        return "(No pude leer script_by_clips.json)"

    if not isinstance(clips, list):
        return "(script_by_clips.json no es lista)"

    parts: List[str] = []
    for c in clips:
        if not isinstance(c, dict):
            continue
        cid = c.get("clip_id", "")
        purpose = c.get("purpose", "")
        vo = (c.get("voiceover", "") or "").strip()
        if vo:
            parts.append(f"{cid} [{purpose}]\n{vo}\n")

    out = "\n".join(parts).strip()
    if len(out) > max_chars:
        out = out[: max_chars - 20] + "\n...(cortado)"
    return out
