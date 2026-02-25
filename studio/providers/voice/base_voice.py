# -*- coding: utf-8 -*-

from __future__ import annotations

from studio.providers.base import BaseProvider


class BaseVoiceProvider(BaseProvider):
    """Interfaz para providers de voz/TTS."""

    def synthesize(self, text: str, output_path: str) -> str:
        """Genera audio desde texto y retorna la ruta final."""
        raise NotImplementedError