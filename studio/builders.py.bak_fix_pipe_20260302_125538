# -*- coding: utf-8 -*-
"""Builders (factory) para construir pipelines sin ensuciar core/pipeline.

- demo   : providers internos (sin API)
- legacy : usa app/providers vía adapters (puede ser DRY/REPLAY/LIVE según config)
"""

from __future__ import annotations

import json
import os
from typing import Optional

from studio.pipeline import StudioPipeline
from studio.exceptions import StudioError


def detect_project_root(start: Optional[str] = None) -> str:
    """Sube carpetas hasta encontrar run.py; si no, usa cwd."""
    cur = os.path.abspath(start or os.getcwd())
    while True:
        if os.path.exists(os.path.join(cur, "run.py")):
            return cur
        parent = os.path.dirname(cur)
        if parent == cur:
            return os.path.abspath(os.getcwd())
        cur = parent


def detect_providers_json(project_root: Optional[str] = None) -> Optional[str]:
    root = os.path.abspath(project_root or detect_project_root())
    p = os.path.join(root, "config", "providers.json")
    return p if os.path.exists(p) else None


def write_demo_providers_json(path: str) -> None:
    """Config DRY segura para usar con legacy providers sin tocar tu config real."""
    obj = {
        "voice": {
            "mode": "DRY",
            "active_provider": "demo_tts",
            "default_params": {"format": "wav"},
            "cache": {"dir": "workspace/cache/voice", "policy": "prefer", "replay_strict": True, "salt": ""}
        },
        "image": {
            "mode": "DRY",
            "active_provider": "demo_img",
            "default_params": {},
            "cache": {"dir": "workspace/cache/images", "policy": "prefer", "replay_strict": True, "salt": ""}
        },
        "providers": {
            "demo_tts": {
                "type": "http_binary",
                "url": "http://127.0.0.1/dry_tts",
                "method": "POST",
                "timeout_s": 5,
                "model": "none",
                "headers": {},
                "body": {},
                "fingerprint_fields": ["type", "url", "model"]
            },
            "demo_img": {
                "type": "http_json",
                "url": "http://127.0.0.1/dry_img",
                "method": "POST",
                "timeout_s": 5,
                "model": "none",
                "headers": {},
                "body": {},
                "extract_paths": ["data.0.b64_json"],
                "fingerprint_fields": ["type", "url", "model"]
            }
        }
    }
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)


def force_mode_copy(src_json: str, dst_json: str, mode: str) -> str:
    """Crea copia de providers.json forzando voice.mode e image.mode."""
    mode = str(mode or "").upper().strip()
    if mode not in ("DRY", "REPLAY", "LIVE"):
        raise ValueError("mode debe ser DRY|REPLAY|LIVE")

    with open(src_json, "r", encoding="utf-8") as f:
        obj = json.load(f)

    obj.setdefault("voice", {})
    obj.setdefault("image", {})
    obj["voice"]["mode"] = mode
    obj["image"]["mode"] = mode

    os.makedirs(os.path.dirname(dst_json) or ".", exist_ok=True)
    with open(dst_json, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)

    return dst_json


def build_demo_pipeline(*, work_dir: str) -> StudioPipeline:
    from studio.providers.demo.demo_voice import DemoVoiceProvider
    from studio.providers.demo.demo_image import DemoImageProvider
    return StudioPipeline(voice=DemoVoiceProvider(), image=DemoImageProvider(), work_dir=work_dir)


def build_legacy_pipeline(*, work_dir: str, providers_json: str, workspace: Optional[str] = None) -> StudioPipeline:
    if workspace:
        os.environ["STUDIO_WORKSPACE"] = os.path.abspath(workspace)

    from studio.providers.legacy.legacy_voice import LegacyVoiceProvider
    from studio.providers.legacy.legacy_image import LegacyImageProvider

    return StudioPipeline(
        voice=LegacyVoiceProvider(config_path=providers_json),
        image=LegacyImageProvider(config_path=providers_json),
        work_dir=work_dir,
    )


def build_pipeline(
    *,
    mode: str,
    work_dir: str,
    providers_json: Optional[str] = None,
    workspace: Optional[str] = None,
) -> StudioPipeline:
    mode = str(mode or "").lower().strip()
    if mode == "demo":
        return build_demo_pipeline(work_dir=work_dir)
    if mode == "legacy":
        if not providers_json:
            raise StudioError("mode=legacy requiere providers_json (o detéctalo con detect_providers_json).")
        return build_legacy_pipeline(work_dir=work_dir, providers_json=providers_json, workspace=workspace)
    raise StudioError(f"mode inválido: {mode!r}")
# =========================
# v0.3 config-based builder
# =========================
def build_pipeline_from_v03_config(config_path: str) -> StudioPipeline:
    """Construye pipeline desde config JSON v0.3 (providers via registry).

    Soporta:
      - voice.provider + voice.config
      - image.provider + image.config
      - text.provider  + text.config (opcional)  <-- F1.1
    """
    from studio.registry import build_provider

    config_path = os.path.abspath(config_path)
    with open(config_path, "r", encoding="utf-8-sig") as f:
        obj = json.load(f)

    work_dir = os.path.abspath(obj.get("work_dir") or "_v03_from_config/artifacts")
    workspace = obj.get("workspace") or ""
    if workspace:
        os.environ["STUDIO_WORKSPACE"] = os.path.abspath(workspace)

    v = obj.get("voice") or {}
    i = obj.get("image") or {}
    t = obj.get("text") or {}

    voice = build_provider(v.get("provider", ""), v.get("config") or {})
    image = build_provider(i.get("provider", ""), i.get("config") or {})

    text = None
    tname = str(t.get("provider", "") or "").strip()
    if tname:
        text = build_provider(tname, t.get("config") or {})

    for p in (voice, image, text):
        if p is not None and hasattr(p, "validate"):
            p.validate()

    # F1.2: metadata para manifest
    try:
        setattr(voice, "_provider_name", v.get("provider", ""))
        setattr(image, "_provider_name", i.get("provider", ""))
        if text is not None:
            setattr(text, "_provider_name", tname)
    except Exception:
        pass
    pipe = StudioPipeline(voice=voice, image=image, text=text, work_dir=work_dir)

    # HOTFIX: knobs multiscene desde config v0.3
    try:
        setattr(pipe, "_v03_config_path", config_path)
        setattr(pipe, "multiscene", bool(obj.get("multiscene", False)))
        setattr(pipe, "max_scenes", int(obj.get("max_scenes", 1) or 1))
        setattr(pipe, "scene_split", str(obj.get("scene_split", "auto") or "auto"))
    except Exception:
        pass
    try:
        setattr(pipe, "_v03_config_path", config_path)
    except Exception:
        pass
    return pipe


    from studio.registry import build_provider

    config_path = os.path.abspath(config_path)
    with open(config_path, "r", encoding="utf-8-sig") as f:
        obj = json.load(f)

    work_dir = os.path.abspath(obj.get("work_dir") or "_v03_from_config/artifacts")
    workspace = obj.get("workspace") or ""
    if workspace:
        os.environ["STUDIO_WORKSPACE"] = os.path.abspath(workspace)

    v = obj.get("voice") or {}
    i = obj.get("image") or {}

    voice = build_provider(v.get("provider", ""), v.get("config") or {})
    image = build_provider(i.get("provider", ""), i.get("config") or {})

    if hasattr(voice, "validate"):
        voice.validate()
    if hasattr(image, "validate"):
        image.validate()

    return StudioPipeline(voice=voice, image=image, work_dir=work_dir)
