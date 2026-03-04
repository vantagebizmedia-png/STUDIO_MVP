# -*- coding: utf-8 -*-
from __future__ import annotations

import base64
import os

from studio.providers.image.base_image import BaseImageProvider

# PNG 1x1 transparente válido
_PNG_1X1 = base64.b64decode(
    b"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+X2dAAAAAASUVORK5CYII="
)

class DemoImageProvider(BaseImageProvider):
    def validate(self) -> None:
        return

    def generate(self, prompt: str, output_path: str) -> str:
        os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
        with open(output_path, "wb") as f:
            f.write(_PNG_1X1)
        return output_path
