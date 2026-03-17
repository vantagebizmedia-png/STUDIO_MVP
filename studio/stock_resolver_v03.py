from __future__ import annotations

from typing import Any, Dict, Iterable, List, Optional

from studio.stock_query_pixabay_v03 import (
    resolve_image_for_scene as pixabay_resolve_image_for_scene,
    resolve_video_for_scene as pixabay_resolve_video_for_scene,
)

_ALLOWED_CAPABILITIES = {"stock_image", "stock_video"}
_DEFAULT_PROVIDER_ORDER = ("pixabay",)


def _norm_text(value: Any) -> str:
    return str(value or "").strip()


def _normalize_requested_capability(requested_capability: str) -> str:
    capability = _norm_text(requested_capability).lower()
    if capability not in _ALLOWED_CAPABILITIES:
        return "stock_image"
    return capability


def _normalize_provider_order(provider_order: Optional[Iterable[str]]) -> List[str]:
    if provider_order is None:
        return list(_DEFAULT_PROVIDER_ORDER)

    out: List[str] = []
    for item in provider_order:
        name = _norm_text(item).lower()
        if not name:
            continue
        if name not in out:
            out.append(name)

    if not out:
        return list(_DEFAULT_PROVIDER_ORDER)

    return out


def _resolve_with_pixabay(
    *,
    pack_dir: str,
    query: str,
    seed: int,
    replay_strict: bool,
    cache: Dict[str, Any],
    requested_capability: str,
    placeholder_path: Optional[str],
    lang: str,
    orientation: str,
    category: str,
    min_width: int,
    editors_choice: bool,
    used_assets: Optional[Dict[str, Any]],
) -> Dict[str, Any]:
    if requested_capability == "stock_video":
        return pixabay_resolve_video_for_scene(
            pack_dir=pack_dir,
            query=query,
            seed=seed,
            replay_strict=replay_strict,
            cache=cache,
            placeholder_path=placeholder_path,
            lang=lang,
            orientation=orientation,
            category=category,
            min_width=min_width,
            editors_choice=editors_choice,
            used_assets=used_assets,
        )

    return pixabay_resolve_image_for_scene(
        pack_dir=pack_dir,
        query=query,
        seed=seed,
        replay_strict=replay_strict,
        cache=cache,
        placeholder_path=placeholder_path,
        lang=lang,
        orientation=orientation,
        category=category,
        min_width=min_width,
        editors_choice=editors_choice,
        used_assets=used_assets,
    )


def resolve_visual_for_scene(
    *,
    pack_dir: str,
    query: str,
    seed: int,
    replay_strict: bool,
    cache: Dict[str, Any],
    requested_capability: str,
    placeholder_path: Optional[str] = None,
    lang: str = "es",
    orientation: str = "vertical",
    category: str = "",
    min_width: int = 1080,
    editors_choice: bool = False,
    used_assets: Optional[Dict[str, Any]] = None,
    provider_order: Optional[Iterable[str]] = None,
) -> Dict[str, Any]:
    capability = _normalize_requested_capability(requested_capability)
    providers = _normalize_provider_order(provider_order)

    last_error: Optional[Exception] = None

    for provider_name in providers:
        try:
            if provider_name == "pixabay":
                result = _resolve_with_pixabay(
                    pack_dir=pack_dir,
                    query=query,
                    seed=seed,
                    replay_strict=replay_strict,
                    cache=cache,
                    requested_capability=capability,
                    placeholder_path=placeholder_path,
                    lang=lang,
                    orientation=orientation,
                    category=category,
                    min_width=min_width,
                    editors_choice=editors_choice,
                    used_assets=used_assets,
                )
            else:
                raise RuntimeError(f"Provider no soportado todavía en stock_resolver_v03: {provider_name}")

            if not isinstance(result, dict):
                raise RuntimeError(f"Resolver inválido para provider {provider_name}: resultado no dict")

            provider_detail = _norm_text(result.get("provider"))
            result["provider_selected"] = provider_name
            result["provider_order_used"] = list(providers)

            if provider_detail and provider_detail != provider_name:
                result["provider_detail"] = provider_detail
            elif "provider_detail" in result:
                del result["provider_detail"]

            result["provider"] = provider_name
            return result
        except Exception as exc:
            last_error = exc

    if last_error is not None:
        raise last_error

    raise RuntimeError("No hay providers configurados para resolve_visual_for_scene")


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
    provider_order: Optional[Iterable[str]] = None,
) -> Dict[str, Any]:
    return resolve_visual_for_scene(
        pack_dir=pack_dir,
        query=query,
        seed=seed,
        replay_strict=replay_strict,
        cache=cache,
        requested_capability="stock_image",
        placeholder_path=placeholder_path,
        lang=lang,
        orientation=orientation,
        category=category,
        min_width=min_width,
        editors_choice=editors_choice,
        used_assets=used_assets,
        provider_order=provider_order,
    )


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
    provider_order: Optional[Iterable[str]] = None,
) -> Dict[str, Any]:
    return resolve_visual_for_scene(
        pack_dir=pack_dir,
        query=query,
        seed=seed,
        replay_strict=replay_strict,
        cache=cache,
        requested_capability="stock_video",
        placeholder_path=placeholder_path,
        lang=lang,
        orientation=orientation,
        category=category,
        min_width=min_width,
        editors_choice=editors_choice,
        used_assets=used_assets,
        provider_order=provider_order,
    )