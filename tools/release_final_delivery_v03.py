# -*- coding: utf-8 -*-
"""
Final delivery v0.3 (1 comando):

  1) RUN + EXPORT + VALIDATE + ZIP PACK
     via tools/release_pack_v03.py

  2) FINALIZE DELIVERY
     via tools/finalize_handoff_v03.py

Uso:
  python tools/release_final_delivery_v03.py `
    --v03-config config/studio_v03_text_smoke.json `
    --script "hola" `
    --overwrite `
    --auto-music `
    --music-dir .\music
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


def run(cmd: list[str], cwd: Path) -> None:
    p = subprocess.run(cmd, text=True, cwd=str(cwd))
    if p.returncode != 0:
        raise SystemExit(
            f"ERROR: comando falló (exit={p.returncode}): {' '.join(cmd)}"
        )


def run_capture(cmd: list[str], cwd: Path) -> str:
    p = subprocess.run(cmd, text=True, capture_output=True, cwd=str(cwd))
    if p.returncode != 0:
        if p.stdout:
            print(p.stdout, end="")
        if p.stderr:
            print(p.stderr, end="", file=sys.stderr)
        raise SystemExit(
            f"ERROR: comando falló (exit={p.returncode}): {' '.join(cmd)}"
        )
    if p.stdout:
        print(p.stdout, end="")
    if p.stderr:
        print(p.stderr, end="", file=sys.stderr)
    return p.stdout or ""


def parse_reported_path(stdout_text: str, key: str) -> Path | None:
    prefix = f"{key}:"
    for line in reversed(stdout_text.splitlines()):
        raw = line.strip()
        if raw.startswith(prefix):
            value = raw.split(":", 1)[1].strip()
            if value:
                return Path(value).expanduser().resolve()
    return None


def to_abs(raw: str, base: Path) -> Path:
    p = Path(raw).expanduser()
    if not p.is_absolute():
        p = base / p
    return p.resolve()


def main() -> int:
    repo_root = Path(__file__).resolve().parents[1]

    ap = argparse.ArgumentParser()
    ap.add_argument("--v03-config", required=True)
    ap.add_argument("--script", required=True)
    ap.add_argument("--overwrite", action="store_true")
    ap.add_argument("--auto-music", action="store_true")
    ap.add_argument("--music-dir", default="music")
    ap.add_argument("--python-exe", default=sys.executable)
    args = ap.parse_args()

    python_exe = str(to_abs(args.python_exe, repo_root))
    cfg = to_abs(args.v03_config, repo_root)
    if not cfg.exists():
        raise SystemExit(f"ERROR: no existe config: {cfg}")

    release_script = (repo_root / "tools" / "release_pack_v03.py").resolve()
    finalize_script = (repo_root / "tools" / "finalize_handoff_v03.py").resolve()

    if not release_script.exists():
        raise SystemExit(f"ERROR: no existe script: {release_script}")
    if not finalize_script.exists():
        raise SystemExit(f"ERROR: no existe script: {finalize_script}")

    music_dir = to_abs(args.music_dir, repo_root)
    if args.auto_music and not music_dir.exists():
        raise SystemExit(f"ERROR: no existe music-dir: {music_dir}")

    # 1) RELEASE PACK
    rel_cmd = [
        python_exe,
        str(release_script),
        "--v03-config",
        str(cfg),
        "--script",
        args.script,
    ]
    if args.overwrite:
        rel_cmd.append("--overwrite")

    rel_out = run_capture(rel_cmd, cwd=repo_root)

    manifest = parse_reported_path(rel_out, "MANIFEST")
    pack_dir = parse_reported_path(rel_out, "PACK_DIR")

    if manifest is None:
        raise SystemExit("ERROR: release_pack_v03.py no reportó MANIFEST en stdout.")
    if pack_dir is None:
        raise SystemExit("ERROR: release_pack_v03.py no reportó PACK_DIR en stdout.")
    if not manifest.exists():
        raise SystemExit(f"ERROR: MANIFEST inválido reportado por release: {manifest}")
    if not pack_dir.exists() or not pack_dir.is_dir():
        raise SystemExit(f"ERROR: PACK_DIR inválido reportado por release: {pack_dir}")

    # 2) FINALIZE DELIVERY SOBRE EL PACK
    fin_cmd = [
        python_exe,
        str(finalize_script),
        "--pack-dir",
        str(pack_dir),
        "--python-exe",
        python_exe,
        "--music-dir",
        str(music_dir),
    ]
    if args.auto_music:
        fin_cmd.append("--auto-music")

    run(fin_cmd, cwd=repo_root)

    delivery_zip = pack_dir.parent / f"{pack_dir.name}.final_delivery.zip"
    handoff_ready = pack_dir / "HANDOFF_READY.txt"
    zip_sha = delivery_zip.with_suffix(delivery_zip.suffix + ".sha256.txt")

    if not delivery_zip.exists() or delivery_zip.stat().st_size <= 0:
        raise SystemExit(f"ERROR: falta final delivery zip: {delivery_zip}")
    if not handoff_ready.exists() or handoff_ready.stat().st_size <= 0:
        raise SystemExit(f"ERROR: falta HANDOFF_READY.txt: {handoff_ready}")
    if not zip_sha.exists() or zip_sha.stat().st_size <= 0:
        raise SystemExit(f"ERROR: falta sha del zip final: {zip_sha}")

    print("")
    print("OK: final delivery completo")
    print("MANIFEST:", str(manifest))
    print("PACK_DIR:", str(pack_dir))
    print("DELIVERY_ZIP:", str(delivery_zip))
    print("DELIVERY_ZIP_SHA256:", str(zip_sha))
    print("HANDOFF_READY:", str(handoff_ready))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())