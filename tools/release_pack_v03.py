# -*- coding: utf-8 -*-
"""
Release bundle v0.3 (1 comando):
  RUN (cli.main --v03-config ...) -> manifest_v03.json
  EXPORT (export_v03_pack.py) -> pack_v03_<tag>/
  VALIDATE (validate_pack.py --fix)
  ZIP (zip_pack.py) -> pack_v03_<tag>.final_delivery.zip

Uso:
  python tools/release_pack_v03.py --v03-config config/studio_v03_text_smoke.json --script "hola" --overwrite
"""
from __future__ import annotations

import argparse
import json
import sys
import subprocess
from pathlib import Path

def run(cmd: list[str]) -> None:
    p = subprocess.run(cmd, text=True)
    if p.returncode != 0:
        raise SystemExit(f"ERROR: comando falló (exit={p.returncode}): {' '.join(cmd)}")


def run_capture(cmd: list[str]) -> str:
    p = subprocess.run(cmd, text=True, capture_output=True)
    if p.stdout:
        print(p.stdout, end="")
    if p.stderr:
        print(p.stderr, end="")
    if p.returncode != 0:
        raise SystemExit(f"ERROR: comando falló (exit={p.returncode}): {' '.join(cmd)}")
    return str(p.stdout or "")

def read_json(p: Path) -> dict:
    return json.loads(p.read_text(encoding="utf-8"))

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--python-exe", default="", help="Python exe para subprocess (default: sys.executable)")
    ap.add_argument("--v03-config", required=True)
    ap.add_argument("--script", default="hola live")
    ap.add_argument("--overwrite", action="store_true")
    args = ap.parse_args()

    python_exe = (args.python_exe or sys.executable)
    cfg = Path(args.v03_config).resolve()
    if not cfg.exists():
        raise SystemExit(f"ERROR: no existe config: {cfg}")

    # 1) RUN
    run([python_exe, "-m", "cli.main", "--v03-config", str(cfg), "--script", args.script])

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
    exp_cmd = [python_exe, "tools/export_v03_pack.py", "--manifest", str(manifest)]
    if args.overwrite:
        exp_cmd.append("--overwrite")
    exp_out = run_capture(exp_cmd)

    pack_dir = None
    for line in reversed(exp_out.splitlines()):
        if line.strip().startswith("PACK_DIR:"):
            raw = line.split(":", 1)[1].strip()
            if raw:
                pack_dir = Path(raw).expanduser().resolve()
                break
    if pack_dir is None:
        raise SystemExit("ERROR: export_v03_pack.py no reportó PACK_DIR en stdout.")
    if not pack_dir.exists() or not pack_dir.is_dir():
        raise SystemExit(f"ERROR: PACK_DIR inválido reportado por export: {pack_dir}")

    # 3) VALIDATE (+fix checksums)
    run([python_exe, "tools/validate_pack.py", "--pack-dir", str(pack_dir), "--fix"])

    # 4) ZIP PACK
    zip_cmd = [python_exe, "tools/zip_pack.py", "--pack-dir", str(pack_dir)]
    if args.overwrite:
        zip_cmd.append("--overwrite")
    run(zip_cmd)

    print("\nOK: release bundle completo")
    print("MANIFEST:", str(manifest))
    print("PACK_DIR:", str(pack_dir))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())


