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
import json
import os
import shutil
from pathlib import Path
from datetime import datetime, timezone

def read_json(p: Path) -> dict:
    return json.loads(p.read_text(encoding="utf-8"))

def read_json_sig(p: Path) -> dict:
    return json.loads(p.read_text(encoding="utf-8-sig"))

def safe_copy(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(str(src), str(dst))

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
    return datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")

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

    work_dir = (manifest.get("work_dir") or "")
    if not work_dir:
        work_dir = str(mpath.parent)
    work_dir = str(Path(work_dir).resolve())

    artifacts = manifest.get("artifacts") or {}
    script_p = Path(artifacts.get("script") or "")
    image_p  = Path(artifacts.get("image")  or "")
    audio_p  = Path(artifacts.get("audio")  or "")

    if script_p and not script_p.is_absolute():
        script_p = Path(work_dir) / script_p
    if image_p and not image_p.is_absolute():
        image_p = Path(work_dir) / image_p
    if audio_p and not audio_p.is_absolute():
        audio_p = Path(work_dir) / audio_p

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
    safe_copy(mpath, pack_dir / "manifest_v03.json")
    safe_copy(script_p, pack_dir / "artifacts" / "script.txt")
    safe_copy(image_p,  pack_dir / "artifacts" / "image.png")
    safe_copy(audio_p,  pack_dir / "artifacts" / "audio.wav")

    script_txt = script_p.read_text(encoding="utf-8")
    # FIX: preservar music_strategy.json si ya existe (evita sobreescribir estrategias ricas)
    _existing_ms = None
    for _ms_candidate in [
        Path(work_dir) / "music_strategy.json",
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
        for s in scenes:
            idx = int(s.get("index", 0) or 0)
            arts = (s.get("artifacts") or {})
            sp = Path(arts.get("script") or "")
            ip = Path(arts.get("image") or "")
            ap2 = Path(arts.get("audio") or "")

            # resolver relativos contra work_dir por si acaso
            if sp and not sp.is_absolute(): sp = Path(work_dir) / sp
            if ip and not ip.is_absolute(): ip = Path(work_dir) / ip
            if ap2 and not ap2.is_absolute(): ap2 = Path(work_dir) / ap2

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

    pack_meta = {
        "pack_version": "v0.3",
        "tag": tag,
        "created_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00","Z"),
        "source": {
            "manifest_path": str(mpath),
            "work_dir": work_dir,
            "config_path": manifest.get("config_path",""),
            "providers": manifest.get("providers", {}),
        },
        "paths": {
            "pack_dir": str(pack_dir),
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
