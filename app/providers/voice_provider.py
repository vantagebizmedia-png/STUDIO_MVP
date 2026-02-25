# -*- coding: utf-8 -*-
# app/providers/voice_provider.py â€” ProviderVoice (TTS) LIVE / REPLAY / DRY con cache por pieza
#
# Config:
#   config/providers.json -> section "voice"
#
# Cache:
#   workspace/cache/voice/<provider>/<sha256>.<format>  (y .json de meta)
#
# RecomendaciÃ³n MVP:
#   usa format="wav" (mÃ¡s fÃ¡cil para placeholders y concat).

import os
import re
import json
import time
import hashlib
import urllib.request
import urllib.error
import wave
from typing import Any, Dict, Optional, Tuple


# Importar utilidades compartidas (evita duplicación con image_provider)
from app.providers._utils import (
    read_json as _read_json,
    write_json as _write_json,
    stable_dumps as _stable_dumps,
    sha256_hex as _sha256_hex,
    sub_env as _sub_env,
    find_project_root as _find_project_root,
    apply_template as _apply_template,
)


class ProviderVoice:
    def __init__(self, config_path: Optional[str] = None) -> None:
        self.project_root = _find_project_root()
        self.config_path = config_path or os.path.join(self.project_root, "config", "providers.json")
        self.cfg = _read_json(self.config_path)

        vcfg = self.cfg.get("voice", {}) or {}
        self.mode = str(vcfg.get("mode", "LIVE")).upper().strip()
        self.active_provider = str(vcfg.get("active_provider", "")).strip()
        self.default_params = dict(vcfg.get("default_params", {}) or {})

        self.cache_cfg = dict(vcfg.get("cache", {}) or {})
        raw = str(self.cache_cfg.get("dir", "workspace/cache/voice"))
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
            raise ValueError(f"voice.active_provider '{self.active_provider}' no existe en providers.json")

        self.pcfg = dict(providers[self.active_provider] or {})
        self.provider_type = str(self.pcfg.get("type", "")).strip()
        self.model = str(self.pcfg.get("model", "")).strip()
        if self.provider_type != "http_binary":
            raise ValueError(f"ProviderVoice requiere type=http_binary (actual: {self.provider_type})")

        self.url = str(self.pcfg.get("url", "")).strip()
        self.method = str(self.pcfg.get("method", "POST")).upper().strip()
        self.timeout_s = int(self.pcfg.get("timeout_s", 120))
        self.headers_tpl = dict(self.pcfg.get("headers", {}) or {})
        self.body_tpl = self.pcfg.get("body", {}) or {}
        self.fingerprint_fields = list(self.pcfg.get("fingerprint_fields", []) or ["type", "url", "model"])

        if not self.url:
            raise ValueError("ProviderVoice requiere url")

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

    def _cache_paths(self, cache_key: str, fmt: str) -> Tuple[str, str]:
        fmt = (fmt or "wav").lower().strip()
        prov_dir = os.path.join(self.cache_dir, self.active_provider)
        os.makedirs(prov_dir, exist_ok=True)
        return (
            os.path.join(prov_dir, f"{cache_key}.{fmt}"),
            os.path.join(prov_dir, f"{cache_key}.json"),
        )

    def _make_cache_key(self, purpose: str, text: str, seed: Optional[int], params: Dict[str, Any]) -> str:
        payload = {
            "purpose": purpose,
            "text": text,
            "seed": seed,
            "params": params,
            "provider": self.active_provider,
            "fingerprint": self._provider_fingerprint(),
            "salt": self.salt,
        }
        return _sha256_hex(_stable_dumps(payload))

    def _http_call(self, text: str, params: Dict[str, Any]) -> Tuple[bytes, Dict[str, Any]]:
        # ctx: {{model}}, {{prompt}}, y params (voice, format, etc.)
        ctx = {"model": self.model, "prompt": text}
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

        meta = {"status": status, "content_type": ctype}
        return raw, meta

    def _silent_wav_bytes(self, duration_s: float = 0.6, sr: int = 24000) -> bytes:
        # WAV mono 16-bit, silencio
        import io
        nframes = max(1, int(float(duration_s) * int(sr)))
        buf = io.BytesIO()
        with wave.open(buf, "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(int(sr))
            wf.writeframes(b"\x00\x00" * nframes)
        return buf.getvalue()


    def _http_call_with_retry(self, text: str, params: Dict[str, Any], max_retries: int = 3) -> tuple:
        """Llama a la API TTS con reintentos automáticos ante errores 429/5xx/red."""
        import time
        last_err = None
        for attempt in range(max_retries):
            try:
                return self._http_call(text, params)
            except RuntimeError as e:
                last_err = e
                msg = str(e)
                if any(code in msg for code in ("429", "500", "502", "503", "504")):
                    wait = (2 ** attempt) * 5
                    print(f"  [retry {attempt+1}/{max_retries}] TTS error: {msg[:80]} — esperando {wait}s...")
                    time.sleep(wait)
                else:
                    raise
        raise RuntimeError(f"TTS API falló tras {max_retries} intentos: {last_err}")

    def speak(self, *, purpose: str, text: str, seed: Optional[int] = None, **overrides: Any) -> Dict[str, Any]:
        purpose = str(purpose or "voice").strip()
        text = str(text or "").strip()
        if not text:
            raise ValueError("text vacÃ­o")

        params = dict(self.default_params)
        for k, v in overrides.items():
            params[k] = v

        fmt = str(params.get("format") or "wav").lower().strip()
        cache_key = self._make_cache_key(purpose, text, seed, params)
        created_at = int(time.time())
        audio_path, meta_path = self._cache_paths(cache_key, fmt)

        # DRY
        if self.mode == "DRY":
            if self.cache_policy != "off" and os.path.exists(audio_path):
                return {"path": audio_path, "provider": self.active_provider, "model": self.model, "mode": self.mode, "cache_hit": True, "cache_key": cache_key, "note": "voice: dry cache_hit"}
            # placeholder (WAV)
            if fmt != "wav":
                # forzamos wav si el usuario pidiÃ³ mp3 pero estamos en DRY
                fmt = "wav"
                audio_path, meta_path = self._cache_paths(cache_key, fmt)
            with open(audio_path, "wb") as f:
                f.write(self._silent_wav_bytes())
            _write_json(meta_path, {"schema": "STUDIO_VOICE_CACHE_V1", "created_at_unix": created_at, "mode": "DRY", "cache_key": cache_key, "note": "DRY silent placeholder"})
            return {"path": audio_path, "provider": self.active_provider, "model": self.model, "mode": self.mode, "cache_hit": False, "cache_key": cache_key, "note": "voice: dry placeholder"}

        # REPLAY
        if self.mode == "REPLAY":
            if os.path.exists(audio_path):
                return {"path": audio_path, "provider": self.active_provider, "model": self.model, "mode": self.mode, "cache_hit": True, "cache_key": cache_key, "note": "voice: replay cache_hit"}
            if self.replay_strict:
                raise RuntimeError(f"REPLAY strict: no existe cache para key {cache_key}")
            if fmt != "wav":
                fmt = "wav"
                audio_path, meta_path = self._cache_paths(cache_key, fmt)
            with open(audio_path, "wb") as f:
                f.write(self._silent_wav_bytes())
            _write_json(meta_path, {"schema": "STUDIO_VOICE_CACHE_V1", "created_at_unix": created_at, "mode": "REPLAY_FALLBACK", "cache_key": cache_key, "note": "missing cache -> silent placeholder"})
            return {"path": audio_path, "provider": self.active_provider, "model": self.model, "mode": self.mode, "cache_hit": False, "cache_key": cache_key, "note": "voice: replay fallback silent"}

        # LIVE
        if self.cache_policy != "off" and self.cache_policy != "refresh" and os.path.exists(audio_path):
            return {"path": audio_path, "provider": self.active_provider, "model": self.model, "mode": self.mode, "cache_hit": True, "cache_key": cache_key, "note": "voice: live cache_hit"}

        raw, http_meta = self._http_call(text, params)
        with open(audio_path, "wb") as f:
            f.write(raw)

        record = {
            "schema": "STUDIO_VOICE_CACHE_V1",
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
        return {"path": audio_path, "provider": self.active_provider, "model": self.model, "mode": self.mode, "cache_hit": False, "cache_key": cache_key, "note": "voice: generated"}

