# -*- coding: utf-8 -*-
# app/providers/image_provider.py — ProviderImage (LIVE / REPLAY / DRY) con cache por pieza
#
# Config:
#   config/providers.json -> section "image" y provider activo en "providers"
#
# Cache:
#   workspace/cache/images/<provider>/<sha256>.png  (y .json de meta)

import os
import re
import io
import json
import time
import hashlib
import base64
import urllib.request
import urllib.error
import urllib.parse
from typing import Any, Dict, Optional, Tuple

# FIX: Importar Pillow a nivel de módulo para fallo temprano con mensaje claro
try:
    from PIL import Image, ImageDraw
except ImportError as _pil_err:
    raise ImportError(
        "Pillow no está instalado. Ejecuta: pip install Pillow>=9.0.0\n"
        f"(Error original: {_pil_err})"
    ) from _pil_err




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

        if self.provider_type not in ("http_json", "pixabay_stock"):
            raise ValueError(
                f"ProviderImage solo soporta type=http_json|pixabay_stock (actual: {self.provider_type})"
            )

        self.url = str(self.pcfg.get("url", "")).strip()
        self.method = str(self.pcfg.get("method", "POST")).upper().strip()
        self.timeout_s = int(self.pcfg.get("timeout_s", 120))

        self.headers_tpl = dict(self.pcfg.get("headers", {}) or {})
        self.body_tpl = self.pcfg.get("body", {}) or {}
        self.extract_paths = list(self.pcfg.get("extract_paths", []) or ["data.0.b64_json"])
        self.fingerprint_fields = list(self.pcfg.get("fingerprint_fields", []) or ["type", "url", "model"])

        # Pixabay-specific
        self.api_key_env = str(self.pcfg.get("api_key_env", "PIXABAY_API_KEY")).strip() or "PIXABAY_API_KEY"
        self.image_type = str(self.pcfg.get("image_type", "photo")).strip() or "photo"
        self.orientation = str(self.pcfg.get("orientation", "vertical")).strip() or "vertical"
        self.safesearch = bool(self.pcfg.get("safesearch", True))
        self.per_page = int(self.pcfg.get("per_page", 10) or 10)

        if self.provider_type == "http_json" and not self.url:
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

    def _choose_best_pixabay_hit(self, hits: Any, target_ratio: float = 9.0 / 16.0) -> Dict[str, Any]:
        if not isinstance(hits, list) or not hits:
            raise RuntimeError("Pixabay no devolvió resultados")

        scored = []
        for hit in hits:
            if not isinstance(hit, dict):
                continue

            w = int(hit.get("imageWidth") or hit.get("webformatWidth") or 0)
            h = int(hit.get("imageHeight") or hit.get("webformatHeight") or 0)
            downloads = int(hit.get("downloads") or 0)
            likes = int(hit.get("likes") or 0)
            views = int(hit.get("views") or 0)

            ratio = (w / h) if w > 0 and h > 0 else 1.0
            ratio_penalty = abs(ratio - target_ratio)  # 0.0 = perfecto
            ratio_score = max(0.0, 1.0 - ratio_penalty / 1.0) * 100.0

            popularity_score = (
                min(downloads / 5000.0, 1.0) * 50.0 +
                min(likes / 500.0, 1.0) * 30.0 +
                min(views / 50000.0, 1.0) * 20.0
            )

            size_bonus = 20.0 if (w >= 720 and h >= 1080) else (10.0 if w >= 480 else 0.0)

            score = ratio_score * 0.5 + popularity_score * 0.35 + size_bonus * 0.15
            scored.append((score, int(hit.get("id", 0) or 0), hit))

        if not scored:
            raise RuntimeError("Pixabay no devolvió hits utilizables")

        scored.sort(key=lambda x: (-x[0], x[1]))
        return scored[0][2]

    def _pixabay_call(self, prompt: str, params: Dict[str, Any]) -> Tuple[bytes, Dict[str, Any]]:
        api_key = os.getenv(self.api_key_env, "").strip()
        if not api_key:
            raise RuntimeError(f"Falta {self.api_key_env} para provider pixabay_stock")

        stock_query = str(params.get("stock_query", "") or "").strip() 
        _raw_prompt = str(prompt or "").strip() 
        _RENDER_PREFIX = "Imagen vertical 9:16, alta calidad, lista para reel." 
        if _raw_prompt.startswith(_RENDER_PREFIX): 
            _raw_prompt = _raw_prompt[len(_RENDER_PREFIX):].strip().lstrip("\n").strip() 
        _raw_prompt = _raw_prompt[:100].strip() 
        query = stock_query or _raw_prompt 
        if not query: 
            raise RuntimeError("Pixabay requiere query no vacía") 
        image_type = str(params.get("image_type", self.image_type) or self.image_type).strip() or "photo"
        orientation = str(params.get("orientation", self.orientation) or self.orientation).strip() or "vertical"
        safesearch = params.get("safesearch", self.safesearch)
        if isinstance(safesearch, str):
            safesearch = safesearch.strip().lower() in ("1", "true", "yes", "on")
        safesearch_str = "true" if bool(safesearch) else "false"
        per_page = int(params.get("per_page", self.per_page) or self.per_page)

        qs = urllib.parse.urlencode({
            "key": api_key,
            "q": query,
            "image_type": image_type,
            "orientation": orientation,
            "safesearch": safesearch_str,
            "per_page": str(per_page),
            "page": "1",
        })
        search_url = f"https://pixabay.com/api/?{qs}"

        req = urllib.request.Request(
            search_url,
            headers={"User-Agent": "STUDIO_MVP/0.3 pixabay_stock deterministic provider"},
        )
        try:
            with urllib.request.urlopen(req, timeout=self.timeout_s) as resp:
                raw = resp.read()
                status = getattr(resp, "status", 200)
                ctype = resp.headers.get("Content-Type", "")
        except urllib.error.HTTPError as e:
            raw = e.read()
            raise RuntimeError(f"Pixabay HTTPError {e.code}: {raw[:400]!r}")
        except Exception as e:
            raise RuntimeError(f"Pixabay request falló: {e!r}")

        try:
            obj = json.loads(raw.decode("utf-8", errors="replace"))
        except Exception:
            raise RuntimeError(f"Pixabay devolvió respuesta no JSON (status={status}, content-type={ctype})")

        hits = obj.get("hits", [])
        best = self._choose_best_pixabay_hit(hits)

        download_url = (
            best.get("largeImageURL")
            or best.get("webformatURL")
            or best.get("previewURL")
            or ""
        )
        if not download_url:
            raise RuntimeError("Pixabay hit sin download URL")

        req_img = urllib.request.Request(
            download_url,
            headers={"User-Agent": "STUDIO_MVP/0.3 pixabay_stock deterministic provider"},
        )
        try:
            with urllib.request.urlopen(req_img, timeout=self.timeout_s) as resp:
                img_bytes = resp.read()
                img_ctype = resp.headers.get("Content-Type", "")
        except urllib.error.HTTPError as e:
            raw = e.read()
            raise RuntimeError(f"Pixabay image HTTPError {e.code}: {raw[:400]!r}")
        except Exception as e:
            raise RuntimeError(f"Pixabay image download falló: {e!r}")

        redacted_search_url = re.sub(r"([?&]key=)[^&]+", r"\1***REDACTED***", search_url)

        meta = {
            "status": status,
            "content_type": ctype,
            "image_content_type": img_ctype,
            "query": query,
            "stock_query_used": bool(stock_query),
            "selected_from_total_hits": int(obj.get("totalHits", 0) or 0),
            "asset_id": str(best.get("id", "")),
            "page_url": str(best.get("pageURL", "") or ""),
            "download_url": str(download_url),
            "user": str(best.get("user", "") or ""),
            "tags": str(best.get("tags", "") or ""),
            "width": int(best.get("imageWidth") or best.get("webformatWidth") or 0),
            "height": int(best.get("imageHeight") or best.get("webformatHeight") or 0),
            "likes": int(best.get("likes") or 0),
            "downloads": int(best.get("downloads") or 0),
            "views": int(best.get("views") or 0),
            "image_type": image_type,
            "orientation": orientation,
            "safesearch": safesearch_str,
            "api_key_env": self.api_key_env,
            "api_search_url": redacted_search_url,
            "license_note": "Pixabay asset descargado localmente para uso determinista; revisar licencia y atribucion si aplica.",
        }
        return img_bytes, meta

    def _normalize_image_bytes_to_png(self, img_bytes: bytes) -> bytes:

        try:
            src = Image.open(io.BytesIO(img_bytes))
            if src.mode not in ("RGB", "RGBA"):
                src = src.convert("RGB")
            elif src.mode == "RGBA":
                bg = Image.new("RGB", src.size, (255, 255, 255))
                bg.paste(src, mask=src.split()[-1])
                src = bg

            out = io.BytesIO()
            src.save(out, format="PNG", optimize=True)
            return out.getvalue()
        except Exception as e:
            raise RuntimeError(f"No se pudo normalizar imagen a PNG: {e!r}")

    def _placeholder_png(self) -> bytes:
        # Placeholder robusto 9:16 (siempre válido para MoviePy/Pillow)

        w, h = 720, 1280
        img = Image.new('RGB', (w, h), (0, 0, 0))
        d = ImageDraw.Draw(img)
        d.text((40, 40), 'STUDIO DRY', fill=(255, 255, 255))

        buf = io.BytesIO()
        img.save(buf, format='PNG', optimize=True)
        return buf.getvalue()


    def _live_call(self, prompt: str, params: Dict[str, Any]) -> tuple:
        if self.provider_type == "pixabay_stock":
            return self._pixabay_call(prompt, params)
        return self._http_call(prompt, params)


    def _http_call_with_retry(self, prompt: str, params: Dict[str, Any], max_retries: int = 3) -> tuple:
        """Llama a la API con reintentos automáticos ante errores 429/5xx/red."""
        import time
        last_err = None
        for attempt in range(max_retries):
            try:
                return self._live_call(prompt, params)
            except RuntimeError as e:
                last_err = e
                msg = str(e)
                # Rate limit o server error: reintentar con backoff exponencial
                if any(code in msg for code in ("429", "500", "502", "503", "504")):
                    wait = (2 ** attempt) * 5  # 5s, 10s, 20s
                    print(f"  [retry {attempt+1}/{max_retries}] Error: {msg[:80]} — esperando {wait}s...")
                    time.sleep(wait)
                else:
                    raise  # Error sin retry
        raise RuntimeError(f"API falló tras {max_retries} intentos: {last_err}")

    def generate(self, *, purpose: str, prompt: str, seed: Optional[int] = None, **overrides: Any) -> Dict[str, Any]:
        purpose = str(purpose or "image").strip()
        prompt = str(prompt or "").strip()
        if not prompt:
            raise ValueError("prompt vacío")

        params = dict(self.default_params)
        for k, v in overrides.items():
            params[k] = v

        cache_key = self._make_cache_key(purpose, prompt, seed, params)
        created_at = int(time.time())
        img_path, meta_path = self._cache_paths(cache_key)

        # DRY: si hay cache, úsalo; si no, placeholder
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
        if self.provider_type == "pixabay_stock":
            img_bytes = self._normalize_image_bytes_to_png(img_bytes)
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


