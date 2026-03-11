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
    media_type: str,
    lang: str,
    orientation: str,
    category: str,
    min_width: int,
    editors_choice: bool,
) -> str:
    q = _normalize_query(query)
    s = (
        f"pixabay|media={media_type}|q={q}|seed={seed}|lang={lang}|orientation={orientation}"
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


def _pick_image_url_from_hit(hit: Dict[str, Any]) -> str:
    for k in ("largeImageURL", "fullHDURL", "webformatURL", "previewURL"):
        v = hit.get(k)
        if isinstance(v, str) and v.strip():
            return v.strip()
    return ""


def _pick_video_stream_from_hit(
    hit: Dict[str, Any],
    *,
    preferred_orientation: str = "all",
    min_width: int = 0,
) -> Tuple[str, str, int, int]:
    videos = hit.get("videos")
    if not isinstance(videos, dict):
        return ("", "", 0, 0)

    size_rank = {"medium": 0, "large": 1, "small": 2, "tiny": 3}
    candidates: List[Tuple[int, int, int, int, int, str, str]] = []

    for key in ("medium", "large", "small", "tiny"):
        item = videos.get(key)
        if not isinstance(item, dict):
            continue

        url = str(item.get("url") or "").strip()
        if not url:
            continue

        thumb = str(item.get("thumbnail") or "").strip()
        width = int(item.get("width") or 0)
        height = int(item.get("height") or 0)

        orientation_ok = True
        if preferred_orientation == "vertical" and width > 0 and height > 0:
            orientation_ok = height >= width
        elif preferred_orientation == "horizontal" and width > 0 and height > 0:
            orientation_ok = width >= height

        width_ok = width >= int(min_width or 0) if width > 0 else False

        candidates.append(
            (
                0 if orientation_ok else 1,
                0 if width_ok else 1,
                size_rank.get(key, 99),
                -width,
                -height,
                url,
                thumb,
            )
        )

    if not candidates:
        return ("", "", 0, 0)

    candidates_sorted = sorted(candidates)
    best = candidates_sorted[0]
    url = best[5]
    thumb = best[6]

    parsed = urllib.parse.urlparse(url)
    width = 0
    height = 0
    try:
        qs = urllib.parse.parse_qs(parsed.query)
        width = int((qs.get("w") or [0])[0] or 0)
        height = int((qs.get("h") or [0])[0] or 0)
    except Exception:
        width = 0
        height = 0

    if width <= 0 or height <= 0:
        for key in ("medium", "large", "small", "tiny"):
            item = videos.get(key)
            if not isinstance(item, dict):
                continue
            if str(item.get("url") or "").strip() == url:
                width = int(item.get("width") or 0)
                height = int(item.get("height") or 0)
                break

    return (url, thumb, width, height)


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


def _pixabay_image_search(
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


def _pixabay_video_search(
    api_key: str,
    query: str,
    *,
    lang: str = "es",
    category: str = "",
    min_width: int = 1080,
    editors_choice: bool = False,
    timeout_sec: int = 15,
) -> List[Dict[str, Any]]:
    base = "https://pixabay.com/api/videos/"
    params: Dict[str, str] = {
        "key": api_key,
        "q": query,
        "video_type": "all",
        "safesearch": "true",
        "order": "popular",
        "per_page": "50",
        "lang": _normalize_lang(lang),
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


def _find_existing_asset(out_dir: Path, cache_key: str, exts: Tuple[str, ...]) -> Optional[Path]:
    for ext in exts:
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
        media_type="image",
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
        source_kind = str(entry.get("source_kind") or "").strip() or (
            "fallback_image" if str(entry.get("provider") or "").startswith("fallback") else "stock_image"
        )
        return {
            "path": rel,
            "cache_hit": bool(cache_hit_value),
            "provider": str(entry.get("provider", "pixabay") or "pixabay"),
            "cache_key": cache_key_value,
            "source_url": source_url or None,
            "hit_id": hit_id,
            "media_kind": "image",
            "source_kind": source_kind,
        }

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

    existing = _find_existing_asset(out_dir, base_cache_key, (".jpg", ".jpeg", ".png", ".webp"))
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
                "source_kind": "fallback_image" if str(provider_name).startswith("fallback") else "stock_image",
            }
            return _result_from_entry(cache[base_cache_key], base_cache_key, True)

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
            "source_kind": "fallback_image",
        }

        _mark_used(rel_path=rel)

        return {
            "path": rel,
            "cache_hit": False,
            "provider": provider_name,
            "cache_key": asset_key,
            "source_url": None,
            "hit_id": None,
            "media_kind": "image",
            "source_kind": "fallback_image",
        }

    if replay_strict:
        return _use_placeholder("fallback_deterministic")

    api_key = _get_api_key()
    if not api_key:
        return _use_placeholder("pixabay_stub_no_key")

    try:
        hits = _pixabay_image_search(
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
            cand_url = _pick_image_url_from_hit(cand)
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

        existing_base = _find_existing_asset(out_dir, base_cache_key, (".jpg", ".jpeg", ".png", ".webp"))
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

        existing_asset = _find_existing_asset(out_dir, asset_key, (".jpg", ".jpeg", ".png", ".webp"))
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
                    "source_kind": "stock_image",
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
            "source_kind": "stock_image",
        }

        return _result_from_entry(cache[asset_key], asset_key, False)

    except Exception:
        return _use_placeholder("pixabay_error")


def resolve_video_for_scene(
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
    pack = Path(pack_dir)
    out_dir = pack / "assets" / "videos"
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
        media_type="video",
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
            "media_kind": "video",
            "source_kind": "stock_video",
            "thumbnail_url": str(entry.get("thumbnail_url") or "").strip() or None,
            "duration_sec": entry.get("duration_sec"),
        }

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

    existing = _find_existing_asset(out_dir, base_cache_key, (".mp4",))
    if existing is not None:
        rel = str(existing.relative_to(pack)).replace("\\", "/")
        if not _is_used(rel_path=rel):
            source_url = ""
            hit_id = None
            thumbnail_url = ""
            duration_sec = None

            if base_cache_key in cache and isinstance(cache.get(base_cache_key), dict):
                source_url = str(cache[base_cache_key].get("source_url") or "").strip()
                hit_id = cache[base_cache_key].get("hit_id")
                thumbnail_url = str(cache[base_cache_key].get("thumbnail_url") or "").strip()
                duration_sec = cache[base_cache_key].get("duration_sec")

            cache[base_cache_key] = {
                "path": rel,
                "provider": "pixabay",
                "source_url": source_url,
                "hit_id": hit_id,
                "thumbnail_url": thumbnail_url,
                "duration_sec": duration_sec,
                "query": q,
                "lang": norm_lang,
                "orientation": norm_orientation,
                "category": norm_category,
                "min_width": int(min_width),
                "editors_choice": bool(editors_choice),
                "source_kind": "stock_video",
            }
            return _result_from_entry(cache[base_cache_key], base_cache_key, True)

    if replay_strict:
        fallback = resolve_image_for_scene(
            pack_dir=pack_dir,
            query=q,
            seed=seed,
            replay_strict=True,
            cache=cache,
            placeholder_path=placeholder_path,
            lang=lang,
            orientation=orientation,
            category=category,
            min_width=min_width,
            editors_choice=editors_choice,
            used_assets=used_assets,
        )
        fallback["media_kind"] = "image"
        fallback["source_kind"] = "fallback_image"
        return fallback

    api_key = _get_api_key()
    if not api_key:
        fallback = resolve_image_for_scene(
            pack_dir=pack_dir,
            query=q,
            seed=seed,
            replay_strict=False,
            cache=cache,
            placeholder_path=placeholder_path,
            lang=lang,
            orientation=orientation,
            category=category,
            min_width=min_width,
            editors_choice=editors_choice,
            used_assets=used_assets,
        )
        fallback["media_kind"] = "image"
        fallback["source_kind"] = "stock_image" if str(fallback.get("provider") or "") == "pixabay" else "fallback_image"
        return fallback

    try:
        hits = _pixabay_video_search(
            api_key=api_key,
            query=q,
            lang=norm_lang,
            category=norm_category,
            min_width=int(min_width),
            editors_choice=bool(editors_choice),
            timeout_sec=15,
        )
        if not hits:
            fallback = resolve_image_for_scene(
                pack_dir=pack_dir,
                query=q,
                seed=seed,
                replay_strict=False,
                cache=cache,
                placeholder_path=placeholder_path,
                lang=lang,
                orientation=orientation,
                category=category,
                min_width=min_width,
                editors_choice=editors_choice,
                used_assets=used_assets,
            )
            fallback["media_kind"] = "image"
            fallback["source_kind"] = "stock_image" if str(fallback.get("provider") or "") == "pixabay" else "fallback_image"
            return fallback

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
        thumb = ""
        selected_rank = -1

        for idx_candidate, cand in enumerate(ordered_hits):
            cand_url, cand_thumb, _w, _h = _pick_video_stream_from_hit(
                cand,
                preferred_orientation=norm_orientation,
                min_width=int(min_width),
            )
            if not cand_url:
                continue

            cand_hit_id = cand.get("id")
            if _is_used(source_url=cand_url, hit_id=cand_hit_id):
                continue

            hit = cand
            url = cand_url
            thumb = cand_thumb
            selected_rank = idx_candidate
            break

        if hit is None or not url:
            fallback = resolve_image_for_scene(
                pack_dir=pack_dir,
                query=q,
                seed=seed,
                replay_strict=False,
                cache=cache,
                placeholder_path=placeholder_path,
                lang=lang,
                orientation=orientation,
                category=category,
                min_width=min_width,
                editors_choice=editors_choice,
                used_assets=used_assets,
            )
            fallback["media_kind"] = "image"
            fallback["source_kind"] = "stock_image" if str(fallback.get("provider") or "") == "pixabay" else "fallback_image"
            return fallback

        parsed = urllib.parse.urlparse(url)
        ext = Path(parsed.path).suffix.lower()
        if ext not in (".mp4",):
            ext = ".mp4"

        safe_suffix = re.sub(r"[^0-9A-Za-z_-]+", "", str(hit.get("id") or f"alt{selected_rank + 1}").strip()) or f"alt{selected_rank + 1}"
        asset_key = base_cache_key

        existing_base = _find_existing_asset(out_dir, base_cache_key, (".mp4",))
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

        existing_asset = _find_existing_asset(out_dir, asset_key, (".mp4",))
        if existing_asset is not None:
            rel = str(existing_asset.relative_to(pack)).replace("\\", "/")
            if not _is_used(rel_path=rel, source_url=url, hit_id=hit.get("id")):
                cache[asset_key] = {
                    "path": rel,
                    "provider": "pixabay",
                    "source_url": url,
                    "hit_id": hit.get("id"),
                    "thumbnail_url": thumb,
                    "duration_sec": hit.get("duration"),
                    "query": q,
                    "lang": norm_lang,
                    "orientation": norm_orientation,
                    "category": norm_category,
                    "min_width": int(min_width),
                    "editors_choice": bool(editors_choice),
                    "source_kind": "stock_video",
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
                fallback = resolve_image_for_scene(
                    pack_dir=pack_dir,
                    query=q,
                    seed=seed,
                    replay_strict=False,
                    cache=cache,
                    placeholder_path=placeholder_path,
                    lang=lang,
                    orientation=orientation,
                    category=category,
                    min_width=min_width,
                    editors_choice=editors_choice,
                    used_assets=used_assets,
                )
                fallback["media_kind"] = "image"
                fallback["source_kind"] = "stock_image" if str(fallback.get("provider") or "") == "pixabay" else "fallback_image"
                return fallback

        rel = str(dst.relative_to(pack)).replace("\\", "/")

        cache[asset_key] = {
            "path": rel,
            "provider": "pixabay",
            "source_url": url,
            "hit_id": hit.get("id"),
            "thumbnail_url": thumb,
            "duration_sec": hit.get("duration"),
            "query": q,
            "lang": norm_lang,
            "orientation": norm_orientation,
            "category": norm_category,
            "min_width": int(min_width),
            "editors_choice": bool(editors_choice),
            "source_kind": "stock_video",
        }

        return _result_from_entry(cache[asset_key], asset_key, False)

    except Exception:
        fallback = resolve_image_for_scene(
            pack_dir=pack_dir,
            query=q,
            seed=seed,
            replay_strict=False,
            cache=cache,
            placeholder_path=placeholder_path,
            lang=lang,
            orientation=orientation,
            category=category,
            min_width=min_width,
            editors_choice=editors_choice,
            used_assets=used_assets,
        )
        fallback["media_kind"] = "image"
        fallback["source_kind"] = "stock_image" if str(fallback.get("provider") or "") == "pixabay" else "fallback_image"
        return fallback
