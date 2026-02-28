# -*- coding: utf-8 -*-
from __future__ import annotations

import os
import wave

from studio.providers.voice.base_voice import BaseVoiceProvider


class DemoVoiceProvider(BaseVoiceProvider):
    """Provider demo (no API): genera un WAV real (silencio) determinista."""

    def validate(self) -> None:
        return

    def synthesize(self, text: str, output_path: str) -> str:
        os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)

        sr = 44100
        dur_s = 1.0  # 1 segundo para smoke rápido
        nframes = int(sr * dur_s)

        with wave.open(output_path, "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)  # 16-bit PCM
            wf.setframerate(sr)
            wf.writeframes(b"\x00\x00" * nframes)

        return output_path
