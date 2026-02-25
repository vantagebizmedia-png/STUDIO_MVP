# -*- coding: utf-8 -*-
"""
Export v0.3 Content Pack desde manifest_v03.json.

Entrada:
  - manifest_v03.json (creado por StudioPipeline en work_dir)

Salida (pack dir):
  <out_root>/pack_v03_<tag>/
    manifest_v03.json
    pack.json
    artifacts/
      script.txt
      image.png
      audio.wav
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
from pathlib import Path
from datetime import datetime

def read_json(p: Path) -> dict:
    return json.loads(p.read_text(encoding="utf-8"))

def safe_copy(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(str(src), str(dst))

def derive_tag(manifest: dict) -> str:
    # Preferimos extraer tag del script filename: script_<tag>.txt
    sp = (manifest.get("artifacts") or {}).get("script") or ""
    name = Path(sp).name
    if name.startswith("script_") and name.endswith(".txt"):
        return name[len("script_"):-len(".txt")]
    # fallback: usar hash corto del image filename
    ip = (manifest.get("artifacts") or {}).get("image") or ""
    iname = Path(ip).name
    if iname.startswith("image_") and iname.endswith(".png"):
        return iname[len("image_"):-len(".png")]
    return datetime.utcnow().strftime("%Y%m%d_%H%M%S")

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", required=True, help="Path a manifest_v03.json")
    ap.add_argument("--out-root", default="", help="Root de export (default: STUDIO_WORKSPACE/exports o ./workspace/exports)")
    ap.add_argument("--overwrite", action="store_true", help="Si existe el pack dir, lo reemplaza (determinista).")
    args = ap.parse_args()

    mpath = Path(args.manifest).expanduser().resolve()
    if not mpath.exists():
        raise SystemExit(f"ERROR: manifest no existe: {mpath}")

    manifest = read_json(mpath)

    work_dir = (manifest.get("work_dir") or "")
    if not work_dir:
        # si falta, usamos carpeta del manifest
        work_dir = str(mpath.parent)
    work_dir = str(Path(work_dir).resolve())

    artifacts = manifest.get("artifacts") or {}
    script_p = Path(artifacts.get("script") or "")
    image_p  = Path(artifacts.get("image")  or "")
    audio_p  = Path(artifacts.get("audio")  or "")

    # Resolve relativos (por si acaso)
    if script_p and not script_p.is_absolute():
        script_p = Path(work_dir) / script_p
    if image_p and not image_p.is_absolute():
        image_p = Path(work_dir) / image_p
    if audio_p and not audio_p.is_absolute():
        audio_p = Path(work_dir) / audio_p

    missing = []
    for p in [("script", script_p), ("image", image_p), ("audio", audio_p)]:
        if not p[1] or not Path(p[1]).exists():
            missing.append(p[0])
    if missing:
        raise SystemExit(f"ERROR: faltan artifacts referenciados en manifest: {missing}")

    # out root
    out_root = args.out_root.strip()
    if not out_root:
        ws = os.environ.get("STUDIO_WORKSPACE", "").strip()
        if ws:
            out_root = str((Path(ws) / "exports").resolve())
        else:
            out_root = str((Path("workspace") / "exports").resolve())
    out_root_p = Path(out_root).resolve()
    out_root_p.mkdir(parents=True, exist_ok=True)

    tag = derive_tag(manifest)
    pack_dir = out_root_p / f"pack_v03_{tag}"
    if pack_dir.exists():
        if args.overwrite:
            shutil.rmtree(pack_dir)
        else:
            # no determinista, pero seguro (evita pisar)
            n = 2
            while (out_root_p / f"pack_v03_{tag}_{n}").exists():
                n += 1
            pack_dir = out_root_p / f"pack_v03_{tag}_{n}"

    (pack_dir / "artifacts").mkdir(parents=True, exist_ok=True)

    # Copias normalizadas
    safe_copy(mpath, pack_dir / "manifest_v03.json")
    safe_copy(script_p, pack_dir / "artifacts" / "script.txt")
    safe_copy(image_p,  pack_dir / "artifacts" / "image.png")
    safe_copy(audio_p,  pack_dir / "artifacts" / "audio.wav")

    pack_meta = {
        "pack_version": "v0.3",
        "tag": tag,
        "created_at_utc": datetime.utcnow().isoformat(timespec="seconds") + "Z",
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
        }
    }
    (pack_dir / "pack.json").write_text(json.dumps(pack_meta, ensure_ascii=False, indent=2), encoding="utf-8")

    print("OK: pack exportado")
    print("PACK_DIR:", str(pack_dir))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
