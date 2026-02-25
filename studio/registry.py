# -*- coding: utf-8 -*-
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Callable, Dict

from studio.exceptions import StudioError
from studio.providers.voice.base_voice import BaseVoiceProvider
from studio.providers.image.base_image import BaseImageProvider


@dataclass(frozen=True)
class ProviderEntry:
    kind: str  # "voice" | "image"
    factory: Callable[[dict[str, Any] | None], Any]


def _demo_voice(cfg: dict[str, Any] | None) -> BaseVoiceProvider:
    from studio.providers.demo.demo_voice import DemoVoiceProvider
    return DemoVoiceProvider()


def _edge_voice(cfg: dict[str, Any] | None) -> BaseVoiceProvider:
    from studio.providers.voice.edge_voice import EdgeVoiceProvider
    cfg = cfg or {}
    return EdgeVoiceProvider(
        voice=str(cfg.get("voice", "en-US-JennyNeural")),
        rate=str(cfg.get("rate", "+0%")),
        volume=str(cfg.get("volume", "+0%")),
        sample_rate=int(cfg.get("sample_rate", 24000)),
    )


def _demo_image(cfg: dict[str, Any] | None) -> BaseImageProvider:
    from studio.providers.demo.demo_image import DemoImageProvider
    return DemoImageProvider()


def _a1111_image(cfg: dict[str, Any] | None) -> BaseImageProvider:
    from studio.providers.image.a1111_image import A1111ImageProvider
    cfg = cfg or {}
    return A1111ImageProvider(
        base_url=str(cfg.get("base_url", "http://127.0.0.1:7860")),
        timeout_s=int(cfg.get("timeout_s", 180)),
        width=int(cfg.get("width", 512)),
        height=int(cfg.get("height", 512)),
        steps=int(cfg.get("steps", 20)),
        cfg_scale=float(cfg.get("cfg_scale", 7.0)),
        sampler_name=str(cfg.get("sampler_name", "DPM++ 2M Karras")),
        seed=int(cfg.get("seed", -1)),
    )


REGISTRY: Dict[str, ProviderEntry] = {
    # VOICE
    "demo_voice": ProviderEntry(kind="voice", factory=_demo_voice),
    "edge_voice": ProviderEntry(kind="voice", factory=_edge_voice),

    # IMAGE
    "demo_image": ProviderEntry(kind="image", factory=_demo_image),
    "a1111_image": ProviderEntry(kind="image", factory=_a1111_image),
}


def build_provider(name: str, cfg: dict[str, Any] | None) -> Any:
    name = str(name or "").strip()
    if not name:
        raise StudioError("provider name vacío")
    ent = REGISTRY.get(name)
    if not ent:
        raise StudioError(f"provider no registrado: {name!r}")
    return ent.factory(cfg or {})