# -*- coding: utf-8 -*-

from __future__ import annotations
import os
from studio.providers.image.base_image import BaseImageProvider

class DemoImageProvider(BaseImageProvider):
    """Provider demo (no API): escribe un header PNG válido."""

    def validate(self) -> None:
        return

    def generate(self, prompt: str, output_path: str) -> str:
        os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
        with open(output_path, "wb") as f:
            f.write(b"\x89PNG\r\n\x1a\n")
        return output_path