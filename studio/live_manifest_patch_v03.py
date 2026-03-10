# studio/live_manifest_patch_v03.py
# Fuente de verdad v03:
# - si ya existe manifest["scenes"] legacy bien armado, derivar scenes_v03 desde ahí
# - si no existe, usar build_scenes_v03(script_text, ...)
# - resolver 1 imagen por escena con cache determinista
# - preservar compatibilidad

from __future__ import annotations

from typing import Dict, Any, List
from studio.scene_builder_v03 import build_scenes_v03
from studio.stock_query_pixabay_v03 import resolve_image_for_scene


def _safe_int(x: Any, default: int = 0) -> int:
    try:
        return int(x)
    except Exception:
        return default


def _norm_text(x: Any) -> str:
    return str(x or "").strip()


def _extract_total_ms(manifest: Dict[str, Any]) -> int:
    total_ms = 0

    sb = manifest.get("scene_builder_v03")
    if isinstance(sb, dict):
        total_ms = _safe_int(sb.get("total_audio_ms"), 0)

    if total_ms <= 0:
        audio = manifest.get("audio")
        if isinstance(audio, dict):
            total_ms = _safe_int(audio.get("duration_ms"), 0)

    if total_ms <= 0:
        total_ms = _safe_int(manifest.get("audio_duration_ms"), 0)

    return max(0, total_ms)


def _build_from_legacy_scenes(manifest: Dict[str, Any], total_ms: int) -> List[Dict[str, Any]]:
    legacy = manifest.get("scenes")
    if not isinstance(legacy, list) or len(legacy) == 0:
        return []

    rows = [dict(x or {}) for x in legacy if isinstance(x, dict)]
    if not rows:
        return []

    n = len(rows)
    if total_ms <= 0:
        total_ms = n * 2000

    base = total_ms // n
    rem = total_ms - (base * n)

    out: List[Dict[str, Any]] = []
    cur = 0

    for i, sc in enumerate(rows):
        dur = base + (1 if i < rem else 0)
        start_ms = cur
        end_ms = cur + dur
        cur = end_ms

        narration = _norm_text(sc.get("narration"))
        onscreen = _norm_text(sc.get("onscreen"))
        stock_query = _norm_text(sc.get("stock_query"))

        arts = sc.get("artifacts") or {}
        if not isinstance(arts, dict):
            arts = {}

        audio_rel = _norm_text(arts.get("audio"))
        image_rel = _norm_text(arts.get("image"))

        scene_text = narration or onscreen or stock_query or f"Escena {i+1:02d}"
        image_query = stock_query or narration or onscreen or "concepto abstracto"

        out.append(
            {
                "id": f"s{i+1:02d}",
                "index": i,
                "start_ms": int(start_ms),
                "end_ms": int(end_ms),
                "duration_ms": int(max(0, end_ms - start_ms)),
                "script_text": scene_text,
                "image_query": image_query,
                "assets": {
                    "image": image_rel or None,
                    "audio_clip": audio_rel or None,
                },
            }
        )

    if out:
        out[-1]["end_ms"] = int(total_ms)
        out[-1]["duration_ms"] = int(max(0, total_ms - _safe_int(out[-1]["start_ms"], 0)))

    return out


def apply_scene_builder_to_manifest(
    manifest: Dict[str, Any],
    *,
    pack_dir: str,
    max_scenes: int,
) -> Dict[str, Any]:
    """
    Modifica manifest in-place y retorna:
      - manifest["scenes_v03"] = [...]  (fuente de verdad v0.3)
      - manifest["scenes"] se preserva
      - manifest["stock_cache"] determinista
      - por escena: assets.image + assets.image_meta
    """

    script_text = (
        manifest.get("script_text")
        or manifest.get("script")
        or manifest.get("text")
        or ""
    )

    total_ms = _extract_total_ms(manifest)

    replay_strict = bool(manifest.get("replay_strict") or False)
    tg = manifest.get("text_generation")
    if isinstance(tg, dict) and "replay_strict" in tg:
        replay_strict = bool(tg.get("replay_strict"))

    seed = _safe_int(manifest.get("seed"), 0)

    stock_cache = manifest.get("stock_cache")
    if not isinstance(stock_cache, dict):
        stock_cache = {}
        manifest["stock_cache"] = stock_cache

    # PRIORIDAD 1: derivar desde scenes legacy ya bien construidas
    scenes = _build_from_legacy_scenes(manifest, total_ms)

    # PRIORIDAD 2: fallback al builder textual
    if not scenes:
        scenes = build_scenes_v03(
            script_text=str(script_text or ""),
            max_scenes=int(max_scenes or 1),
            total_audio_ms=int(total_ms or 0),
        )

    for sc in scenes:
        q = _norm_text(sc.get("image_query")) or "concepto abstracto"
        r = resolve_image_for_scene(
            pack_dir=pack_dir,
            query=q,
            seed=seed,
            replay_strict=replay_strict,
            cache=stock_cache,
            placeholder_path=None,
        )

        assets = sc.get("assets")
        if not isinstance(assets, dict):
            assets = {}
            sc["assets"] = assets

        assets["image"] = r["path"]
        assets["image_meta"] = {
            "provider": r["provider"],
            "cache_hit": r["cache_hit"],
            "cache_key": r["cache_key"],
            "query": q,
        }

    manifest["scenes_v03"] = scenes
    manifest["scene_builder_v03"] = {
        "max_scenes": len(scenes),
        "total_audio_ms": int(total_ms),
        "note": "generated by live_manifest_patch_v03 using legacy scenes as priority source",
    }

    if "scenes" not in manifest or not isinstance(manifest.get("scenes"), list):
        manifest["scenes"] = scenes

    return manifest
