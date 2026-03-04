# -*- coding: utf-8 -*-
"""Provider de texto usando OpenAI API (gpt-4o-mini, gpt-4o, etc.)."""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request

from studio.exceptions import ProviderError
from studio.providers.text.base_text import BaseTextProvider


class OpenAITextProvider(BaseTextProvider):
    """Generación de texto usando OpenAI Chat Completions API.

    Compatible con cualquier modelo de la familia GPT (gpt-4o-mini,
    gpt-4o, gpt-3.5-turbo, etc.).

    Attributes:
        model: Nombre del modelo OpenAI.
        api_key_env: Variable de entorno que contiene la API key.
        max_tokens: Máximo de tokens en la respuesta.
        temperature: Temperatura de sampling (0.0 = determinista, 1.0 = creativo).
        system: Prompt de sistema por defecto (puede sobreescribirse en generate()).

    Example::

        provider = OpenAITextProvider(
            model="gpt-4o-mini",
            temperature=0.8,
            system="Eres un creador de contenido viral para redes sociales.",
        )
        provider.validate()
        script = provider.generate("Dame 5 consejos de disciplina para jóvenes")
    """

    _API_URL = "https://api.openai.com/v1/chat/completions"

    def __init__(
        self,
        model: str = "gpt-4o-mini",
        api_key_env: str = "OPENAI_API_KEY",
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
        """Verifica que la API key está disponible.

        Raises:
            ProviderError: Si la variable de entorno de la API key está vacía.
        """
        key = os.environ.get(self.api_key_env, "").strip()
        if not key:
            raise ProviderError(
                f"OpenAITextProvider requiere {self.api_key_env}=<tu_api_key> "
                "en variables de entorno."
            )

    def generate(self, prompt: str, system: str = "") -> str:
        """Genera texto usando OpenAI Chat Completions.

        Args:
            prompt: Mensaje del usuario.
            system: Prompt de sistema. Si está vacío, usa el configurado en __init__.

        Returns:
            Texto generado por el modelo.

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
        messages = []
        if effective_system:
            messages.append({"role": "system", "content": effective_system})
        messages.append({"role": "user", "content": prompt})

        payload = {
            "model": self.model,
            "messages": messages,
            "max_tokens": self.max_tokens,
            "temperature": self.temperature,
        }

        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        req = urllib.request.Request(self._API_URL, data=data, method="POST")
        req.add_header("Content-Type", "application/json")
        req.add_header("Authorization", f"Bearer {api_key}")

        try:
            with urllib.request.urlopen(req, timeout=self.timeout_s) as resp:
                raw = resp.read()
        except urllib.error.HTTPError as e:
            msg = e.read().decode("utf-8", errors="replace")[:400]
            raise ProviderError(f"OpenAI HTTPError {e.code}: {msg}") from e
        except Exception as e:
            raise ProviderError(f"OpenAI request falló: {e!r}") from e

        try:
            obj = json.loads(raw.decode("utf-8", errors="replace"))
        except Exception as e:
            raise ProviderError("OpenAI devolvió respuesta no-JSON.") from e

        try:
            return str(obj["choices"][0]["message"]["content"]).strip()
        except (KeyError, IndexError, TypeError) as e:
            raise ProviderError(f"OpenAI respuesta inesperada: {obj!r}") from e
