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
    used_assets: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """
    Retorna:
      {
        "path": "<relative>",
        "cache_hit": bool,
        "provider": str,
        "cache_key": str,
        "source_url": str|None,
        "hit_id": Any|None
      }

    Reglas:
      - Reusa cache solo si ese asset NO fue usado ya por otra escena en esta corrida.
      - Bloquea reutilizar hit_id/source_url/path entre escenas del mismo manifest.
      - Si replay_strict y no hay cache útil -> fallback determinista válido.
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

    base_cache_key = _stable_key(
        q,
        int(seed),
        lang=norm_lang,
        orientation=norm_orientation,
        category=norm_category,
        min_width=int(min_width),
        editors_choice=bool(editors_choice),
    )

    def _used_bucket(name: str) -> set[str]:
        if used_assets is None:
            return set()
        bucket = used_assets.get(name)
        if isinstance(bucket, set):
            return bucket
        if isinstance(bucket, list):
            s = {str(x).strip() for x in bucket if str(x).strip()}
            used_assets[name] = s
            return s
        s = set()
        used_assets[name] = s
        return s

    def _norm_hit_id(value: Any) -> str:
        if value is None:
            return ""
        return str(value).strip()

    def _is_used(*, rel_path: str = "", source_url: str = "", hit_id: Any = None) -> bool:
        rp = str(rel_path or "").replace("\\", "/").strip()
        su = str(source_url or "").strip()
        hid = _norm_hit_id(hit_id)

        if rp and rp in _used_bucket("paths"):
            return True
        if su and su in _used_bucket("source_urls"):
            return True
        if hid and hid in _used_bucket("hit_ids"):
            return True
        return False

    def _mark_used(*, rel_path: str = "", source_url: str = "", hit_id: Any = None) -> None:
        if used_assets is None:
            return

        rp = str(rel_path or "").replace("\\", "/").strip()
        su = str(source_url or "").strip()
        hid = _norm_hit_id(hit_id)

        if rp:
            _used_bucket("paths").add(rp)
        if su:
            _used_bucket("source_urls").add(su)
        if hid:
            _used_bucket("hit_ids").add(hid)

    def _sanitize_suffix(value: Any, fallback: str) -> str:
        s = re.sub(r"[^0-9A-Za-z_-]+", "", str(value or "").strip())
        return s or fallback

    def _result_from_entry(entry: Dict[str, Any], cache_key_value: str, cache_hit_value: bool) -> Dict[str, Any]:
        rel = str(entry.get("path") or "").replace("\\", "/").strip()
        source_url = str(entry.get("source_url") or "").strip()
        hit_id = entry.get("hit_id")
        _mark_used(rel_path=rel, source_url=source_url, hit_id=hit_id)
        return {
            "path": rel,
            "cache_hit": bool(cache_hit_value),
            "provider": str(entry.get("provider", "pixabay") or "pixabay"),
            "cache_key": cache_key_value,
            "source_url": source_url or None,
            "hit_id": hit_id,
        }

    # 1) Cache hit en memoria (solo si no fue usado ya en otra escena)
    if base_cache_key in cache and isinstance(cache.get(base_cache_key), dict) and cache[base_cache_key].get("path"):
        cached_entry = dict(cache[base_cache_key])
        cached_rel = str(cached_entry.get("path") or "").strip()
        if cached_rel:
            cached_abs = pack / cached_rel
            if cached_abs.exists() and cached_abs.stat().st_size > 0:
                if not _is_used(
                    rel_path=cached_rel,
                    source_url=str(cached_entry.get("source_url") or ""),
                    hit_id=cached_entry.get("hit_id"),
                ):
                    return _result_from_entry(cached_entry, base_cache_key, True)

    # 2) Cache hit en disco aunque no venga en memoria (solo si no fue usado ya)
    existing = _find_existing_asset(out_dir, base_cache_key)
    if existing is not None:
        rel = str(existing.relative_to(pack)).replace("\\", "/")
        if not _is_used(rel_path=rel):
            provider_name = "pixabay"
            source_url = ""
            hit_id = None

            if base_cache_key in cache and isinstance(cache.get(base_cache_key), dict):
                provider_name = str(cache[base_cache_key].get("provider", "pixabay") or "pixabay")
                source_url = str(cache[base_cache_key].get("source_url") or "").strip()
                hit_id = cache[base_cache_key].get("hit_id")

            cache[base_cache_key] = {
                "path": rel,
                "provider": provider_name,
                "source_url": source_url,
                "hit_id": hit_id,
                "query": q,
                "lang": norm_lang,
                "orientation": norm_orientation,
                "category": norm_category,
                "min_width": int(min_width),
                "editors_choice": bool(editors_choice),
            }
            return _result_from_entry(cache[base_cache_key], base_cache_key, True)

    # 3) Placeholder determinista válido
    if not placeholder_path:
        placeholder_path = str((pack / "assets" / "placeholder.png").resolve())

    ph = _ensure_valid_placeholder(Path(placeholder_path))

    def _use_placeholder(provider_name: str) -> Dict[str, Any]:
        asset_key = base_cache_key
        dst = out_dir / f"{asset_key}.png"
        rel = str(dst.relative_to(pack)).replace("\\", "/")

        if _is_used(rel_path=rel):
            n = 2
            while True:
                asset_key = f"{base_cache_key}__ph{n}"
                dst = out_dir / f"{asset_key}.png"
                rel = str(dst.relative_to(pack)).replace("\\", "/")
                if not _is_used(rel_path=rel):
                    break
                n += 1

        if (not dst.exists()) or dst.stat().st_size <= 0:
            shutil.copyfile(ph, dst)

        cache[asset_key] = {
            "path": rel,
            "provider": provider_name,
            "query": q,
            "lang": norm_lang,
            "orientation": norm_orientation,
            "category": norm_category,
            "min_width": int(min_width),
            "editors_choice": bool(editors_choice),
        }

        _mark_used(rel_path=rel)

        return {
            "path": rel,
            "cache_hit": False,
            "provider": provider_name,
            "cache_key": asset_key,
            "source_url": None,
            "hit_id": None,
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
        start_idx = int(seed) % len(hits_sorted) if len(hits_sorted) > 0 else 0
        ordered_hits = hits_sorted[start_idx:] + hits_sorted[:start_idx]

        hit = None
        url = ""
        selected_rank = -1

        for idx_candidate, cand in enumerate(ordered_hits):
            cand_url = _pick_url_from_hit(cand)
            if not cand_url:
                continue

            cand_hit_id = cand.get("id")
            if _is_used(source_url=cand_url, hit_id=cand_hit_id):
                continue

            hit = cand
            url = cand_url
            selected_rank = idx_candidate
            break

        if hit is None or not url:
            return _use_placeholder("pixabay_all_hits_used")

        parsed = urllib.parse.urlparse(url)
        ext = Path(parsed.path).suffix.lower()
        if ext not in (".jpg", ".jpeg", ".png", ".webp"):
            ext = ".jpg"

        safe_suffix = _sanitize_suffix(hit.get("id"), f"alt{selected_rank + 1}")
        asset_key = base_cache_key

        existing_base = _find_existing_asset(out_dir, base_cache_key)
        base_entry = cache.get(base_cache_key) if isinstance(cache.get(base_cache_key), dict) else None

        if existing_base is not None or base_entry is not None:
            same_as_base = False
            if base_entry is not None:
                base_url = str(base_entry.get("source_url") or "").strip()
                base_hit_id = _norm_hit_id(base_entry.get("hit_id"))
                curr_hit_id = _norm_hit_id(hit.get("id"))
                same_as_base = bool(
                    (base_url and base_url == url)
                    or (base_hit_id and curr_hit_id and base_hit_id == curr_hit_id)
                )

            if not same_as_base:
                asset_key = f"{base_cache_key}__{safe_suffix}"

        existing_asset = _find_existing_asset(out_dir, asset_key)
        if existing_asset is not None:
            rel = str(existing_asset.relative_to(pack)).replace("\\", "/")
            if not _is_used(rel_path=rel, source_url=url, hit_id=hit.get("id")):
                cache[asset_key] = {
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
                return _result_from_entry(cache[asset_key], asset_key, True)

        dst = out_dir / f"{asset_key}{ext}"

        if dst.exists() and dst.stat().st_size <= 0:
            dst.unlink()

        if not dst.exists():
            ok = _download(url=url, dst=dst, timeout_sec=30)
            if (not ok) or (not dst.exists()) or dst.stat().st_size <= 0:
                if dst.exists():
                    dst.unlink()
                return _use_placeholder("pixabay_download_failed")

        rel = str(dst.relative_to(pack)).replace("\\", "/")

        cache[asset_key] = {
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

        return _result_from_entry(cache[asset_key], asset_key, False)

    except Exception:
        return _use_placeholder("pixabay_error")


