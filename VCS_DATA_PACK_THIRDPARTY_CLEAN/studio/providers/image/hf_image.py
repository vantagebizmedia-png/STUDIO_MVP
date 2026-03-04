# -*- coding: utf-8 -*-
from __future__ import annotations

# STUDIO_HF_IMAGE_MODEL_CONFIG_v2
DEFAULT_MODEL = "black-forest-labs/FLUX.1-schnell"

import os

from studio.exceptions import ProviderError
from studio.providers.image.base_image import BaseImageProvider


class HFImageProvider(BaseImageProvider):
    """Text-to-Image usando Hugging Face Inference Providers (router) vía huggingface_hub.

    Requiere env: HF_TOKEN (token de Hugging Face).
    """

    def __init__(
        self,
        model: str = "black-forest-labs/FLUX.1-schnell",
        provider: str = "hf-inference",
        token_env: str = "HF_TOKEN",
    ) -> None:
        self.model = str(model).strip()
        self.provider = str(provider).strip() or "auto"
        self.token_env = str(token_env).strip()

    def validate(self) -> None:
        tok = os.environ.get(self.token_env, "").strip()
        if not tok:
            raise ProviderError(f"HFImageProvider requiere {self.token_env}=<token> en variables de entorno.")
        if not self.model:
            raise ProviderError("HFImageProvider requiere model no vacío.")

        try:
            from huggingface_hub import InferenceClient  # noqa: F401
        except Exception as e:
            raise ProviderError("Instala deps: pip install huggingface_hub pillow") from e

    def generate(self, prompt: str, output_path: str) -> str:
        prompt = str(prompt or "").strip()
        if not prompt:
            raise ValueError("prompt vacío")

        tok = os.environ.get(self.token_env, "").strip()
        if not tok:
            raise ProviderError(f"Falta {self.token_env}. Setea {self.token_env}=<token>.")

        try:
            from huggingface_hub import InferenceClient
        except Exception as e:
            raise ProviderError("Instala deps: pip install huggingface_hub pillow") from e

        try:
            client = InferenceClient(provider=self.provider, api_key=tok)
            img = client.text_to_image(prompt, model=self.model)  # PIL.Image
        except Exception as e:
            raise ProviderError(f"HF InferenceClient falló: {e!r}") from e

        os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
        try:
            img.save(output_path)
        except Exception as e:
            raise ProviderError(f"No se pudo guardar imagen en {output_path}: {e!r}") from e

        return output_path