# -*- coding: utf-8 -*-

from __future__ import annotations
import os
from studio.providers.voice.base_voice import BaseVoiceProvider

class DemoVoiceProvider(BaseVoiceProvider):
    """Provider demo (no API): escribe bytes dummy."""

    def validate(self) -> None:
        return

    def synthesize(self, text: str, output_path: str) -> str:
        os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
        with open(output_path, "wb") as f:
            f.write(b"STUDIO_DEMO_WAV")
        return output_path