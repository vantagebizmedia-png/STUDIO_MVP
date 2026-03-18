from __future__ import annotations

from typing import Any, Callable, Dict, Iterable, List, Optional

from studio.stock_query_pixabay_v03 import (
    resolve_image_for_scene as pixabay_resolve_image_for_scene,
    resolve_video_for_scene as pixabay_resolve_video_for_scene,
)

ProviderResolver = Callable[..., Dict[str, Any]]

_ALLOWED_CAPABILITIES = {"stock_image", "stock_video"}
_ALLOWED_MEDIA_KINDS = {"image", "video"}
_DEFAULT_PROVIDER_ORDER = ("pixabay",)


def _norm_text(value: Any) -> str:
    return str(value or "").strip()


def _normalize_provider_name(value: Any) -> str:
    return _norm_text(value).lower()


def _normalize_capability_name(value: Any) -> str:
    capability = _norm_text(value).lower()
    if capability in _ALLOWED_CAPABILITIES:
        return capability
    return ""


def _normalize_media_kind(value: Any) -> str:
    media_kind = _norm_text(value).lower()
    if media_kind in _ALLOWED_MEDIA_KINDS:
        return media_kind
    return ""


def _normalize_requested_capability(requested_capability: str) -> str:
    capability = _normalize_capability_name(requested_capability)
    if not capability:
        return "stock_image"
    return capability


def _normalize_provider_order(provider_order: Optional[Iterable[str]]) -> List[str]:
    if provider_order is None:
        return list(_DEFAULT_PROVIDER_ORDER)

    out: List[str] = []
    for item in provider_order:
        name = _normalize_provider_name(item)
        if not name:
            continue
        if name not in out:
            out.append(name)

    if not out:
        return list(_DEFAULT_PROVIDER_ORDER)

    return out


def _default_media_kind_for_capability(requested_capability: str) -> str:
    return "video" if requested_capability == "stock_video" else "image"


def _default_source_kind_for_media_kind(media_kind: str) -> str:
    return "stock_video" if media_kind == "video" else "stock_image"


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


_PROVIDER_REGISTRY: Dict[str, Dict[str, Any]] = {
    "pixabay": {
        "resolver": _resolve_with_pixabay,
        "capabilities": frozenset(_ALLOWED_CAPABILITIES),
        "enabled": True,
    },
}


def _get_provider_spec(provider_name: str) -> Dict[str, Any]:
    spec = _PROVIDER_REGISTRY.get(provider_name)
    if spec is None:
        raise RuntimeError(f"Provider no soportado todavía en stock_resolver_v03: {provider_name}")

    if not bool(spec.get("enabled", False)):
        raise RuntimeError(f"Provider deshabilitado en stock_resolver_v03: {provider_name}")

    resolver = spec.get("resolver")
    if not callable(resolver):
        raise RuntimeError(f"Resolver inválido para provider {provider_name}: resolver no callable")

    raw_capabilities = spec.get("capabilities")
    if not isinstance(raw_capabilities, (set, frozenset, tuple, list)):
        raise RuntimeError(f"Resolver inválido para provider {provider_name}: capabilities inválidas")

    capabilities = {
        normalized
        for normalized in (_normalize_capability_name(item) for item in raw_capabilities)
        if normalized
    }
    if not capabilities:
        raise RuntimeError(f"Resolver inválido para provider {provider_name}: capabilities vacías")

    return {
        "resolver": resolver,
        "capabilities": capabilities,
    }


def _resolve_single_provider(
    *,
    provider_name: str,
    requested_capability: str,
    pack_dir: str,
    query: str,
    seed: int,
    replay_strict: bool,
    cache: Dict[str, Any],
    placeholder_path: Optional[str],
    lang: str,
    orientation: str,
    category: str,
    min_width: int,
    editors_choice: bool,
    used_assets: Optional[Dict[str, Any]],
) -> Dict[str, Any]:
    spec = _get_provider_spec(provider_name)
    capabilities = spec["capabilities"]
    resolver = spec["resolver"]

    if requested_capability not in capabilities:
        raise RuntimeError(
            f"Provider {provider_name} no soporta capability {requested_capability}"
        )

    result = resolver(
        pack_dir=pack_dir,
        query=query,
        seed=seed,
        replay_strict=replay_strict,
        cache=cache,
        requested_capability=requested_capability,
        placeholder_path=placeholder_path,
        lang=lang,
        orientation=orientation,
        category=category,
        min_width=min_width,
        editors_choice=editors_choice,
        used_assets=used_assets,
    )

    if not isinstance(result, dict):
        raise RuntimeError(f"Resolver inválido para provider {provider_name}: resultado no dict")

    return result


def _validate_provider_result(
    *,
    provider_name: str,
    requested_capability: str,
    result: Dict[str, Any],
) -> None:
    path_value = _norm_text(result.get("path")).replace("\\", "/")
    if not path_value:
        raise RuntimeError(f"Resolver inválido para provider {provider_name}: path vacío")

    cache_key_value = _norm_text(result.get("cache_key"))
    if not cache_key_value:
        raise RuntimeError(f"Resolver inválido para provider {provider_name}: cache_key vacío")

    if "cache_hit" not in result:
        raise RuntimeError(f"Resolver inválido para provider {provider_name}: falta cache_hit")

    media_kind = _normalize_media_kind(result.get("media_kind"))
    if not media_kind:
        raise RuntimeError(f"Resolver inválido para provider {provider_name}: media_kind inválido")

    source_kind = _norm_text(result.get("source_kind")).lower()
    if not source_kind:
        raise RuntimeError(f"Resolver inválido para provider {provider_name}: source_kind vacío")

    expected_default_media_kind = _default_media_kind_for_capability(requested_capability)
    if media_kind not in {"image", "video"}:
        raise RuntimeError(
            f"Resolver inválido para provider {provider_name}: media_kind no permitido "
            f"(esperado {expected_default_media_kind} o fallback compatible)"
        )


def _finalize_provider_result(
    *,
    provider_name: str,
    provider_order_used: Iterable[str],
    requested_capability: str,
    result: Dict[str, Any],
) -> Dict[str, Any]:
    finalized = dict(result)

    raw_provider = _normalize_provider_name(finalized.get("provider"))
    provider_detail = raw_provider if raw_provider and raw_provider != provider_name else ""

    media_kind = _normalize_media_kind(finalized.get("media_kind"))
    if not media_kind:
        media_kind = _default_media_kind_for_capability(requested_capability)

    source_kind = _norm_text(finalized.get("source_kind")).lower()
    if not source_kind:
        source_kind = _default_source_kind_for_media_kind(media_kind)

    finalized["path"] = _norm_text(finalized.get("path")).replace("\\", "/")
    finalized["cache_hit"] = bool(finalized.get("cache_hit"))
    finalized["cache_key"] = _norm_text(finalized.get("cache_key"))
    finalized["media_kind"] = media_kind
    finalized["source_kind"] = source_kind

    finalized["provider"] = provider_name
    finalized["provider_selected"] = provider_name
    finalized["provider_order_used"] = list(provider_order_used)

    if "source_url" in finalized and not _norm_text(finalized.get("source_url")):
        finalized["source_url"] = None

    if "thumbnail_url" in finalized and not _norm_text(finalized.get("thumbnail_url")):
        finalized["thumbnail_url"] = None

    fallback_reason = _norm_text(finalized.get("fallback_reason"))
    if fallback_reason:
        finalized["fallback_reason"] = fallback_reason
    elif "fallback_reason" in finalized:
        del finalized["fallback_reason"]

    if provider_detail:
        finalized["provider_detail"] = provider_detail
    elif "provider_detail" in finalized:
        del finalized["provider_detail"]

    return finalized


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
            raw_result = _resolve_single_provider(
                provider_name=provider_name,
                requested_capability=capability,
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

            _validate_provider_result(
                provider_name=provider_name,
                requested_capability=capability,
                result=raw_result,
            )

            return _finalize_provider_result(
                provider_name=provider_name,
                provider_order_used=providers,
                requested_capability=capability,
                result=raw_result,
            )
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