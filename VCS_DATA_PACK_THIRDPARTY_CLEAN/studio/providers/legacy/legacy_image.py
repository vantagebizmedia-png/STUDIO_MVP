# -*- coding: utf-8 -*-

from __future__ import annotations

import os
import shutil
from typing import Optional

from studio.exceptions import ProviderError
from studio.providers.image.base_image import BaseImageProvider

try:
    from app.providers.image_provider import ProviderImage as _LegacyImage
except Exception as e:
    raise ProviderError(f"No se pudo importar app.providers.image_provider.ProviderImage: {e!r}")


class LegacyImageProvider(BaseImageProvider):
    """Adapter v0.3 -> ProviderImage (legacy). Copia el resultado al output_path."""

    def __init__(self, config_path: Optional[str] = None, purpose: str = "image") -> None:
        self._inner = _LegacyImage(config_path=config_path)
        self._purpose = str(purpose or "image").strip()

    def validate(self) -> None:
        return

    def generate(self, prompt: str, output_path: str) -> str:
        prompt = str(prompt or "").strip()
        if not prompt:
            raise ValueError("prompt vacío")

        out = self._inner.generate(purpose=self._purpose, prompt=prompt)
        src = str(out.get("path") or "").strip()
        if not src:
            raise ProviderError(f"LegacyImage devolvió path vacío: {out!r}")

        os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
        if os.path.abspath(src) != os.path.abspath(output_path):
            shutil.copyfile(src, output_path)

        return output_path