# -*- coding: utf-8 -*-
"""
Release bundle v0.3 (1 comando):
  RUN (cli.main --v03-config ...) -> manifest_v03.json
  EXPORT (export_v03_pack.py) -> pack_v03_<tag>/
  VALIDATE (validate_pack.py --fix)
  ZIP (zip_pack.py) -> pack_v03_<tag>_<ts>.zip

Uso:
  python tools/release_pack_v03.py --v03-config config/studio_v03_text_smoke.json --script "hola" --overwrite
"""
from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path

def run(cmd: list[str]) -> None:
    p = subprocess.run(cmd, text=True)
    if p.returncode != 0:
        raise SystemExit(f"ERROR: comando falló (exit={p.returncode}): {' '.join(cmd)}")

def read_json(p: Path) -> dict:
    return json.loads(p.read_text(encoding="utf-8"))

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--v03-config", required=True)
    ap.add_argument("--script", default="hola live")
    ap.add_argument("--overwrite", action="store_true")
    args = ap.parse_args()

    cfg = Path(args.v03_config).resolve()
    if not cfg.exists():
        raise SystemExit(f"ERROR: no existe config: {cfg}")

    # 1) RUN
    run(["python", "-m", "cli.main", "--v03-config", str(cfg), "--script", args.script])

    # Encontrar manifest en work_dir desde config (preferido) o fallback en _v03_smoke_cfg/artifacts
    cfg_obj = json.loads(cfg.read_text(encoding="utf-8-sig"))
    work_dir = Path((cfg_obj.get("work_dir") or "_v03_from_config/artifacts")).resolve()
    manifest = work_dir / "manifest_v03.json"
    if not manifest.exists():
        # fallback conocido
        fallback = Path("_v03_smoke_cfg/artifacts/manifest_v03.json").resolve()
        if fallback.exists():
            manifest = fallback
        else:
            raise SystemExit(f"ERROR: no encontré manifest_v03.json en {work_dir} ni en fallback.")

    # 2) EXPORT
    exp_cmd = ["python", "tools/export_v03_pack.py", "--manifest", str(manifest)]
    if args.overwrite:
        exp_cmd.append("--overwrite")
    run(exp_cmd)

    # Leer manifest exportado para derivar tag y ubicar pack_dir:
    m = read_json(manifest)
    cfgp = (m.get("config_path") or str(cfg)).strip()

    # Determinar exports root usando misma lógica: workspace del config
    cfg2 = json.loads(Path(cfgp).read_text(encoding="utf-8-sig"))
    ws = (cfg2.get("workspace") or "").strip()
    if ws:
        ws_p = Path(ws)
        if not ws_p.is_absolute():
            ws_p = (Path.cwd() / ws_p).resolve()
        exports_root = (ws_p / "exports").resolve()
    else:
        exports_root = (Path("workspace") / "exports").resolve()

    # Pack más reciente
    packs = sorted([p for p in exports_root.glob("pack_v03_*") if p.is_dir()], key=lambda x: x.stat().st_mtime, reverse=True)
    if not packs:
        raise SystemExit(f"ERROR: no encontré packs en {exports_root}")
    pack_dir = packs[0]

    # 3) VALIDATE (+fix checksums)
    run(["python", "tools/validate_pack.py", "--pack-dir", str(pack_dir), "--fix"])

    # 4) ZIP PACK
    zip_cmd = ["python", "tools/zip_pack.py", "--pack-dir", str(pack_dir)]
    if args.overwrite:
        zip_cmd.append("--overwrite")
    run(zip_cmd)

    print("\nOK: release bundle completo")
    print("MANIFEST:", str(manifest))
    print("PACK_DIR:", str(pack_dir))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
