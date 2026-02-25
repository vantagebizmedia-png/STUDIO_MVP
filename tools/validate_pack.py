# -*- coding: utf-8 -*-
"""
Valida un pack exportado (pack_v03_*) y opcionalmente agrega hashes.

Uso:
  python tools/validate_pack.py --pack-dir <dir> [--fix]
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Dict

REQ_FILES = [
    ("pack.json", "pack.json"),
    ("manifest", "manifest_v03.json"),
    ("script", "artifacts/script.txt"),
    ("image",  "artifacts/image.png"),
    ("audio",  "artifacts/audio.wav"),
]

def sha256_file(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def read_json(p: Path) -> Dict:
    return json.loads(p.read_text(encoding="utf-8"))

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack-dir", required=True)
    ap.add_argument("--fix", action="store_true")
    args = ap.parse_args()

    pack_dir = Path(args.pack_dir).expanduser().resolve()
    if not pack_dir.exists() or not pack_dir.is_dir():
        raise SystemExit(f"ERROR: pack-dir invalido: {pack_dir}")

    problems = []
    paths: Dict[str, Path] = {}

    for key, rel in REQ_FILES:
        fp = pack_dir / rel
        paths[key] = fp
        if not fp.exists():
            problems.append(f"FALTA: {rel}")
        else:
            if fp.is_file() and fp.stat().st_size <= 0:
                problems.append(f"VACIO: {rel}")

    if not paths["pack.json"].exists():
        for pr in problems:
            print("ERROR:", pr)
        raise SystemExit("ERROR: pack.json faltante (no puedo continuar).")

    try:
        pack = read_json(paths["pack.json"])
    except Exception as e:
        raise SystemExit(f"ERROR: pack.json no es JSON valido: {e}")

    pj_paths = pack.get("paths") or {}
    expected = {
        "script": "artifacts/script.txt",
        "image": "artifacts/image.png",
        "audio": "artifacts/audio.wav",
        "manifest": "manifest_v03.json",
    }
    for k, rel in expected.items():
        if k in pj_paths and str(pj_paths[k]).replace("\\","/") != rel:
            problems.append(f"paths.{k} en pack.json != {rel} (tiene {pj_paths[k]})")

    if problems:
        for pr in problems:
            print("WARN:", pr)

    if args.fix:
        checksums = pack.get("checksums") or {}
        sha = checksums.get("sha256") or {}
        changed = False

        for k, rel in [("script","artifacts/script.txt"), ("image","artifacts/image.png"), ("audio","artifacts/audio.wav"), ("manifest","manifest_v03.json")]:
            fp = pack_dir / rel
            if fp.exists() and k not in sha:
                sha[k] = sha256_file(fp)
                changed = True

        if changed:
            checksums["sha256"] = sha
            pack["checksums"] = checksums
            paths["pack.json"].write_text(json.dumps(pack, ensure_ascii=False, indent=2), encoding="utf-8")
            print("OK: checksums agregados a pack.json")
        else:
            print("OK: checksums ya estaban presentes (no cambios)")

    if problems:
        print("\nRESULT: FAIL")
        return 2

    print("\nRESULT: OK")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
