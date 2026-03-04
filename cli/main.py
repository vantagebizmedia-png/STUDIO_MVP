# -*- coding: utf-8 -*-
"""CLI v0.3 (core)

Modos:
- --demo                 : demo interno (sin API)
- --legacy-demo          : legacy usando config DEMO DRY (seguro)
- --legacy               : legacy usando tu config real, PERO por defecto forzamos DRY (seguro)

Knobs Multi-Scene (deterministas):
- --multiscene           : activa Scene Builder (split de guion -> N escenas)
- --max-scenes N         : número máximo de escenas (>=1)
- --scene-split MODE     : 'auto' (default) u otros modos soportados por studio.scene_builder

Notas:
- LIVE está bloqueado por defecto. Para permitirlo: set STUDIO_ALLOW_LIVE=1
"""

from __future__ import annotations

import argparse
import os
from typing import Any


# --- LIVE guard (súper fuerte) ---
def _enforce_live_guard(force_mode: str) -> None:
    m = str(force_mode or "").upper().strip()
    if m == "LIVE":
        if os.environ.get("STUDIO_ALLOW_LIVE", "") != "1":
            raise SystemExit("LIVE bloqueado. Setea STUDIO_ALLOW_LIVE=1 para permitir LIVE.")
# --- end guard ---


def apply_pipe_knobs(pipeline: Any, *, multiscene: bool, max_scenes: int, scene_split: str) -> None:
    """Aplica knobs sin romper compat (best-effort)."""
    try:
        if multiscene:
            setattr(pipeline, "multiscene", True)
        if int(max_scenes or 1) < 1:
            max_scenes = 1
        setattr(pipeline, "max_scenes", int(max_scenes or 1))
        if scene_split:
            setattr(pipeline, "scene_split", str(scene_split or "auto"))
    except Exception:
        return


from studio.builders import (
    build_pipeline,
    detect_providers_json,
    force_mode_copy,
    write_demo_providers_json,
)


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="studio", description="STUDIO v0.3 (core stable)")
    g = p.add_mutually_exclusive_group(required=False)
    g.add_argument("--demo", action="store_true", help="Genera demo (sin API)")
    g.add_argument("--legacy-demo", action="store_true", help="Legacy con providers_demo.json (DRY seguro)")
    g.add_argument("--legacy", action="store_true", help="Legacy con tu providers.json (forzando DRY por defecto)")

    p.add_argument("--script", default="demo", help="Texto base")
    p.add_argument("--work-dir", default="", help="Dir de salida (si vacío, usa defaults por modo)")
    p.add_argument("--workspace", default="", help="STUDIO_WORKSPACE (cache aislado)")

    p.add_argument("--providers-json", default="", help="Ruta a providers.json (legacy)")
    p.add_argument("--force-mode", default="DRY", help="DRY|REPLAY|LIVE (legacy). Default: DRY")

    p.add_argument("--v03-config", default="", help="Ruta a config v0.3 JSON (provider swapping nativo)")

    # --- Multi-Scene knobs (P1) ---
    p.add_argument("--multiscene", action="store_true", help="Activa split a escenas + assets por escena")
    p.add_argument("--max-scenes", dest="max_scenes", type=int, default=1, help="Máximo de escenas (>=1)")
    p.add_argument("--scene-split", dest="scene_split", default="auto", help="Modo split (default: auto)")
    # ------------------------------

    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    # 1) v03 config-based pipeline
    if args.v03_config:
        from studio.builders import build_pipeline_from_v03_config

        pipe = build_pipeline_from_v03_config(args.v03_config)
        apply_pipe_knobs(pipe, multiscene=bool(args.multiscene), max_scenes=int(args.max_scenes), scene_split=str(args.scene_split))
        img, aud = pipe.run(args.script)

        print("OK v0.3 config")
        print(f"image: {img}")
        print(f"audio: {aud}")
        print(f"config: {os.path.abspath(args.v03_config)}")
        return 0

    # 2) demo
    if args.demo:
        work = os.path.abspath(args.work_dir or "_demo_out")
        pipe = build_pipeline(mode="demo", work_dir=work)
        apply_pipe_knobs(pipe, multiscene=bool(args.multiscene), max_scenes=int(args.max_scenes), scene_split=str(args.scene_split))
        img, aud = pipe.run(args.script)
        print("OK demo")
        print(f"image: {img}")
        print(f"audio: {aud}")
        return 0

    # 3) legacy-demo (DRY)
    if args.legacy_demo:
        root = os.path.abspath("_demo_out_legacy")
        ws = os.path.abspath(args.workspace or os.path.join(root, "workspace"))
        cfg = os.path.join(root, "providers_demo.json")
        if not os.path.exists(cfg):
            write_demo_providers_json(cfg)

        work = os.path.abspath(args.work_dir or os.path.join(root, "artifacts"))
        pipe = build_pipeline(mode="legacy", work_dir=work, providers_json=cfg, workspace=ws)
        apply_pipe_knobs(pipe, multiscene=bool(args.multiscene), max_scenes=int(args.max_scenes), scene_split=str(args.scene_split))
        img, aud = pipe.run(args.script)
        print("OK legacy-demo (DRY)")
        print(f"image: {img}")
        print(f"audio: {aud}")
        print(f"STUDIO_WORKSPACE: {ws}")
        print(f"providers_demo.json: {cfg}")
        return 0

    # 4) legacy (tu config real)
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
        apply_pipe_knobs(pipe, multiscene=bool(args.multiscene), max_scenes=int(args.max_scenes), scene_split=str(args.scene_split))
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
