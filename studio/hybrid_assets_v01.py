import hashlib
import json
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

from studio.pixabay_engine_v01 import fetch_and_normalize


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def _load_hybrid_cfg() -> Dict[str, Any]:
    cfg = _repo_root() / "config" / "hybrid.local.json"
    if not cfg.exists():
        return {"hybrid_v1": {"enabled": False}}
    try:
        return json.loads(cfg.read_text(encoding="utf-8"))
    except Exception:
        return {"hybrid_v1": {"enabled": False}}


def _sha1(s: str) -> str:
    return hashlib.sha1(s.encode("utf-8")).hexdigest()


def _get_str(scene: Dict[str, Any], key: str) -> str:
    v = scene.get(key)
    if v is None:
        return ""
    return str(v).strip()


def _pick_scene_query(scene: Dict[str, Any], mode: str) -> str:
    """
    query_mode:
      - scene_text: script_text/text/narration/title
      - image_query: image_query (fallback script_text)
      - title: title (fallback script_text)
    """
    mode = (mode or "scene_text").strip().lower()

    if mode == "image_query":
        q = _get_str(scene, "image_query")
        if q:
            return q
        return _get_str(scene, "script_text")

    if mode == "title":
        q = _get_str(scene, "title")
        if q:
            return q
        return _get_str(scene, "script_text")

    for k in ("script_text", "text", "narration", "title"):
        q = _get_str(scene, k)
        if q:
            return q
    return ""


def _ensure_assets(scene: Dict[str, Any]) -> Dict[str, Any]:
    if "assets" not in scene or not isinstance(scene["assets"], dict):
        scene["assets"] = {}
    if "video" not in scene["assets"] or not isinstance(scene["assets"]["video"], list):
        scene["assets"]["video"] = []
    if "image" not in scene["assets"] or not isinstance(scene["assets"]["image"], list):
        scene["assets"]["image"] = []
    return scene


def _fallback_video_path() -> Optional[Path]:
    p = _repo_root() / "assets" / "fallback" / "fallback_9x16.mp4"
    return p if p.exists() else None


def _find_cached_9x16_mp4(out_dir: Path) -> Optional[Path]:
    """
    Cache-first determinista:
      - si ya hay *_9x16.mp4, usa el lexicográficamente menor (estable)
    """
    if not out_dir.exists():
        return None
    candidates = sorted([p for p in out_dir.glob("*_9x16.mp4") if p.is_file()])
    return candidates[0] if candidates else None


def apply_hybrid_assets_to_manifest(
    manifest_path: Path,
    *,
    workspace_runs_dir: Optional[Path] = None
) -> Tuple[bool, str]:
    """
    Modifica manifest_v03.json IN-PLACE:
      - Cache-first: si existe mp4 9x16 en out_dir -> úsalo, sin red
      - Si no hay cache:
          - network_mode=auto (default): intenta Pixabay
          - network_mode=off: NO usa red; va a fallback si corresponde
      - Si Pixabay falla y fallback=keep_image:
          - marca hybrid_note
          - si existe assets/fallback/fallback_9x16.mp4 -> lo agrega como video local (determinista)
    """
    cfg = (_load_hybrid_cfg().get("hybrid_v1") or {})
    enabled = bool(cfg.get("enabled", False))
    if not enabled:
        return False, "hybrid_v1 disabled"

    provider = str(cfg.get("provider") or "pixabay").strip().lower()
    if provider != "pixabay":
        return False, f"provider no soportado: {provider}"

    query_mode = str(cfg.get("query_mode") or "scene_text").strip().lower()
    fallback = str(cfg.get("fallback") or "keep_image").strip().lower()
    use_cache = bool(cfg.get("cache", True))
    network_mode = str(cfg.get("network_mode") or "auto").strip().lower()  # auto|off

    if not manifest_path.exists():
        return False, f"no existe manifest: {manifest_path}"

    obj = json.loads(manifest_path.read_text(encoding="utf-8"))
    scenes = obj.get("scenes_v03") or obj.get("scenes") or []
    if not isinstance(scenes, list) or not scenes:
        return False, "manifest sin escenas"

    if workspace_runs_dir is None:
        workspace_runs_dir = manifest_path.parent
    cache_dir = workspace_runs_dir / "_hybrid_cache" / "pixabay"
    cache_dir.mkdir(parents=True, exist_ok=True)

    fb = _fallback_video_path()

    changed = False
    injected = 0
    skipped = 0
    fallback_used = 0
    cache_hits = 0
    net_fetch = 0
    net_off = 0

    for sc in scenes:
        if not isinstance(sc, dict):
            skipped += 1
            continue

        sc = _ensure_assets(sc)

        existing = sc["assets"]["video"]
        if isinstance(existing, list) and len(existing) > 0:
            skipped += 1
            continue

        q = _pick_scene_query(sc, query_mode)

        # sin query -> fallback si aplica
        if not q:
            if fallback == "keep_image" and fb is not None:
                sc["assets"]["video"].append({
                    "provider": "local",
                    "kind": "fallback_video",
                    "query": "",
                    "cache_key": "",
                    "path": str(fb.resolve()),
                    "note": "no query; used fallback video",
                })
                fallback_used += 1
                changed = True
            else:
                skipped += 1
            continue

        key = _sha1(q)[:12]
        out_dir = cache_dir / key
        out_dir.mkdir(parents=True, exist_ok=True)

        # (1) CACHE-FIRST
        if use_cache:
            cached = _find_cached_9x16_mp4(out_dir)
            if cached is not None:
                sc["assets"]["video"].append({
                    "provider": "pixabay",
                    "kind": "stock_video",
                    "query": q,
                    "cache_key": key,
                    "path": str(cached.resolve()),
                    "pixabay_id": None,
                    "page_url": None,
                    "note": "cache-first hit",
                })
                cache_hits += 1
                injected += 1
                changed = True
                continue

        # (2) si network off -> no red, fallback
        if network_mode == "off":
            net_off += 1
            if fallback == "keep_image" and fb is not None:
                sc.setdefault("hybrid_note", "network_mode=off; used fallback")
                sc["assets"]["video"].append({
                    "provider": "local",
                    "kind": "fallback_video",
                    "query": q,
                    "cache_key": key,
                    "path": str(fb.resolve()),
                    "note": "network off; used fallback video",
                })
                fallback_used += 1
                changed = True
            else:
                sc.setdefault("hybrid_note", "network_mode=off; no fallback available")
                skipped += 1
            continue

        # (3) red habilitada -> intenta pixabay
        try:
            norm_path, hit = fetch_and_normalize(q, out_dir=out_dir)
            net_fetch += 1
            sc["assets"]["video"].append({
                "provider": "pixabay",
                "kind": "stock_video",
                "query": q,
                "cache_key": key,
                "path": str(norm_path.resolve()),
                "pixabay_id": int(hit.id) if hit else None,
                "page_url": hit.page_url if hit else None,
                "note": "network fetch",
            })
            injected += 1
            changed = True
        except Exception as e:
            if fallback == "keep_image":
                sc.setdefault("hybrid_note", f"pixabay failed: {type(e).__name__}")
                if fb is not None:
                    sc["assets"]["video"].append({
                        "provider": "local",
                        "kind": "fallback_video",
                        "query": q,
                        "cache_key": key,
                        "path": str(fb.resolve()),
                        "note": f"pixabay failed: {type(e).__name__}",
                    })
                    fallback_used += 1
                    changed = True
                else:
                    skipped += 1
                continue
            raise

    if changed:
        if "scenes_v03" in obj and isinstance(obj["scenes_v03"], list):
            obj["scenes_v03"] = scenes
        elif "scenes" in obj and isinstance(obj["scenes"], list):
            obj["scenes"] = scenes

        manifest_path.write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding="utf-8")
        return True, (
            f"hybrid injected={injected} cache_hits={cache_hits} net_fetch={net_fetch} "
            f"net_off={net_off} fallback_used={fallback_used} skipped={skipped} "
            f"cache={use_cache} query_mode={query_mode} network_mode={network_mode}"
        )

    return False, (
        f"hybrid no-op injected=0 skipped={skipped} cache={use_cache} "
        f"query_mode={query_mode} network_mode={network_mode}"
    )
