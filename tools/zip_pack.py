# -*- coding: utf-8 -*-
"""
Zippea un pack exportado (pack_v03_*) en un .zip listo para enviar.

Uso:
  python tools/zip_pack.py --pack-dir <dir> [--out <zip>] [--overwrite]
"""
from __future__ import annotations

import argparse
import os
import zipfile
from pathlib import Path
from datetime import datetime, timezone

def default_out(pack_dir: Path) -> Path:
    ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    return pack_dir.parent / f"{pack_dir.name}_{ts}.zip"

def add_dir(z: zipfile.ZipFile, root: Path, rel_base: Path) -> None:
    for p in root.rglob("*"):
        if p.is_dir():
            continue
        arc = rel_base / p.relative_to(root)
        z.write(p, arcname=str(arc).replace("\\", "/"))

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack-dir", required=True, help="Directorio del pack (ej: .../pack_v03_xxxx)")
    ap.add_argument("--out", default="", help="Ruta zip de salida (default: junto al pack)")
    ap.add_argument("--overwrite", action="store_true", help="Si existe el zip, lo reemplaza.")
    args = ap.parse_args()

    pack_dir = Path(args.pack_dir).expanduser().resolve()
    if not pack_dir.exists() or not pack_dir.is_dir():
        raise SystemExit(f"ERROR: pack-dir invalido: {pack_dir}")

    # sanity: debe tener pack.json y artifacts/
    if not (pack_dir / "pack.json").exists():
        raise SystemExit("ERROR: pack.json no existe en el pack-dir")
    if not (pack_dir / "artifacts").exists():
        raise SystemExit("ERROR: artifacts/ no existe en el pack-dir")

    out = Path(args.out).expanduser().resolve() if args.out.strip() else default_out(pack_dir)
    if out.exists():
        if args.overwrite:
            out.unlink()
        else:
            raise SystemExit(f"ERROR: zip ya existe: {out} (usa --overwrite o --out)")

    out.parent.mkdir(parents=True, exist_ok=True)

    # Zip determinista-ish: mismo orden de archivos, compresión deflate
    with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        add_dir(z, pack_dir, Path(pack_dir.name))

    print("OK: zip creado")
    print("ZIP:", str(out))
    print("BYTES:", out.stat().st_size)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
