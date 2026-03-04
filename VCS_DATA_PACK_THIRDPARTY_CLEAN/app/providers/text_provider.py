# -*- coding: utf-8 -*-
# app/providers/text_provider.py â€” ProviderText V2.4 (http_json)
# - Lee config/providers.json
# - Modos: DRY / LIVE / REPLAY
# - Cache: workspace/cache/text/<provider>/<sha256>.json
# - Decodifica HTTP en UTF-8 (y repara mojibake tÃ­pico si apareciera)
# - COERCE: fuerza campos numÃ©ricos a nÃºmero (temperature/top_p/max_tokens/max_output_tokens, etc.)

import os
import re
import json
import time
import hashlib
import urllib.request
import urllib.error
from dataclasses import dataclass
from typing import Any, Dict, Optional, Tuple


# -------------------------
# Data model
# -------------------------
@dataclass
class TextResult:
    text: str
    provider_name: str
    model: str
    mode: str
    cache_hit: bool
    cache_key: str
    created_at_unix: int


# -------------------------
# Helpers
# -------------------------
def _read_json(path: str) -> Any:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def _write_json(path: str, obj: Any) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)
        f.write("\n")


def _stable_dumps(obj: Any) -> str:
    return json.dumps(obj, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _sha256_hex(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def _sub_env(s: str) -> str:
    # Soporta ${ENV:VAR}
    def repl(m: re.Match) -> str:
        var = m.group(1)
        return os.environ.get(var, "")
    return re.sub(r"\$\{ENV:([A-Z0-9_]+)\}", repl, s or "")


def _apply_template(value: Any, ctx: Dict[str, Any]) -> Any:
    # Reemplaza {{k}} en strings; recursivo para dict/list.
    if isinstance(value, str):
        out = value
        for k, v in ctx.items():
            out = out.replace("{{" + k + "}}", str(v))
        out = _sub_env(out)
        return out
    if isinstance(value, dict):
        return {k: _apply_template(v, ctx) for k, v in value.items()}
    if isinstance(value, list):
        return [_apply_template(v, ctx) for v in value]
    return value


def _get_by_path(obj: Any, path: str) -> Any:
    # path tipo: "output.0.content.0.text"
    cur = obj
    for part in (path or "").split("."):
        if part == "":
            continue
        if isinstance(cur, dict):
            cur = cur.get(part)
        elif isinstance(cur, list):
            try:
                idx = int(part)
            except Exception:
                return None
            if idx < 0 or idx >= len(cur):
                return None
            cur = cur[idx]
        else:
            return None
    return cur


def _looks_mojibake(s: str) -> bool:
    if not s:
        return False
    bad = ("Ã‚", "Ãƒ", "Ã", " ")
    return any(b in s for b in bad)


def _repair_mojibake(s: str) -> str:
    if not s or not _looks_mojibake(s):
        return s
    try:
        candidate = s.encode("latin1", errors="ignore").decode("utf-8", errors="ignore")
        before = s.count("Ãƒ") + s.count("Ã‚")
        after = candidate.count("Ãƒ") + candidate.count("Ã‚")
        if candidate and after < before:
            return candidate
    except Exception:
        pass
    return s


def _to_float(x: Any, default: float) -> float:
    if isinstance(x, (int, float)):
        return float(x)
    if isinstance(x, str):
        s = x.strip().replace(",", ".")
        try:
            return float(s)
        except Exception:
            return default
    return default


def _to_int(x: Any, default: int) -> int:
    if isinstance(x, int):
        return x
    if isinstance(x, float):
        return int(x)
    if isinstance(x, str):
        s = x.strip()
        try:
            return int(float(s))
        except Exception:
            return default
    return default


def _coerce_numeric_fields(obj: Any) -> Any:
    """
    Convierte strings numÃ©ricos a nÃºmeros para campos tÃ­picos de sampling.
    Blindaje para Responses API: max_output_tokens suele venir templated como string.
    """
    num_float_keys = {"temperature", "top_p", "presence_penalty", "frequency_penalty"}
    num_int_keys = {"max_tokens", "max_output_tokens"}

    if isinstance(obj, dict):
        out: Dict[str, Any] = {}
        for k, v in obj.items():
            if k in num_float_keys:
                out[k] = _to_float(v, 0.2)
            elif k in num_int_keys:
                out[k] = _to_int(v, 1800)
            else:
                out[k] = _coerce_numeric_fields(v)
        return out
    if isinstance(obj, list):
        return [_coerce_numeric_fields(x) for x in obj]
    return obj


def _find_project_root() -> str:
    here = os.path.abspath(os.path.dirname(__file__))
    for _ in range(10):
        cand = os.path.join(here, "config", "providers.json")
        if os.path.exists(cand):
            return here
        here = os.path.dirname(here)
    return os.getcwd()


# -------------------------
# ProviderText
# -------------------------
class ProviderText:
    def __init__(self, config_path: Optional[str] = None) -> None:
        self.project_root = _find_project_root()
        self.config_path = config_path or os.path.join(self.project_root, "config", "providers.json")
        self.cfg = _read_json(self.config_path)

        text_cfg = self.cfg.get("text", {}) or {}
        self.mode = str(text_cfg.get("mode", "DRY")).upper().strip()
        self.active_provider = str(text_cfg.get("active_provider", "")).strip()

        self.default_params = dict(text_cfg.get("default_params", {}) or {})
        self.cache_cfg = dict(text_cfg.get("cache", {}) or {})
        raw = str(self.cache_cfg.get("dir", "workspace/cache/text"))
        ws = os.getenv("STUDIO_WORKSPACE", "").strip()
        norm = raw.replace("\\", "/").lstrip("./")
        if ws and (norm == "workspace" or norm.startswith("workspace/")):
            tail = norm[len("workspace/"):] if norm.startswith("workspace/") else ""
            raw = os.path.join(ws, tail) if tail else ws
        self.cache_dir = raw if os.path.isabs(raw) else os.path.join(self.project_root, raw)
        self.cache_policy = str(self.cache_cfg.get("policy", "prefer")).lower().strip()  # prefer|refresh|off
        self.replay_strict = bool(self.cache_cfg.get("replay_strict", True))
        self.salt = str(self.cache_cfg.get("salt", "") or "")

        self.providers = dict(self.cfg.get("providers", {}) or {})
        if self.active_provider not in self.providers:
            raise ValueError(f"active_provider '{self.active_provider}' no existe en providers.json")

        self.pcfg = dict(self.providers[self.active_provider] or {})
        self.provider_type = str(self.pcfg.get("type", "")).strip()
        self.model = str(self.pcfg.get("model", "")).strip()

        if self.provider_type != "http_json":
            raise ValueError(f"Provider type no soportado: {self.provider_type} (solo http_json)")

        self.url = str(self.pcfg.get("url", "")).strip()
        self.method = str(self.pcfg.get("method", "POST")).upper().strip()
        self.timeout_s = int(self.pcfg.get("timeout_s", 60))

        self.headers_tpl = dict(self.pcfg.get("headers", {}) or {})
        self.body_tpl = self.pcfg.get("body", {}) or {}
        self.extract_paths = list(self.pcfg.get("extract_paths", []) or [])
        self.fingerprint_fields = list(self.pcfg.get("fingerprint_fields", []) or [])

        if not self.url:
            raise ValueError("Provider http_json requiere 'url'")

        if not self.extract_paths:
            self.extract_paths = ["output.0.content.0.text"]

    def _provider_fingerprint(self) -> Dict[str, Any]:
        if not self.fingerprint_fields:
            return {"type": self.provider_type, "url": self.url, "model": self.model}
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

    def _cache_path(self, cache_key: str) -> str:
        prov_dir = os.path.join(self.cache_dir, self.active_provider)
        os.makedirs(prov_dir, exist_ok=True)
        return os.path.join(prov_dir, f"{cache_key}.json")

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

    def _load_cache(self, cache_key: str) -> Optional[Dict[str, Any]]:
        p = self._cache_path(cache_key)
        if os.path.exists(p):
            try:
                return _read_json(p)
            except Exception:
                return None
        return None

    def _save_cache(self, cache_key: str, record: Dict[str, Any]) -> None:
        p = self._cache_path(cache_key)
        _write_json(p, record)

    def _http_call(self, prompt: str, params: Dict[str, Any]) -> Tuple[str, Dict[str, Any]]:
        # Normalizar params numÃ©ricos ANTES de templating
        temp = _to_float(params.get("temperature", self.default_params.get("temperature", 0.2)), 0.2)
        top_p = _to_float(params.get("top_p", self.default_params.get("top_p", 1.0)), 1.0)

        # Algunos configs usan max_tokens, otros max_output_tokens (Responses)
        raw_max = params.get("max_output_tokens", None)
        if raw_max is None:
            raw_max = params.get("max_tokens", self.default_params.get("max_output_tokens", self.default_params.get("max_tokens", 1800)))
        max_out = _to_int(raw_max, 1800)

        ctx = {
            "model": self.model,
            "prompt": prompt,
            "temperature": temp,
            "top_p": top_p,
            "max_tokens": max_out,          # por compat
            "max_output_tokens": max_out,   # Responses API
        }

        headers = {k: _apply_template(v, ctx) for k, v in self.headers_tpl.items()}
        body_obj = _apply_template(self.body_tpl, ctx)

        # Blindaje final: coerciÃ³n numÃ©rica aunque el JSON tenga strings
        body_obj = _coerce_numeric_fields(body_obj)

        data = json.dumps(body_obj, ensure_ascii=False).encode("utf-8")
        req = urllib.request.Request(self.url, data=data, method=self.method)
        for k, v in headers.items():
            req.add_header(str(k), str(v))

        t0 = time.time()
        try:
            with urllib.request.urlopen(req, timeout=self.timeout_s) as resp:
                raw_bytes = resp.read()
                raw_text = raw_bytes.decode("utf-8", errors="replace")
                j = json.loads(raw_text)
        except urllib.error.HTTPError as e:
            try:
                err_body = e.read().decode("utf-8", errors="replace")
            except Exception:
                err_body = ""
            raise RuntimeError(f"HTTPError {e.code}: {err_body[:800]}")
        except Exception as e:
            raise RuntimeError(f"HTTP call failed: {e}")

        dt_ms = int((time.time() - t0) * 1000)
        meta = {"http_ms": dt_ms}

        extracted = None
        for pth in self.extract_paths:
            extracted = _get_by_path(j, pth)
            if extracted is not None:
                break

        if extracted is None:
            if isinstance(j, str):
                extracted = j
            else:
                raise RuntimeError("No pude extraer texto del JSON de respuesta (extract_paths).")

        if isinstance(extracted, list):
            extracted = "\n".join([str(x) for x in extracted])

        text = _repair_mojibake(str(extracted))
        return text, meta

    def complete(
        self,
        purpose: str,
        prompt: str,
        seed: Optional[int] = None,
        **overrides: Any,
    ) -> TextResult:
        purpose = str(purpose or "text").strip()
        prompt = str(prompt or "").strip()
        if not prompt:
            raise ValueError("prompt vacÃ­o")

        params = dict(self.default_params)
        for k, v in overrides.items():
            params[k] = v

        cache_key = self._make_cache_key(purpose, prompt, seed, params)
        created_at = int(time.time())

        if self.mode == "DRY":
            if self.cache_policy != "off":
                hit = self._load_cache(cache_key)
                if hit and isinstance(hit.get("text"), str):
                    return TextResult(hit["text"], self.active_provider, self.model, self.mode, True, cache_key, int(hit.get("created_at_unix", created_at)))
            return TextResult("", self.active_provider, self.model, self.mode, False, cache_key, created_at)

        if self.mode == "REPLAY":
            hit = self._load_cache(cache_key)
            if hit and isinstance(hit.get("text"), str):
                return TextResult(hit["text"], self.active_provider, self.model, self.mode, True, cache_key, int(hit.get("created_at_unix", created_at)))
            if self.replay_strict:
                raise RuntimeError(f"REPLAY strict: no existe cache para key {cache_key}")
            self.mode = "LIVE"

        if self.cache_policy != "off" and self.cache_policy != "refresh":
            hit = self._load_cache(cache_key)
            if hit and isinstance(hit.get("text"), str):
                return TextResult(hit["text"], self.active_provider, self.model, self.mode, True, cache_key, int(hit.get("created_at_unix", created_at)))

        text, http_meta = self._http_call(prompt, params)

        record = {
            "schema": "STUDIO_TEXT_CACHE_V1",
            "created_at_unix": created_at,
            "provider": self.active_provider,
            "model": self.model,
            "mode": self.mode,
            "purpose": purpose,
            "cache_key": cache_key,
            "params": params,
            "meta": http_meta,
            "text": text,
        }
        if self.cache_policy != "off":
            self._save_cache(cache_key, record)

        return TextResult(text, self.active_provider, self.model, self.mode, False, cache_key, created_at)

