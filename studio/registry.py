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


def _hf_image(cfg: dict[str, Any] | None) -> BaseImageProvider:
    from studio.providers.image.hf_image import HFImageProvider
    cfg = cfg or {}
    return HFImageProvider(
        model=str(cfg.get("model", "black-forest-labs/FLUX.1-schnell")),
        provider=str(cfg.get("provider", "hf-inference")),
        token_env=str(cfg.get("token_env", "HF_TOKEN")),
    )


def _pixabay_image(cfg: dict[str, Any] | None) -> BaseImageProvider:
    from studio.providers.image.pixabay_image import PixabayImageProvider
    cfg = cfg or {}
    return PixabayImageProvider(
        api_key_env=str(cfg.get("api_key_env", "PIXABAY_API_KEY")),
        timeout_s=int(cfg.get("timeout_s", 10)),
        replay_strict=bool(cfg.get("replay_strict", False)),
        cache_enabled=bool(cfg.get("cache_enabled", True)),
    )

def _demo_text(cfg: dict[str, Any] | None) -> Any:
    from studio.providers.text.demo_text import DemoTextProvider
    return DemoTextProvider()


def _openai_text(cfg: dict[str, Any] | None) -> Any:
    from studio.providers.text.openai_text import OpenAITextProvider
    cfg = cfg or {}
    return OpenAITextProvider(
        model=str(cfg.get("model", "gpt-4o-mini")),
        api_key_env=str(cfg.get("api_key_env", "OPENAI_API_KEY")),
        max_tokens=int(cfg.get("max_tokens", 1024)),
        temperature=float(cfg.get("temperature", 0.7)),
        system=str(cfg.get("system", "")),
    )


def _claude_text(cfg: dict[str, Any] | None) -> Any:
    from studio.providers.text.claude_text import ClaudeTextProvider
    cfg = cfg or {}
    return ClaudeTextProvider(
        model=str(cfg.get("model", "claude-haiku-4-5-20251001")),
        api_key_env=str(cfg.get("api_key_env", "ANTHROPIC_API_KEY")),
        max_tokens=int(cfg.get("max_tokens", 1024)),
        temperature=float(cfg.get("temperature", 0.7)),
        system=str(cfg.get("system", "")),
    )


REGISTRY: Dict[str, ProviderEntry] = {
    # VOICE
    "demo_voice": ProviderEntry(kind="voice", factory=_demo_voice),
    "edge_voice": ProviderEntry(kind="voice", factory=_edge_voice),

    # IMAGE
    "demo_image":  ProviderEntry(kind="image", factory=_demo_image),
    "a1111_image": ProviderEntry(kind="image", factory=_a1111_image),
    "hf_image":    ProviderEntry(kind="image", factory=_hf_image),

    "pixabay_image": ProviderEntry(kind="image", factory=_pixabay_image),
    # TEXT
    "demo_text":   ProviderEntry(kind="text", factory=_demo_text),
    "openai_text": ProviderEntry(kind="text", factory=_openai_text),
    "claude_text": ProviderEntry(kind="text", factory=_claude_text),
}


def build_provider(name: str, cfg: dict[str, Any] | None) -> Any:
    name = str(name or "").strip()
    if not name:
        raise StudioError("provider name vacío")
    ent = REGISTRY.get(name)
    if not ent:
        raise StudioError(f"provider no registrado: {name!r}")
    return ent.factory(cfg or {})