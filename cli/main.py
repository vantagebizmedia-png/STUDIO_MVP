# -*- coding: utf-8 -*-
"""CLI v0.3 (core)

Modos:
- --demo
- --legacy-demo
- --legacy
- --v03-config

Regla importante:
- Si usas --v03-config y NO pasas knobs por CLI, se leen desde el JSON:
  pipe.multiscene / pipe.max_scenes / pipe.scene_split
"""

from __future__ import annotations

import argparse
import json
import os
from typing import Any


def _enforce_live_guard(force_mode: str) -> None:
    m = str(force_mode or "").upper().strip()
    if m == "LIVE":
        if os.environ.get("STUDIO_ALLOW_LIVE", "") != "1":
            raise SystemExit("LIVE bloqueado. Setea STUDIO_ALLOW_LIVE=1 para permitir LIVE.")


def _load_v03_pipe_defaults(config_path: str) -> dict[str, Any]:
    try:
        with open(config_path, "r", encoding="utf-8-sig") as f:
            obj = json.load(f)

        if not isinstance(obj, dict):
            return {}

        pipe_cfg = obj.get("pipe") or {}
        if isinstance(pipe_cfg, dict) and pipe_cfg:
            return {
                k: pipe_cfg.get(k)
                for k in ("multiscene", "max_scenes", "scene_split")
                if k in pipe_cfg
            }

        # Compat: configs viejos con knobs al nivel raíz
        return {
            k: obj.get(k)
            for k in ("multiscene", "max_scenes", "scene_split")
            if k in obj
        }
    except Exception:
        return {}

def apply_pipe_knobs(
    pipeline: Any,
    *,
    multiscene: bool,
    max_scenes: int,
    scene_split: str,
) -> None:
    try:
        setattr(pipeline, "multiscene", bool(multiscene))
        if int(max_scenes or 1) < 1:
            max_scenes = 1
        setattr(pipeline, "max_scenes", int(max_scenes or 1))
        setattr(pipeline, "scene_split", str(scene_split or "auto"))
    except Exception:
        return


from studio.builders import (
    build_pipeline,
    build_pipeline_from_v03_config,
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

    p.add_argument("--multiscene", action="store_true", help="Activa split a escenas + assets por escena")
    p.add_argument("--max-scenes", dest="max_scenes", type=int, default=0, help="Máximo de escenas (0 = usar config)")
    p.add_argument("--scene-split", dest="scene_split", default="", help="Modo split (vacío = usar config)")

    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    if args.v03_config:
        pipe_defaults = _load_v03_pipe_defaults(args.v03_config)

        multiscene = bool(args.multiscene)
        if not multiscene:
            multiscene = bool(pipe_defaults.get("multiscene", False))

        max_scenes = int(args.max_scenes or 0)
        if max_scenes <= 0:
            max_scenes = int(pipe_defaults.get("max_scenes", 1) or 1)

        scene_split = str(args.scene_split or "").strip()
        if not scene_split:
            scene_split = str(pipe_defaults.get("scene_split", "auto") or "auto")

        pipe = build_pipeline_from_v03_config(args.v03_config)
        apply_pipe_knobs(
            pipe,
            multiscene=multiscene,
            max_scenes=max_scenes,
            scene_split=scene_split,
        )

        img, aud = pipe.run(args.script)

        print("OK v0.3 config")
        print(f"image: {img}")
        print(f"audio: {aud}")
        print(f"config: {os.path.abspath(args.v03_config)}")
        print(f"multiscene: {multiscene}")
        print(f"max_scenes: {max_scenes}")
        print(f"scene_split: {scene_split}")
        return 0

    if args.demo:
        work = os.path.abspath(args.work_dir or "_demo_out")
        pipe = build_pipeline(mode="demo", work_dir=work)
        apply_pipe_knobs(
            pipe,
            multiscene=bool(args.multiscene),
            max_scenes=int(args.max_scenes or 1),
            scene_split=str(args.scene_split or "auto"),
        )
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
        apply_pipe_knobs(
            pipe,
            multiscene=bool(args.multiscene),
            max_scenes=int(args.max_scenes or 1),
            scene_split=str(args.scene_split or "auto"),
        )
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
        apply_pipe_knobs(
            pipe,
            multiscene=bool(args.multiscene),
            max_scenes=int(args.max_scenes or 1),
            scene_split=str(args.scene_split or "auto"),
        )
        img, aud = pipe.run(args.script)
        print(f"OK legacy (force-mode={args.force_mode})")
        print(f"image: {img}")
        print(f"audio: {aud}")
        print(f"STUDIO_WORKSPACE: {ws}")
        print(f"providers_forced.json: {forced}")
        print(f"source providers.json: {src}")
        return 0

    print("Nada que hacer. Usa --demo o --legacy-demo o --legacy o --v03-config")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
