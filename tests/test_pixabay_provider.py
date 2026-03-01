# -*- coding: utf-8 -*-

import base64
import hashlib
import os
from pathlib import Path

from studio.providers.image.pixabay_image import PixabayImageProvider


_PNG_1X1 = base64.b64decode(
    b"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+X2dAAAAAASUVORK5CYII="
)


def test_pixabay_provider_fallback_when_api_key_missing(tmp_path, monkeypatch):
    monkeypatch.delenv("PIXABAY_API_KEY", raising=False)
    p = PixabayImageProvider()
    out = tmp_path / "img.png"

    got = p.generate("ciudad nocturna", str(out))
    assert Path(got).exists()
    raw = Path(got).read_bytes()
    assert raw == _PNG_1X1


def test_pixabay_provider_fallback_on_network_error(tmp_path, monkeypatch):
    monkeypatch.setenv("PIXABAY_API_KEY", "dummy")
    p = PixabayImageProvider()

    def _boom(*args, **kwargs):
        raise OSError("forced offline")

    monkeypatch.setattr(p, "_fetch_best_image_url", _boom)
    out = tmp_path / "img_net_err.png"
    got = p.generate("montanas", str(out))

    assert Path(got).exists()
    assert hashlib.sha256(Path(got).read_bytes()).hexdigest() == hashlib.sha256(_PNG_1X1).hexdigest()


def test_pixabay_provider_replay_strict_without_cache_uses_fallback(tmp_path, monkeypatch):
    monkeypatch.setenv("PIXABAY_API_KEY", "dummy")
    p = PixabayImageProvider(replay_strict=True, cache_enabled=False)
    out = tmp_path / "img_replay.png"

    got = p.generate("playa", str(out))
    assert os.path.exists(got)
    assert Path(got).read_bytes() == _PNG_1X1
