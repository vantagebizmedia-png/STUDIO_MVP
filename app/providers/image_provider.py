# -*- coding: utf-8 -*-
# app/providers/image_provider.py â€” ProviderImage (LIVE / REPLAY / DRY) con cache por pieza
#
# Config:
#   config/providers.json -> section "image" y provider activo en "providers"
#
# Cache:
#   workspace/cache/images/<provider>/<sha256>.png  (y .json de meta)

import os
import re
import json
import time
import hashlib
import base64
import urllib.request
import urllib.error
from typing import Any, Dict, Optional, Tuple


# Importar utilidades compartidas (evita duplicación con voice_provider)
from app.providers._utils import (
    read_json as _read_json,
    write_json as _write_json,
    stable_dumps as _stable_dumps,
    sha256_hex as _sha256_hex,
    sub_env as _sub_env,
    find_project_root as _find_project_root,
    apply_template as _apply_template,
    extract_path as _extract_path,
)


class ProviderImage:
    def __init__(self, config_path: Optional[str] = None) -> None:
        self.project_root = _find_project_root()
        self.config_path = config_path or os.path.join(self.project_root, "config", "providers.json")
        self.cfg = _read_json(self.config_path)

        img_cfg = self.cfg.get("image", {}) or {}
        self.mode = str(img_cfg.get("mode", "LIVE")).upper().strip()
        self.active_provider = str(img_cfg.get("active_provider", "")).strip()
        self.default_params = dict(img_cfg.get("default_params", {}) or {})

        self.cache_cfg = dict(img_cfg.get("cache", {}) or {})
        raw = str(self.cache_cfg.get("dir", "workspace/cache/images"))
        ws = os.getenv("STUDIO_WORKSPACE", "").strip()
        norm = raw.replace("\\", "/").lstrip("./")
        if ws and (norm == "workspace" or norm.startswith("workspace/")):
            tail = norm[len("workspace/"):] if norm.startswith("workspace/") else ""
            raw = os.path.join(ws, tail) if tail else ws
        self.cache_dir = raw if os.path.isabs(raw) else os.path.join(self.project_root, raw)
        self.cache_policy = str(self.cache_cfg.get("policy", "prefer")).lower().strip()  # prefer|refresh|off
        self.replay_strict = bool(self.cache_cfg.get("replay_strict", True))
        self.salt = str(self.cache_cfg.get("salt", "") or "")

        providers = dict(self.cfg.get("providers", {}) or {})
        if self.active_provider not in providers:
            raise ValueError(f"image.active_provider '{self.active_provider}' no existe en providers.json")

        self.pcfg = dict(providers[self.active_provider] or {})
        self.provider_type = str(self.pcfg.get("type", "")).strip()
        self.model = str(self.pcfg.get("model", "")).strip()

        if self.provider_type != "http_json":
            raise ValueError(f"ProviderImage solo soporta type=http_json (actual: {self.provider_type})")

        self.url = str(self.pcfg.get("url", "")).strip()
        self.method = str(self.pcfg.get("method", "POST")).upper().strip()
        self.timeout_s = int(self.pcfg.get("timeout_s", 120))

        self.headers_tpl = dict(self.pcfg.get("headers", {}) or {})
        self.body_tpl = self.pcfg.get("body", {}) or {}
        self.extract_paths = list(self.pcfg.get("extract_paths", []) or ["data.0.b64_json"])
        self.fingerprint_fields = list(self.pcfg.get("fingerprint_fields", []) or ["type", "url", "model"])

        if not self.url:
            raise ValueError("ProviderImage requiere url")

    def _provider_fingerprint(self) -> Dict[str, Any]:
        out: Dict[str, Any] = {}
        for f in self.fingerprint_fields:
            if f == "type":
                out["type"] = self.provider_type
            elif f == "url":
                out["url"] = self.url
            elif f == "model":
                out["model"] = self.model
            else:
                out[f] = self.pcfg.get(f)
        return out

    def _cache_paths(self, cache_key: str) -> Tuple[str, str]:
        prov_dir = os.path.join(self.cache_dir, self.active_provider)
        os.makedirs(prov_dir, exist_ok=True)
        return (
            os.path.join(prov_dir, f"{cache_key}.png"),
            os.path.join(prov_dir, f"{cache_key}.json"),
        )

    def _make_cache_key(self, purpose: str, prompt: str, seed: Optional[int], params: Dict[str, Any]) -> str:
        payload = {
            "purpose": purpose,
            "prompt": prompt,
            "seed": seed,
            "params": params,
            "provider": self.active_provider,
            "fingerprint": self._provider_fingerprint(),
            "salt": self.salt,
        }
        return _sha256_hex(_stable_dumps(payload))

    def _http_call(self, prompt: str, params: Dict[str, Any]) -> Tuple[bytes, Dict[str, Any]]:
        ctx = {"model": self.model, "prompt": prompt}
        for k, v in params.items():
            ctx[str(k)] = v

        headers = {k: _apply_template(v, ctx) for k, v in self.headers_tpl.items()}
        body_obj = _apply_template(self.body_tpl, ctx)
        data = json.dumps(body_obj, ensure_ascii=False).encode("utf-8")

        req = urllib.request.Request(self.url, data=data, method=self.method)
        for k, v in headers.items():
            req.add_header(k, str(v))

        try:
            with urllib.request.urlopen(req, timeout=self.timeout_s) as resp:
                raw = resp.read()
                status = getattr(resp, "status", 200)
                ctype = resp.headers.get("Content-Type", "")
        except urllib.error.HTTPError as e:
            raw = e.read()
            raise RuntimeError(f"HTTPError {e.code}: {raw[:400]!r}")
        except Exception as e:
            raise RuntimeError(str(e))

        try:
            obj = json.loads(raw.decode("utf-8", errors="replace"))
        except Exception:
            raise RuntimeError(f"Respuesta no JSON (status={status}, content-type={ctype})")

        b64_val = None
        for p in self.extract_paths:
            v = _extract_path(obj, p)
            if isinstance(v, str) and v.strip():
                b64_val = v.strip()
                break
        if not b64_val:
            raise RuntimeError("No se pudo extraer b64_json del response")

        img_bytes = base64.b64decode(b64_val)

        meta = {"status": status, "content_type": ctype}
        return img_bytes, meta

    def _placeholder_png(self) -> bytes:
        # Placeholder robusto 9:16 (siempre válido para MoviePy/Pillow)
        import io
        from PIL import Image, ImageDraw

        w, h = 720, 1280
        img = Image.new('RGB', (w, h), (0, 0, 0))
        d = ImageDraw.Draw(img)
        d.text((40, 40), 'STUDIO DRY', fill=(255, 255, 255))

        buf = io.BytesIO()
        img.save(buf, format='PNG', optimize=True)
        return buf.getvalue()


    def _http_call_with_retry(self, prompt: str, params: Dict[str, Any], max_retries: int = 3) -> tuple:
        """Llama a la API con reintentos automáticos ante errores 429/5xx/red."""
        import time
        last_err = None
        for attempt in range(max_retries):
            try:
                return self._http_call(prompt, params)
            except RuntimeError as e:
                last_err = e
                msg = str(e)
                # Rate limit o server error: reintentar con backoff exponencial
                if any(code in msg for code in ("429", "500", "502", "503", "504")):
                    wait = (2 ** attempt) * 5  # 5s, 10s, 20s
                    print(f"  [retry {attempt+1}/{max_retries}] Error: {msg[:80]} — esperando {wait}s...")
                    time.sleep(wait)
                else:
                    raise  # Error sin retry (ej: 400, 401, prompt inválido)
        raise RuntimeError(f"API falló tras {max_retries} intentos: {last_err}")

    def generate(self, *, purpose: str, prompt: str, seed: Optional[int] = None, **overrides: Any) -> Dict[str, Any]:
        purpose = str(purpose or "image").strip()
        prompt = str(prompt or "").strip()
        if not prompt:
            raise ValueError("prompt vacÃ­o")

        params = dict(self.default_params)
        for k, v in overrides.items():
            params[k] = v

        cache_key = self._make_cache_key(purpose, prompt, seed, params)
        created_at = int(time.time())
        img_path, meta_path = self._cache_paths(cache_key)

        # DRY: si hay cache, Ãºsalo; si no, placeholder
        if self.mode == "DRY":
            if self.cache_policy != "off" and os.path.exists(img_path):
                return {"path": img_path, "provider": self.active_provider, "model": self.model, "mode": self.mode, "cache_hit": True, "cache_key": cache_key, "note": "image: dry cache_hit"}
            # crear placeholder
            os.makedirs(os.path.dirname(img_path), exist_ok=True)
            with open(img_path, "wb") as f:
                f.write(self._placeholder_png())
            _write_json(meta_path, {"schema": "STUDIO_IMAGE_CACHE_V1", "created_at_unix": created_at, "mode": "DRY", "cache_key": cache_key, "note": "DRY placeholder"})
            return {"path": img_path, "provider": self.active_provider, "model": self.model, "mode": self.mode, "cache_hit": False, "cache_key": cache_key, "note": "image: dry placeholder"}

        # REPLAY: solo cache
        if self.mode == "REPLAY":
            if os.path.exists(img_path):
                return {"path": img_path, "provider": self.active_provider, "model": self.model, "mode": self.mode, "cache_hit": True, "cache_key": cache_key, "note": "image: replay cache_hit"}
            if self.replay_strict:
                raise RuntimeError(f"REPLAY strict: no existe cache para key {cache_key}")
            # fallback placeholder
            with open(img_path, "wb") as f:
                f.write(self._placeholder_png())
            _write_json(meta_path, {"schema": "STUDIO_IMAGE_CACHE_V1", "created_at_unix": created_at, "mode": "REPLAY_FALLBACK", "cache_key": cache_key, "note": "missing cache -> placeholder"})
            return {"path": img_path, "provider": self.active_provider, "model": self.model, "mode": "REPLAY", "cache_hit": False, "cache_key": cache_key, "note": "image: replay fallback placeholder"}

        # LIVE: prefer cache si policy=prefer
        if self.cache_policy != "off" and self.cache_policy != "refresh" and os.path.exists(img_path):
            return {"path": img_path, "provider": self.active_provider, "model": self.model, "mode": self.mode, "cache_hit": True, "cache_key": cache_key, "note": "image: live cache_hit"}

        img_bytes, http_meta = self._http_call_with_retry(prompt, params)
        with open(img_path, "wb") as f:
            f.write(img_bytes)

        record = {
            "schema": "STUDIO_IMAGE_CACHE_V1",
            "created_at_unix": created_at,
            "provider": self.active_provider,
            "model": self.model,
            "mode": self.mode,
            "purpose": purpose,
            "cache_key": cache_key,
            "params": params,
            "meta": http_meta,
        }
        _write_json(meta_path, record)
        return {"path": img_path, "provider": self.active_provider, "model": self.model, "mode": self.mode, "cache_hit": False, "cache_key": cache_key, "note": "image: generated"}

