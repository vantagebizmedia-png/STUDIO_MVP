# -*- coding: utf-8 -*-
"""Provider de texto DRY — para tests sin coste de API."""

from __future__ import annotations

from studio.providers.text.base_text import BaseTextProvider


class DemoTextProvider(BaseTextProvider):
    """Provider de texto offline para tests y modo DRY.

    No llama ninguna API. Devuelve un texto determinista basado en el prompt,
    útil para validar el pipeline sin gastar créditos.

    Example::

        provider = DemoTextProvider()
        provider.validate()
        text = provider.generate("Consejos de productividad")
        # Retorna un texto de demostración
    """

    _DEMO_SCRIPT = (
        "Hoy te compartiré tres ideas poderosas. "
        "La primera: la consistencia supera al talento. "
        "La segunda: cada pequeño paso cuenta. "
        "La tercera: el progreso, no la perfección. "
        "Empieza hoy, un paso a la vez."
    )

    def validate(self) -> None:
        """DemoTextProvider no requiere dependencias externas."""
        pass

    def generate(self, prompt: str, system: str = "") -> str:
        """Genera un script de demostración estático.

        Args:
            prompt: Ignorado en modo demo.
            system: Ignorado en modo demo.

        Returns:
            Script de demostración fijo para pruebas.
        """
        prompt = str(prompt or "").strip()
        if not prompt:
            raise ValueError("prompt vacío")
        return f"[DEMO sobre: {prompt[:60]}]\n\n{self._DEMO_SCRIPT}"
