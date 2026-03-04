# -*- coding: utf-8 -*-
"""
Export v0.3 Content Pack desde manifest_v03.json.

Si manifest trae scenes[]:
- copia artifacts/script.txt (script global)
- copia artifacts/image.png / audio.wav (escena 1 por compat)
- además copia todas las escenas a:
  artifacts/scenes/scene_01/{script.txt,image.png,audio.wav}
  artifacts/scenes/scene_02/...
y escribe pack.json con sección scenes[] (paths relativos)
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
from pathlib import Path

def read_json(p: Path) -> dict:
    return json.loads(p.read_text(encoding="utf-8"))

def read_json_sig(p: Path) -> dict:
    return json.loads(p.read_text(encoding="utf-8-sig"))

def safe_copy(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(str(src), str(dst))

def _rel_to_base(path: str, base_dir: Path) -> str:
    p = str(path or "").strip()
    if not p:
        return ""
    base_abs = base_dir.resolve()
    src = Path(p)
    if not src.is_absolute():
        src = (base_abs / src).resolve()
    return os.path.relpath(str(src), start=str(base_abs)).replace("\\", "/")


def _resolve_scene_sources(work_dir: Path, idx: int, arts: dict) -> tuple[Path, Path, Path]:
    stable_dir = work_dir / "artifacts" / "scenes" / f"scene_{idx:02d}"
    stable_script = stable_dir / "script.txt"
    stable_image = stable_dir / "image.png"
    stable_audio = stable_dir / "audio.wav"
    if stable_script.exists() and stable_image.exists() and stable_audio.exists():
        return stable_script, stable_image, stable_audio

    sp = Path(arts.get("script") or "")
    ip = Path(arts.get("image") or "")
    ap = Path(arts.get("audio") or "")
    if sp and not sp.is_absolute():
        sp = work_dir / sp
    if ip and not ip.is_absolute():
        ip = work_dir / ip
    if ap and not ap.is_absolute():
        ap = work_dir / ap
    return sp, ip, ap


def _scene_index(row: dict) -> int:
    try:
        return int(row.get("index", 0) or 0)
    except Exception:
        return 0

def _compact_music_strategy_text(*parts: object) -> str:
    vals = []
    for p in parts:
        s = str(p or "").strip().lower()
        if s:
            vals.append(s)
    return " ".join(vals)

def _pick_auto_music_strategy(script_text: str, manifest: dict) -> dict:
    text = _compact_music_strategy_text(script_text)

    providers = manifest.get("providers") or {}
    provider_name = str((providers.get("music") or "local_music")).strip()

    rules = [
        (["motivación", "motivacion", "disciplina", "productividad", "hábito", "habito", "hábitos", "habitos", "enfoque", "energía", "energia"],
         "motivational upbeat corporate background",
         "high",
         "matched_keywords_productivity"),
        (["meditación", "meditacion", "calma", "relax", "relajación", "relajacion", "suave"],
         "calm ambient background",
         "low",
         "matched_keywords_calm"),
        (["noticias", "explicación", "explicacion", "tutorial", "guía", "guia", "documental"],
         "clean modern documentary background",
         "medium",
         "matched_keywords_explainer"),
    ]

    for keywords, query, energy, reason in rules:
        if any(k in text for k in keywords):
            return {
                "music_source_mode": "local",
                "music_provider_override": provider_name,
                "music_query": query,
                "music_strategy_reason": reason,
                "music_energy": energy,
            }

    return {
        "music_source_mode": "local",
        "music_provider_override": provider_name,
        "music_query": "motivational background instrumental",
        "music_strategy_reason": "default_export_v03_from_script",
        "music_energy": "medium",
    }

def derive_tag(manifest: dict) -> str:
    sp = (manifest.get("artifacts") or {}).get("script") or ""
    name = Path(sp).name
    if name.startswith("script_") and name.endswith(".txt"):
        return name[len("script_"):-len(".txt")]
    ip = (manifest.get("artifacts") or {}).get("image") or ""
    iname = Path(ip).name
    if iname.startswith("image_") and iname.endswith(".png"):
        return iname[len("image_"):-len(".png")]
    stable_blob = {
        "artifacts": manifest.get("artifacts") or {},
        "scenes": manifest.get("scenes") or [],
    }
    raw = json.dumps(stable_blob, sort_keys=True, ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()[:8]

def pick_default_out_root(manifest: dict) -> Path:
    cfgp = (manifest.get("config_path") or "").strip()
    if cfgp:
        p = Path(cfgp).expanduser()
        if p.exists():
            try:
                cfg = read_json_sig(p.resolve())
                ws = (cfg.get("workspace") or "").strip()
                if ws:
                    ws_p = Path(ws)
                    if not ws_p.is_absolute():
                        ws_p = (Path.cwd() / ws_p).resolve()
                    return (ws_p / "exports").resolve()
            except Exception:
                pass
    env_ws = os.environ.get("STUDIO_WORKSPACE", "").strip()
    if env_ws:
        return (Path(env_ws).expanduser().resolve() / "exports").resolve()
    return (Path("workspace").resolve() / "exports").resolve()

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", required=True, help="Path a manifest_v03.json")
    ap.add_argument("--out-root", default="", help="Root de export (default: workspace del config)")
    ap.add_argument("--overwrite", action="store_true", help="Si existe el pack dir, lo reemplaza.")
    args = ap.parse_args()

    mpath = Path(args.manifest).expanduser().resolve()
    if not mpath.exists():
        raise SystemExit(f"ERROR: manifest no existe: {mpath}")

    manifest = read_json(mpath)

    manifest_dir = mpath.parent.resolve()
    work_dir = manifest_dir
    manifest_work_dir = str(manifest.get("work_dir") or "").strip()
    if manifest_work_dir:
        wd = Path(manifest_work_dir)
        if not wd.is_absolute():
            wd = (manifest_dir / wd)
        work_dir = wd.resolve()

    artifacts = manifest.get("artifacts") or {}
    script_p = Path(artifacts.get("script") or "")
    image_p  = Path(artifacts.get("image")  or "")
    audio_p  = Path(artifacts.get("audio")  or "")

    if script_p and not script_p.is_absolute():
        script_p = work_dir / script_p
    if image_p and not image_p.is_absolute():
        image_p = work_dir / image_p
    if audio_p and not audio_p.is_absolute():
        audio_p = work_dir / audio_p

    missing = []
    for k, p in [("script", script_p), ("image", image_p), ("audio", audio_p)]:
        if not p or not p.exists():
            missing.append(k)
    if missing:
        raise SystemExit(f"ERROR: faltan artifacts referenciados en manifest: {missing}")

    out_root = args.out_root.strip()
    out_root_p = Path(out_root).resolve() if out_root else pick_default_out_root(manifest)
    out_root_p.mkdir(parents=True, exist_ok=True)

    tag = derive_tag(manifest)
    pack_dir = out_root_p / f"pack_v03_{tag}"
    if pack_dir.exists():
        if args.overwrite:
            shutil.rmtree(pack_dir)
        else:
            n = 2
            while (out_root_p / f"pack_v03_{tag}_{n}").exists():
                n += 1
            pack_dir = out_root_p / f"pack_v03_{tag}_{n}"

    (pack_dir / "artifacts").mkdir(parents=True, exist_ok=True)

    # Copias base (compat)
    safe_copy(script_p, pack_dir / "artifacts" / "script.txt")
    safe_copy(image_p,  pack_dir / "artifacts" / "image.png")
    safe_copy(audio_p,  pack_dir / "artifacts" / "audio.wav")

    script_txt = script_p.read_text(encoding="utf-8")
    # FIX: preservar music_strategy.json si ya existe (evita sobreescribir estrategias ricas)
    _existing_ms = None
    for _ms_candidate in [
        work_dir / "music_strategy.json",
        mpath.parent / "music_strategy.json",
    ]:
        if _ms_candidate.exists():
            try:
                _existing_ms = json.loads(_ms_candidate.read_text(encoding="utf-8"))
                break
            except Exception:
                pass

    if _existing_ms is not None:
        music_strategy = _existing_ms
    else:
        music_strategy = _pick_auto_music_strategy(script_txt, manifest)
    (pack_dir / "music_strategy.json").write_text(
        json.dumps(music_strategy, ensure_ascii=False, indent=2),
        encoding="utf-8"
    )

    scenes_rel = []
    scenes = manifest.get("scenes") or []
    if isinstance(scenes, list) and scenes:
        scenes_sorted = sorted(
            [dict(s or {}) for s in scenes if isinstance(s, dict)],
            key=_scene_index,
        )
        for s in scenes_sorted:
            idx = int(s.get("index", 0) or 0)
            if idx <= 0:
                continue

            arts = (s.get("artifacts") or {})
            sp, ip, ap2 = _resolve_scene_sources(work_dir, idx, arts)
            if not (sp.exists() and ip.exists() and ap2.exists()):
                continue

            sdir = pack_dir / "artifacts" / "scenes" / f"scene_{idx:02d}"
            safe_copy(sp,  sdir / "script.txt")
            safe_copy(ip,  sdir / "image.png")
            safe_copy(ap2, sdir / "audio.wav")

            scenes_rel.append({
                "index": idx,
                # Compat + utilidad: el pipeline v0.3 produce campos ricos por escena
                # (narration/onscreen/stock_query). Si no existe, cae a "text".
                "text": (s.get("narration") or s.get("audio_text") or s.get("text", "")),
                "tag": s.get("tag", ""),
                "narration": s.get("narration", ""),
                "onscreen": s.get("onscreen", ""),
                "stock_query": s.get("stock_query", ""),
                "image_prompt": s.get("image_prompt", ""),
                "audio_text": s.get("audio_text", ""),
                "script": f"artifacts/scenes/scene_{idx:02d}/script.txt",
                "image":  f"artifacts/scenes/scene_{idx:02d}/image.png",
                "audio":  f"artifacts/scenes/scene_{idx:02d}/audio.wav",
            })

    manifest_export = dict(manifest)
    manifest_export["work_dir"] = "."
    manifest_export["config_path"] = _rel_to_base(str(manifest.get("config_path", "")), manifest_dir)
    base_arts = dict(manifest_export.get("artifacts") or {})
    manifest_export["artifacts"] = {
        "script": _rel_to_base(str(base_arts.get("script", "")), work_dir),
        "image": _rel_to_base(str(base_arts.get("image", "")), work_dir),
        "audio": _rel_to_base(str(base_arts.get("audio", "")), work_dir),
    }
    in_scenes = manifest_export.get("scenes") or []
    if isinstance(in_scenes, list) and in_scenes:
        scenes_export = []
        for s in in_scenes:
            row = dict(s or {})
            arts = dict(row.get("artifacts") or {})
            row["artifacts"] = {
                "script": _rel_to_base(str(arts.get("script", "")), work_dir),
                "image": _rel_to_base(str(arts.get("image", "")), work_dir),
                "audio": _rel_to_base(str(arts.get("audio", "")), work_dir),
            }
            scenes_export.append(row)
        manifest_export["scenes"] = scenes_export
    (pack_dir / "manifest_v03.json").write_text(json.dumps(manifest_export, ensure_ascii=False, indent=2), encoding="utf-8")

    pack_meta = {
        "pack_version": "v0.3",
        "tag": tag,
        "source": {
            "manifest_path": "manifest_v03.json",
            "work_dir": _rel_to_base(str(work_dir), manifest_dir),
            "config_path": _rel_to_base(str(manifest.get("config_path", "")), manifest_dir),
            "providers": manifest.get("providers", {}),
        },
        "paths": {
            "script": "artifacts/script.txt",
            "image":  "artifacts/image.png",
            "audio":  "artifacts/audio.wav",
            "manifest": "manifest_v03.json",
        },
    }
    if scenes_rel:
        pack_meta["scenes"] = scenes_rel

    (pack_dir / "pack.json").write_text(json.dumps(pack_meta, ensure_ascii=False, indent=2), encoding="utf-8")

    print("OK: pack exportado")
    print("PACK_DIR:", str(pack_dir))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
