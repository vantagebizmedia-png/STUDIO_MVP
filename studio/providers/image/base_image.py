# -*- coding: utf-8 -*-

from __future__ import annotations

from studio.providers.base import BaseProvider


class BaseImageProvider(BaseProvider):
    """Interfaz para providers de imagen."""

    def generate(self, prompt: str, output_path: str) -> str:
        """Genera imagen desde prompt y retorna la ruta final."""
        raise NotImplementedError