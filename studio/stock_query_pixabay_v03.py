# studio/stock_query_pixabay_v03.py
# Pixabay stock_query v03: 1 imagen por escena (determinista con cache; fallback en replay strict)

from __future__ import annotations

from typing import Dict, Any, Optional, List, Tuple
from pathlib import Path
import hashlib
import shutil
import os
import json
import re
import base64
import urllib.parse
import urllib.request


_STOPWORDS = {
    "a","al","con","de","del","el","en","la","las","lo","los","para","por","sin","un","una","unos","unas","y","o",
    "the","and","with","without","for","from","of","in","on","at","to"
}

# PNG válido 1x1 transparente
_FALLBACK_PNG_1X1 = base64.b64decode(
    b"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+X2dAAAAAASUVORK5CYII="
)


def _normalize_query(query: str) -> str:
    q = str(query or "").strip().lower()
    q = re.sub(r"[^\w\sáéíóúüñ-]", " ", q, flags=re.IGNORECASE)
    q = q.replace("_", " ")
    q = re.sub(r"\s+", " ", q).strip()

    if not q:
        return "persona escritorio"

    tokens: List[str] = []
    for w in q.split(" "):
        w = w.strip("- ").strip()
        if not w:
            continue
        if len(w) < 3:
            continue
        if w in _STOPWORDS:
            continue
        if w not in tokens:
            tokens.append(w)

    if not tokens:
        return "persona escritorio"

    tokens = tokens[:6]
    out = " ".join(tokens).strip()
    return out[:100].strip() or "persona escritorio"


def _stable_key(
    query: str,
    seed: int,
    *,
    lang: str,
    orientation: str,
    category: str,
    min_width: int,
    editors_choice: bool,
) -> str:
    q = _normalize_query(query)
    s = (
        f"pixabay|q={q}|seed={seed}|lang={lang}|orientation={orientation}"
        f"|category={category}|min_width={int(min_width)}|editors_choice={bool(editors_choice)}"
    ).encode("utf-8")
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


def _normalize_lang(lang: str) -> str:
    lang = str(lang or "").strip().lower()
    allowed = {
        "cs","da","de","en","es","fr","id","it","hu","nl","no","pl","pt","ro",
        "sk","fi","sv","tr","vi","th","bg","ru","el","ja","ko","zh"
    }
    if lang in allowed:
        return lang
    return "es"


def _normalize_orientation(orientation: str) -> str:
    orientation = str(orientation or "").strip().lower()
    if orientation in {"all", "horizontal", "vertical"}:
        return orientation
    return "vertical"


def _normalize_category(category: str) -> str:
    category = str(category or "").strip().lower()
    allowed = {
        "backgrounds","fashion","nature","science","education","feelings","health","people",
        "religion","places","animals","industry","computer","food","sports","transportation",
        "travel","buildings","business","music"
    }
    if category in allowed:
        return category
    return ""


def _pixabay_search(
    api_key: str,
    query: str,
    *,
    lang: str = "es",
    orientation: str = "vertical",
    category: str = "",
    min_width: int = 1080,
    editors_choice: bool = False,
    timeout_sec: int = 15,
) -> List[Dict[str, Any]]:
    base = "https://pixabay.com/api/"
    params: Dict[str, str] = {
        "key": api_key,
        "q": query,
        "image_type": "photo",
        "safesearch": "true",
        "order": "popular",
        "per_page": "50",
        "lang": _normalize_lang(lang),
        "orientation": _normalize_orientation(orientation),
        "min_width": str(max(0, int(min_width))),
        "editors_choice": "true" if bool(editors_choice) else "false",
    }

    cat = _normalize_category(category)
    if cat:
        params["category"] = cat

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


def _ensure_valid_placeholder(path: Path) -> Path:
    _ensure_dir(path.parent)
    if (not path.exists()) or path.stat().st_size <= 0:
        path.write_bytes(_FALLBACK_PNG_1X1)
    return path


def resolve_image_for_scene(
    *,
    pack_dir: str,
    query: str,
    seed: int,
    replay_strict: bool,
    cache: Dict[str, Any],
    placeholder_path: Optional[str] = None,
    lang: str = "es",
    orientation: str = "vertical",
    category: str = "",
    min_width: int = 1080,
    editors_choice: bool = False,
) -> Dict[str, Any]:
    """
    Retorna:
      { "path": "<relative>", "cache_hit": bool, "provider": str, "cache_key": str }

    Reglas:
      - Si cache ya tiene key -> cache_hit True y reusa.
      - Si existe archivo físico previo para el mismo cache_key -> cache_hit True y reusa.
      - Si replay_strict y no hay cache -> fallback determinista (placeholder válido).
      - Si NO replay_strict:
          - con API key -> Pixabay real
          - sin key o error -> placeholder determinista válido
    """
    pack = Path(pack_dir)
    out_dir = pack / "assets" / "images"
    _ensure_dir(out_dir)

    q = _normalize_query(query)
    if not q:
        q = "persona escritorio"

    norm_lang = _normalize_lang(lang)
    norm_orientation = _normalize_orientation(orientation)
    norm_category = _normalize_category(category)

    cache_key = _stable_key(
        q,
        int(seed),
        lang=norm_lang,
        orientation=norm_orientation,
        category=norm_category,
        min_width=int(min_width),
        editors_choice=bool(editors_choice),
    )

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
            "lang": norm_lang,
            "orientation": norm_orientation,
            "category": norm_category,
            "min_width": int(min_width),
            "editors_choice": bool(editors_choice),
        }
        return {
            "path": rel,
            "cache_hit": True,
            "provider": provider_name,
            "cache_key": cache_key,
        }

    # 3) Placeholder determinista válido
    if not placeholder_path:
        placeholder_path = str((pack / "assets" / "placeholder.png").resolve())

    ph = _ensure_valid_placeholder(Path(placeholder_path))

    def _use_placeholder(provider_name: str) -> Dict[str, Any]:
        dst = out_dir / f"{cache_key}.png"
        if (not dst.exists()) or dst.stat().st_size <= 0:
            shutil.copyfile(ph, dst)
        rel = str(dst.relative_to(pack)).replace("\\", "/")
        cache[cache_key] = {
            "path": rel,
            "provider": provider_name,
            "query": q,
            "lang": norm_lang,
            "orientation": norm_orientation,
            "category": norm_category,
            "min_width": int(min_width),
            "editors_choice": bool(editors_choice),
        }
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
        hits = _pixabay_search(
            api_key=api_key,
            query=q,
            lang=norm_lang,
            orientation=norm_orientation,
            category=norm_category,
            min_width=int(min_width),
            editors_choice=bool(editors_choice),
            timeout_sec=15,
        )
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

        if dst.exists() and dst.stat().st_size <= 0:
            dst.unlink()

        if not dst.exists():
            ok = _download(url=url, dst=dst, timeout_sec=30)
            if (not ok) or (not dst.exists()) or dst.stat().st_size <= 0:
                if dst.exists():
                    dst.unlink()
                return _use_placeholder("pixabay_download_failed")

        rel = str(dst.relative_to(pack)).replace("\\", "/")
        cache[cache_key] = {
            "path": rel,
            "provider": "pixabay",
            "source_url": url,
            "hit_id": hit.get("id"),
            "query": q,
            "lang": norm_lang,
            "orientation": norm_orientation,
            "category": norm_category,
            "min_width": int(min_width),
            "editors_choice": bool(editors_choice),
        }
        return {
            "path": rel,
            "cache_hit": False,
            "provider": "pixabay",
            "cache_key": cache_key,
        }

    except Exception:
        return _use_placeholder("pixabay_error")
