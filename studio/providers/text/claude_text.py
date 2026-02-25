# -*- coding: utf-8 -*-
"""Provider de texto usando Anthropic Claude API."""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request

from studio.exceptions import ProviderError
from studio.providers.text.base_text import BaseTextProvider


class ClaudeTextProvider(BaseTextProvider):
    """Generación de texto usando Anthropic Claude Messages API.

    Compatible con los modelos Claude (claude-haiku-4-5-20251001,
    claude-sonnet-4-6, claude-opus-4-6, etc.).

    Attributes:
        model: Nombre del modelo Anthropic.
        api_key_env: Variable de entorno con la API key de Anthropic.
        max_tokens: Máximo de tokens en la respuesta.
        temperature: Temperatura de sampling (0.0 = determinista, 1.0 = creativo).
        system: Prompt de sistema por defecto.

    Example::

        provider = ClaudeTextProvider(
            model="claude-haiku-4-5-20251001",
            system="Eres un experto en crear guiones virales para reels.",
        )
        provider.validate()
        script = provider.generate("5 hábitos de las personas exitosas")
    """

    _API_URL = "https://api.anthropic.com/v1/messages"
    _API_VERSION = "2023-06-01"

    def __init__(
        self,
        model: str = "claude-haiku-4-5-20251001",
        api_key_env: str = "ANTHROPIC_API_KEY",
        max_tokens: int = 1024,
        temperature: float = 0.7,
        system: str = "",
        timeout_s: int = 60,
    ) -> None:
        self.model = str(model).strip()
        self.api_key_env = str(api_key_env).strip()
        self.max_tokens = int(max_tokens)
        self.temperature = float(temperature)
        self.system = str(system or "").strip()
        self.timeout_s = int(timeout_s)

    def validate(self) -> None:
        """Verifica que la API key de Anthropic está disponible.

        Raises:
            ProviderError: Si la variable de entorno de la API key está vacía.
        """
        key = os.environ.get(self.api_key_env, "").strip()
        if not key:
            raise ProviderError(
                f"ClaudeTextProvider requiere {self.api_key_env}=<tu_api_key> "
                "en variables de entorno. Obtenla en: https://console.anthropic.com"
            )

    def generate(self, prompt: str, system: str = "") -> str:
        """Genera texto usando Anthropic Claude Messages API.

        Args:
            prompt: Mensaje del usuario.
            system: Prompt de sistema. Si está vacío, usa el configurado en __init__.

        Returns:
            Texto generado por Claude.

        Raises:
            ValueError: Si prompt está vacío.
            ProviderError: Si la API key es inválida o la llamada falla.
        """
        prompt = str(prompt or "").strip()
        if not prompt:
            raise ValueError("prompt vacío")

        api_key = os.environ.get(self.api_key_env, "").strip()
        if not api_key:
            raise ProviderError(f"Falta {self.api_key_env}. Setea la variable de entorno.")

        effective_system = str(system or self.system or "").strip()

        payload = {
            "model": self.model,
            "max_tokens": self.max_tokens,
            "temperature": self.temperature,
            "messages": [{"role": "user", "content": prompt}],
        }
        if effective_system:
            payload["system"] = effective_system

        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        req = urllib.request.Request(self._API_URL, data=data, method="POST")
        req.add_header("Content-Type", "application/json")
        req.add_header("x-api-key", api_key)
        req.add_header("anthropic-version", self._API_VERSION)

        try:
            with urllib.request.urlopen(req, timeout=self.timeout_s) as resp:
                raw = resp.read()
        except urllib.error.HTTPError as e:
            msg = e.read().decode("utf-8", errors="replace")[:400]
            raise ProviderError(f"Anthropic HTTPError {e.code}: {msg}") from e
        except Exception as e:
            raise ProviderError(f"Anthropic request falló: {e!r}") from e

        try:
            obj = json.loads(raw.decode("utf-8", errors="replace"))
        except Exception as e:
            raise ProviderError("Anthropic devolvió respuesta no-JSON.") from e

        try:
            return str(obj["content"][0]["text"]).strip()
        except (KeyError, IndexError, TypeError) as e:
            raise ProviderError(f"Anthropic respuesta inesperada: {obj!r}") from e
