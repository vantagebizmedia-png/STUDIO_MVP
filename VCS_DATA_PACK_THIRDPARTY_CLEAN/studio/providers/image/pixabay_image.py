# -*- coding: utf-8 -*-
from __future__ import annotations

import base64
import json
import os
import urllib.error
import urllib.parse
import urllib.request

from studio.providers.image.base_image import BaseImageProvider


_PNG_1X1 = base64.b64decode(
    b"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+X2dAAAAAASUVORK5CYII="
)


class PixabayImageProvider(BaseImageProvider):
    """Provider de imagen stock via Pixabay con fallback determinista offline."""

    _API_URL = "https://pixabay.com/api/"

    def __init__(
        self,
        *,
        api_key_env: str = "PIXABAY_API_KEY",
        timeout_s: int = 10,
        replay_strict: bool = False,
        cache_enabled: bool = True,
    ) -> None:
        self.api_key_env = str(api_key_env or "PIXABAY_API_KEY").strip()
        self.timeout_s = int(timeout_s or 10)
        self.replay_strict = bool(replay_strict)
        self.cache_enabled = bool(cache_enabled)

    def validate(self) -> None:
        return

    def _write_fallback_png(self, output_path: str) -> str:
        os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
        with open(output_path, "wb") as f:
            f.write(_PNG_1X1)
        return output_path

    def _build_search_url(self, *, api_key: str, query: str) -> str:
        params = {
            "key": api_key,
            "q": query,
            "image_type": "photo",
            "safesearch": "true",
            "per_page": "3",
            "page": "1",
        }
        return f"{self._API_URL}?{urllib.parse.urlencode(params)}"

    def _fetch_best_image_url(self, *, api_key: str, query: str) -> str:
        search_url = self._build_search_url(api_key=api_key, query=query)
        req = urllib.request.Request(search_url, method="GET")
        with urllib.request.urlopen(req, timeout=self.timeout_s) as resp:
            payload = resp.read()
        obj = json.loads(payload.decode("utf-8", errors="replace"))
        hits = obj.get("hits") or []
        if not isinstance(hits, list) or not hits:
            return ""
        for hit in hits:
            if not isinstance(hit, dict):
                continue
            for key in ("largeImageURL", "webformatURL", "previewURL"):
                u = str(hit.get(key) or "").strip()
                if u:
                    return u
        return ""

    def _download_image(self, *, url: str, output_path: str) -> str:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, timeout=self.timeout_s) as resp:
            data = resp.read()
        if not data:
            raise ValueError("imagen vacia")
        os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
        with open(output_path, "wb") as f:
            f.write(data)
        return output_path

    def generate(self, prompt: str, output_path: str) -> str:
        query = str(prompt or "").strip()
        if not query:
            query = "stock image"

        # Mantiene smoke/offline estable: en replay estricto sin cache, no intentar red.
        if self.replay_strict and (not self.cache_enabled):
            return self._write_fallback_png(output_path)

        api_key = os.environ.get(self.api_key_env, "").strip()
        if not api_key:
            return self._write_fallback_png(output_path)

        try:
            image_url = self._fetch_best_image_url(api_key=api_key, query=query)
            if not image_url:
                return self._write_fallback_png(output_path)
            return self._download_image(url=image_url, output_path=output_path)
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, ValueError, OSError, json.JSONDecodeError):
            return self._write_fallback_png(output_path)
