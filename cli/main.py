from pathlib import Path
import json
# -*- coding: utf-8 -*-
"""CLI v0.3

Modos:
- --demo                 : demo interno (sin API)
- --legacy-demo          : legacy usando config DEMO DRY (seguro)
- --legacy               : legacy usando tu config real, PERO por defecto forzamos DRY (seguro)
    * --providers-json X : ruta a providers.json (si no, intenta detectar config/providers.json)
    * --force-mode DRY|REPLAY|LIVE : por defecto DRY (LIVE solo si lo pides explícito)
    * --workspace PATH   : fija STUDIO_WORKSPACE
"""

from __future__ import annotations

import argparse
import os

# --- LIVE guard (súper fuerte) ---
def _enforce_live_guard(force_mode: str) -> None:
    m = str(force_mode or "").upper().strip()
    if m == "LIVE":
        if os.environ.get("STUDIO_ALLOW_LIVE", "") != "1":
            raise SystemExit("LIVE bloqueado. Setea STUDIO_ALLOW_LIVE=1 para permitir LIVE.")
# --- end guard ---


from studio.builders import (
    build_pipeline,
    detect_providers_json,
    force_mode_copy,
    write_demo_providers_json,
)


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="studio", description="STUDIO v0.3 (core stable)")
    g = p.add_mutually_exclusive_group(required=False)
    g.add_argument("--demo", action="store_true", help="Genera 1 imagen+audio demo en ./_demo_out")
    g.add_argument("--legacy-demo", action="store_true", help="Usa legacy con providers_demo.json (DRY seguro)")
    g.add_argument("--legacy", action="store_true", help="Usa legacy con tu providers.json (forzando DRY por defecto)")

    p.add_argument("--script", default="demo", help="Texto base")
    p.add_argument("--work-dir", default="", help="Dir de salida (si vacío, usa defaults por modo)")
    p.add_argument("--workspace", default="", help="STUDIO_WORKSPACE (cache aislado)")

    p.add_argument("--providers-json", default="", help="Ruta a providers.json (legacy)")
    p.add_argument("--force-mode", default="DRY", help="DRY|REPLAY|LIVE (legacy). Default: DRY")

    p.add_argument("--v03-config", default="", help="Ruta a config v0.3 JSON (provider swapping nativo)")

    return p
def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    if args.v03_config:
        from studio.builders import build_pipeline_from_v03_config

        pipe = build_pipeline_from_v03_config(args.v03_config)
        img, aud = pipe.run(args.script)

        print("OK v0.3 config")

    # F1.2: escribir manifest mínimo (bridge v0.3)
    try:
        # Detecta work_dir de forma segura
        wd = None
        try:
            wd = getattr(pipeline, "work_dir", None)
        except Exception:
            wd = None
        work_dir = str(wd) if wd else "_v03_from_config/artifacts"
        work_dir = str(Path(work_dir).resolve())

        # Buscar artifacts recientes (fallback si no tenemos variables img/aud)
        script_files = sorted(Path(work_dir).glob("script_*.txt"), key=lambda x: x.stat().st_mtime, reverse=True)
        img_files    = sorted(Path(work_dir).glob("image_*.png"),  key=lambda x: x.stat().st_mtime, reverse=True)
        aud_files    = sorted(Path(work_dir).glob("audio_*.wav"),  key=lambda x: x.stat().st_mtime, reverse=True)

        manifest = {
            "version": "v0.3",
            "mode": "RUN",
            "work_dir": work_dir,
            "config_path": str(Path(args.v03_config).resolve()),
            "artifacts": {
                "script": str(script_files[0].resolve()) if script_files else "",
                "image":  str(img_files[0].resolve()) if img_files else "",
                "audio":  str(aud_files[0].resolve()) if aud_files else "",
            },
        }
        Path(work_dir, "manifest_v03.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    except Exception:
        pass

        print(f"image: {img}")
        print(f"audio: {aud}")
        print(f"config: {os.path.abspath(args.v03_config)}")
        return 0

    if args.demo:
        work = os.path.abspath(args.work_dir or "_demo_out")
        pipe = build_pipeline(mode="demo", work_dir=work)
        img, aud = pipe.run(args.script)
        print("OK demo")
        print(f"image: {img}")
        print(f"audio: {aud}")
        return 0

    if args.legacy_demo:
        root = os.path.abspath("_demo_out_legacy")
        ws = os.path.abspath(args.workspace or os.path.join(root, "workspace"))
        cfg = os.path.join(root, "providers_demo.json")
        if not os.path.exists(cfg):
            write_demo_providers_json(cfg)

        work = os.path.abspath(args.work_dir or os.path.join(root, "artifacts"))
        pipe = build_pipeline(mode="legacy", work_dir=work, providers_json=cfg, workspace=ws)
        img, aud = pipe.run(args.script)
        print("OK legacy-demo (DRY)")
        print(f"image: {img}")
        print(f"audio: {aud}")
        print(f"STUDIO_WORKSPACE: {ws}")
        print(f"providers_demo.json: {cfg}")
        return 0

    if args.legacy:
        root = os.path.abspath("_v03_legacy_run")
        os.makedirs(root, exist_ok=True)

        ws = os.path.abspath(args.workspace or os.path.join(root, "workspace"))
        work = os.path.abspath(args.work_dir or os.path.join(root, "artifacts"))

        src = args.providers_json.strip() or (detect_providers_json() or "")
        if not src:
            print("ERROR: no se encontró providers.json. Usa --providers-json .\\config\\providers.json")
            return 2

        forced = os.path.join(root, "providers_forced.json")
        _enforce_live_guard(args.force_mode)
        force_mode_copy(src, forced, args.force_mode)

        pipe = build_pipeline(mode="legacy", work_dir=work, providers_json=forced, workspace=ws)
        img, aud = pipe.run(args.script)
        print(f"OK legacy (force-mode={args.force_mode})")
        print(f"image: {img}")
        print(f"audio: {aud}")
        print(f"STUDIO_WORKSPACE: {ws}")
        print(f"providers_forced.json: {forced}")
        print(f"source providers.json: {src}")
        return 0

    print("Nada que hacer. Usa --demo o --legacy-demo o --legacy")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())