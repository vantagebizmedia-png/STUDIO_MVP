# -*- coding: utf-8 -*-
"""Pipeline puro (sin prints, sin CLI)."""

from __future__ import annotations

import hashlib
import os
from dataclasses import dataclass

from studio.providers.voice.base_voice import BaseVoiceProvider
from studio.providers.image.base_image import BaseImageProvider


def _sha8(text: str) -> str:
    h = hashlib.sha256(text.encode("utf-8")).hexdigest()
    return h[:8]


@dataclass
class StudioPipeline:
    voice: BaseVoiceProvider
    image: BaseImageProvider
    work_dir: str = "."

    def run(self, script: str) -> tuple[str, str]:
        """Ejecuta generación mínima: 1 imagen + 1 audio."""

        os.makedirs(self.work_dir, exist_ok=True)
        tag = _sha8(script)

        image_path = os.path.join(self.work_dir, f"image_{tag}.png")
        audio_path = os.path.join(self.work_dir, f"audio_{tag}.wav")

        img = self.image.generate(script, image_path)
        aud = self.voice.synthesize(script, audio_path)

        return img, aud