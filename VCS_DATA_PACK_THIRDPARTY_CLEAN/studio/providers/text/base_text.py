# -*- coding: utf-8 -*-
"""Interfaz base para providers de texto/LLM."""

from __future__ import annotations

from studio.providers.base import BaseProvider


class BaseTextProvider(BaseProvider):
    """Interfaz para providers de generación de texto con LLMs.

    Un text provider encapsula el acceso a un modelo de lenguaje
    (API remota o local) y expone una interfaz uniforme.

    Example::

        class MyProvider(BaseTextProvider):
            def validate(self) -> None:
                if not os.environ.get("MY_API_KEY"):
                    raise ProviderError("Falta MY_API_KEY")

            def generate(self, prompt: str, system: str = "") -> str:
                return call_my_api(prompt, system)
    """

    def generate(self, prompt: str, system: str = "") -> str:
        """Genera texto a partir de un prompt.

        Args:
            prompt: Prompt del usuario / instrucción de generación.
            system: Prompt de sistema opcional (define el rol o estilo del modelo).

        Returns:
            Texto generado como string.

        Raises:
            ValueError: Si prompt está vacío.
            ProviderError: Si el modelo falla o no está disponible.
        """
        raise NotImplementedError
