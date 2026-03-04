# -*- coding: utf-8 -*-

from __future__ import annotations

import os
import shutil
from typing import Optional

from studio.exceptions import ProviderError
from studio.providers.voice.base_voice import BaseVoiceProvider

try:
    from app.providers.voice_provider import ProviderVoice as _LegacyVoice
except Exception as e:
    raise ProviderError(f"No se pudo importar app.providers.voice_provider.ProviderVoice: {e!r}")


class LegacyVoiceProvider(BaseVoiceProvider):
    """Adapter v0.3 -> ProviderVoice (legacy). Copia el resultado al output_path."""

    def __init__(self, config_path: Optional[str] = None, purpose: str = "voice") -> None:
        self._inner = _LegacyVoice(config_path=config_path)
        self._purpose = str(purpose or "voice").strip()

    def validate(self) -> None:
        # El legacy valida en __init__ leyendo providers.json
        return

    def synthesize(self, text: str, output_path: str) -> str:
        text = str(text or "").strip()
        if not text:
            raise ValueError("text vacío")

        out = self._inner.speak(purpose=self._purpose, text=text)
        src = str(out.get("path") or "").strip()
        if not src:
            raise ProviderError(f"LegacyVoice devolvió path vacío: {out!r}")

        os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
        if os.path.abspath(src) != os.path.abspath(output_path):
            shutil.copyfile(src, output_path)

        return output_path