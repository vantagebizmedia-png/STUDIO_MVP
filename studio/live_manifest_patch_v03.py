# studio/live_manifest_patch_v03.py
# Inserta scenes[] y resuelve 1 imagen por escena

from __future__ import annotations

from typing import Dict, Any
from studio.scene_builder_v03 import build_scenes_v03
from studio.stock_query_pixabay_v03 import resolve_image_for_scene


def apply_scene_builder_to_manifest(
    manifest: Dict[str, Any],
    *,
    pack_dir: str,
    max_scenes: int,
) -> Dict[str, Any]:
    """
    Modifica manifest in-place (y lo retorna):
      - manifest["scenes"] = [...]
      - manifest["stock_cache"] para determinismo
      - por escena: assets.image y assets.image_meta

    Inputs esperados (usa fallback si faltan):
      - script/script_text/text
      - audio.duration_ms o audio_duration_ms
      - seed
      - replay_strict o text_generation.replay_strict
    """
    script_text = (
        manifest.get("script")
        or manifest.get("script_text")
        or manifest.get("text", "")
    )

    total_ms = 0
    if isinstance(manifest.get("audio"), dict) and "duration_ms" in manifest["audio"]:
        total_ms = int(manifest["audio"]["duration_ms"] or 0)
    else:
        total_ms = int(manifest.get("audio_duration_ms") or 0)

    replay_strict = bool(manifest.get("replay_strict") or False)
    tg = manifest.get("text_generation")
    if isinstance(tg, dict) and "replay_strict" in tg:
        replay_strict = bool(tg.get("replay_strict"))

    seed = int(manifest.get("seed") or 0)

    scenes = build_scenes_v03(
        script_text=script_text,
        max_scenes=max_scenes,
        total_audio_ms=total_ms,
    )

    stock_cache = manifest.get("stock_cache")
    if not isinstance(stock_cache, dict):
        stock_cache = {}
        manifest["stock_cache"] = stock_cache

    for sc in scenes:
        q = sc.get("image_query") or ""
        r = resolve_image_for_scene(
            pack_dir=pack_dir,
            query=q,
            seed=seed,
            replay_strict=replay_strict,
            cache=stock_cache,
            placeholder_path=None,
        )
        sc["assets"]["image"] = r["path"]
        sc["assets"]["image_meta"] = {
            "provider": r["provider"],
            "cache_hit": r["cache_hit"],
            "cache_key": r["cache_key"],
            "query": q,
        }

    manifest["scenes"] = scenes
    return manifest
