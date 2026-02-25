# -*- coding: utf-8 -*-
from __future__ import annotations

import base64
import json
import os
import urllib.request
import urllib.error
from typing import Any, Optional

from studio.exceptions import ProviderError
from studio.providers.image.base_image import BaseImageProvider


class A1111ImageProvider(BaseImageProvider):
    """Automatic1111 Stable Diffusion WebUI (local) via HTTP API.

    Requiere que el WebUI esté corriendo con --api.
    Por seguridad, si STUDIO_ALLOW_LIVE != "1", bloquea generación (igual que el guard).
    """

    def __init__(
        self,
        base_url: str = "http://127.0.0.1:7860",
        timeout_s: int = 600,
        # defaults pensados para 6GB VRAM
        width: int = 512,
        height: int = 512,
        steps: int = 20,
        cfg_scale: float = 7.0,
        sampler_name: str = "DPM++ 2M Karras",
        seed: int = -1,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.timeout_s = int(timeout_s)
        self.width = int(width)
        self.height = int(height)
        self.steps = int(steps)
        self.cfg_scale = float(cfg_scale)
        self.sampler_name = str(sampler_name)
        self.seed = int(seed)

    def validate(self) -> None:
        if not self.base_url.startswith("http"):
            raise ProviderError("A1111 base_url inválida.")
        # NO hacemos ping aquí para mantener validate sin red.

    def _post_json(self, path: str, payload: dict[str, Any]) -> dict[str, Any]:
        url = self.base_url + path
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        req = urllib.request.Request(url, data=data, method="POST")
        req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=self.timeout_s) as resp:
                raw = resp.read()
        except urllib.error.HTTPError as e:
            msg = e.read().decode("utf-8", errors="replace")[:400]
            raise ProviderError(f"A1111 HTTPError {e.code}: {msg}")
        except Exception as e:
            raise ProviderError(f"A1111 request falló: {e!r}")
        try:
            return json.loads(raw.decode("utf-8", errors="replace"))
        except Exception:
            raise ProviderError("A1111 devolvió respuesta no-JSON.")

    def generate(self, prompt: str, output_path: str) -> str:
        if os.environ.get("STUDIO_ALLOW_LIVE", "") != "1":
            raise ProviderError("A1111 LIVE bloqueado. Setea STUDIO_ALLOW_LIVE=1 para permitir generación local.")

        prompt = str(prompt or "").strip()
        if not prompt:
            raise ValueError("prompt vacío")

        payload: dict[str, Any] = {
            "prompt": prompt,
            "negative_prompt": "",
            "steps": self.steps,
            "cfg_scale": self.cfg_scale,
            "sampler_name": self.sampler_name,
            "width": self.width,
            "height": self.height,
            "seed": self.seed,
            "batch_size": 1,
            "n_iter": 1,
        }

        out = self._post_json("/sdapi/v1/txt2img", payload)
        imgs = out.get("images")
        if not isinstance(imgs, list) or not imgs:
            raise ProviderError(f"A1111 respuesta sin images: {out!r}")

        b64 = imgs[0]
        if not isinstance(b64, str) or not b64:
            raise ProviderError("A1111 image b64 inválido.")

        # A1111 suele devolver solo base64; a veces incluye "data:image/png;base64,..."
        if "," in b64 and b64.strip().lower().startswith("data:"):
            b64 = b64.split(",", 1)[1]

        raw = base64.b64decode(b64.encode("utf-8"))
        os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
        with open(output_path, "wb") as f:
            f.write(raw)

        return output_path