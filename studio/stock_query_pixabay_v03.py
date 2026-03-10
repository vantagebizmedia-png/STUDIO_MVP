# studio/stock_query_pixabay_v03.py
# Pixabay stock_query v03: 1 imagen por escena (determinista con cache; fallback en replay strict)

from __future__ import annotations

from typing import Dict, Any, Optional, List, Tuple
from pathlib import Path
import hashlib
import shutil
import os
import json
import urllib.parse
import urllib.request


def _stable_key(query: str, seed: int) -> str:
    s = f"pixabay|q={query}|seed={seed}".encode("utf-8")
    return hashlib.sha256(s).hexdigest()[:16]


def _ensure_dir(p: Path) -> None:
    p.mkdir(parents=True, exist_ok=True)


def _get_api_key() -> str:
    return (
        (os.environ.get("OPENAI_STUDIO_PIXABAY_API_KEY") or "").strip()
        or (os.environ.get("PIXABAY_API_KEY") or "").strip()
    )


def _pick_url_from_hit(hit: Dict[str, Any]) -> str:
    for k in ("largeImageURL", "fullHDURL", "webformatURL", "previewURL"):
        v = hit.get(k)
        if isinstance(v, str) and v.strip():
            return v.strip()
    return ""


def _pixabay_search(api_key: str, query: str, timeout_sec: int = 15) -> List[Dict[str, Any]]:
    base = "https://pixabay.com/api/"
    params = {
        "key": api_key,
        "q": query,
        "image_type": "photo",
        "safesearch": "true",
        "order": "popular",
        "per_page": "50",
    }
    url = base + "?" + urllib.parse.urlencode(params, doseq=False)

    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "STUDIO_MVP/scene_builder_v03 (urllib)",
            "Accept": "application/json",
        },
        method="GET",
    )

    with urllib.request.urlopen(req, timeout=timeout_sec) as resp:
        data = resp.read()

    obj = json.loads(data.decode("utf-8", errors="ignore"))
    hits = obj.get("hits")
    if not isinstance(hits, list):
        return []

    out: List[Dict[str, Any]] = []
    for h in hits:
        if isinstance(h, dict):
            out.append(h)
    return out


def _download(url: str, dst: Path, timeout_sec: int = 30) -> bool:
    try:
        req = urllib.request.Request(
            url,
            headers={
                "User-Agent": "STUDIO_MVP/scene_builder_v03 (urllib)",
                "Accept": "*/*",
            },
            method="GET",
        )
        with urllib.request.urlopen(req, timeout=timeout_sec) as resp:
            content = resp.read()

        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(content)
        return dst.exists() and dst.stat().st_size > 0
    except Exception:
        return False


def _find_existing_asset(out_dir: Path, cache_key: str) -> Optional[Path]:
    for ext in (".jpg", ".jpeg", ".png", ".webp"):
        p = out_dir / f"{cache_key}{ext}"
        if p.exists() and p.stat().st_size > 0:
            return p
    return None


def resolve_image_for_scene(
    *,
    pack_dir: str,
    query: str,
    seed: int,
    replay_strict: bool,
    cache: Dict[str, Any],
    placeholder_path: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Retorna:
      { "path": "<relative>", "cache_hit": bool, "provider": str, "cache_key": str }

    Reglas:
      - Si cache ya tiene key -> cache_hit True y reusa.
      - Si existe archivo físico previo para el mismo cache_key -> cache_hit True y reusa.
      - Si replay_strict y no hay cache -> fallback determinista (placeholder).
      - Si NO replay_strict:
          - con API key -> Pixabay real
          - sin key o error -> placeholder determinista
    """
    pack = Path(pack_dir)
    out_dir = pack / "assets" / "images"
    _ensure_dir(out_dir)

    q = (query or "").strip()
    if not q:
        q = "concepto abstracto"

    cache_key = _stable_key(q, int(seed))

    # 1) Cache hit en memoria
    if cache_key in cache and isinstance(cache.get(cache_key), dict) and cache[cache_key].get("path"):
        cached_rel = str(cache[cache_key]["path"]).strip()
        if cached_rel:
            cached_abs = pack / cached_rel
            if cached_abs.exists() and cached_abs.stat().st_size > 0:
                return {
                    "path": cached_rel.replace("\\", "/"),
                    "cache_hit": True,
                    "provider": cache[cache_key].get("provider", "pixabay"),
                    "cache_key": cache_key,
                }

    # 2) Cache hit en disco aunque no venga en memoria
    existing = _find_existing_asset(out_dir, cache_key)
    if existing is not None:
        rel = str(existing.relative_to(pack)).replace("\\", "/")
        provider_name = "pixabay"
        if cache_key in cache and isinstance(cache.get(cache_key), dict):
            provider_name = str(cache[cache_key].get("provider", "pixabay") or "pixabay")
        cache[cache_key] = {
            "path": rel,
            "provider": provider_name,
            "query": q,
        }
        return {
            "path": rel,
            "cache_hit": True,
            "provider": provider_name,
            "cache_key": cache_key,
        }

    # 3) Placeholder determinista
    if not placeholder_path:
        placeholder_path = str((pack / "assets" / "placeholder.jpg").resolve())

    ph = Path(placeholder_path)
    _ensure_dir(ph.parent)
    if not ph.exists():
        ph.write_bytes(b"")

    def _use_placeholder(provider_name: str) -> Dict[str, Any]:
        dst = out_dir / f"{cache_key}.jpg"
        if not dst.exists():
            shutil.copyfile(ph, dst)
        rel = str(dst.relative_to(pack)).replace("\\", "/")
        cache[cache_key] = {"path": rel, "provider": provider_name, "query": q}
        return {
            "path": rel,
            "cache_hit": False,
            "provider": provider_name,
            "cache_key": cache_key,
        }

    # 4) replay strict
    if replay_strict:
        return _use_placeholder("fallback_deterministic")

    # 5) RUN -> Pixabay real
    api_key = _get_api_key()
    if not api_key:
        return _use_placeholder("pixabay_stub_no_key")

    try:
        hits = _pixabay_search(api_key=api_key, query=q, timeout_sec=15)
        if not hits:
            return _use_placeholder("pixabay_no_hits")

        def _hit_sort_key(h: Dict[str, Any]) -> Tuple[int, str]:
            hid = h.get("id")
            if isinstance(hid, int):
                return (hid, "")
            return (2**31 - 1, json.dumps(h, sort_keys=True, ensure_ascii=True))

        hits_sorted = sorted(hits, key=_hit_sort_key)

        idx = int(seed) % len(hits_sorted) if len(hits_sorted) > 0 else 0
        hit = hits_sorted[idx]
        url = _pick_url_from_hit(hit)
        if not url:
            return _use_placeholder("pixabay_bad_hit")

        parsed = urllib.parse.urlparse(url)
        ext = Path(parsed.path).suffix.lower()
        if ext not in (".jpg", ".jpeg", ".png", ".webp"):
            ext = ".jpg"

        dst = out_dir / f"{cache_key}{ext}"
        if not dst.exists() or dst.stat().st_size <= 0:
            ok = _download(url=url, dst=dst, timeout_sec=30)
            if not ok:
                return _use_placeholder("pixabay_download_failed")

        rel = str(dst.relative_to(pack)).replace("\\", "/")
        cache[cache_key] = {
            "path": rel,
            "provider": "pixabay",
            "source_url": url,
            "hit_id": hit.get("id"),
            "query": q,
        }
        return {
            "path": rel,
            "cache_hit": False,
            "provider": "pixabay",
            "cache_key": cache_key,
        }

    except Exception:
        return _use_placeholder("pixabay_error")
