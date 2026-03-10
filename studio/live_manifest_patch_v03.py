# studio/live_manifest_patch_v03.py
# Fuente de verdad v03:
# - si ya existe manifest["scenes"] legacy bien armado, derivar scenes_v03 desde ahí
# - si no existe, usar build_scenes_v03(script_text, ...)
# - resolver 1 imagen por escena con cache determinista
# - preservar compatibilidad
# - sanear visual queries para Pixabay
# - enriquecer contexto visual con orientation/category/lang

from __future__ import annotations

from typing import Dict, Any, List
import re

from studio.scene_builder_v03 import build_scenes_v03
from studio.stock_query_pixabay_v03 import resolve_image_for_scene


_STOPWORDS = {
    "a","al","con","de","del","el","en","la","las","lo","los","para","por","sin","un","una","unos","unas","y","o",
    "the","and","with","without","for","from","of","in","on","at","to"
}

_ABSTRACT = {
    "disciplina","motivacion","motivación","habito","habitos","hábito","hábitos","constancia","enfoque","claridad",
    "mejora","progreso","resultado","objetivo","objetivos","meta","metas","cambio","crecimiento","avance",
    "mentalidad","mindset","idea","ideas","estrategia","estrategias","proceso","valor","valores"
}

_VISUAL_ANCHORS = (
    "persona escritorio agenda",
    "persona trabajando laptop",
    "persona oficina fondo neutro",
    "persona manos cuaderno",
    "persona celebrando logro"
)


def _safe_int(x: Any, default: int = 0) -> int:
    try:
        return int(x)
    except Exception:
        return default


def _norm_text(x: Any) -> str:
    return str(x or "").strip()


def _tokenize_visual(text: str) -> List[str]:
    t = str(text or "").strip().lower()
    t = re.sub(r"[^\w\sáéíóúüñ-]", " ", t, flags=re.IGNORECASE)
    t = t.replace("_", " ")
    t = re.sub(r"\s+", " ", t).strip()
    if not t:
        return []
    out: List[str] = []
    for w in t.split(" "):
        w = w.strip("- ").strip()
        if not w:
            continue
        if len(w) < 3:
            continue
        out.append(w)
    return out


def _clean_visual_query(*values: Any) -> str:
    tokens: List[str] = []

    for value in values:
        s = _norm_text(value)
        if not s:
            continue

        s = re.sub(r"\b(escena|narracion|narración|onscreen|stock_query)\b[: ]*", " ", s, flags=re.IGNORECASE)
        s = re.sub(r"\s+", " ", s).strip()

        for w in _tokenize_visual(s):
            if w in _STOPWORDS:
                continue
            if w not in tokens:
                tokens.append(w)

    while tokens and tokens[-1] in _STOPWORDS:
        tokens.pop()

    if not tokens:
        return "persona escritorio"

    concrete = [w for w in tokens if w not in _ABSTRACT]

    if len(concrete) >= 2:
        tokens = concrete

    tokens = tokens[:6]

    q = " ".join(tokens).strip()

    if not q:
        return "persona escritorio"

    if len(tokens) == 1:
        if tokens[0] in {"camara", "cámara", "rostro", "cara"}:
            return "persona camara"
        if tokens[0] in {"oficina", "escritorio", "laptop", "computadora"}:
            return "persona escritorio"
        return f"persona {tokens[0]}".strip()

    if all(t in _ABSTRACT for t in tokens):
        return _VISUAL_ANCHORS[0]

    return q


def _infer_pixabay_context(scene_text: str, image_query: str, scene_index: int) -> Dict[str, Any]:
    text = f"{_norm_text(scene_text)} {_norm_text(image_query)}".lower()

    lang = "es"
    orientation = "vertical"
    min_width = 1080
    editors_choice = False
    category = "people"

    if any(x in text for x in ("oficina", "escritorio", "laptop", "computadora", "agenda", "rutina", "productividad")):
        category = "business"

    elif any(x in text for x in ("salud", "bienestar", "ejercicio", "gym", "gimnasio", "pesas")):
        category = "health"

    elif any(x in text for x in ("comida", "cocina", "desayuno", "almuerzo", "cena", "receta")):
        category = "food"

    elif any(x in text for x in ("viaje", "aeropuerto", "maleta", "vacaciones", "turismo")):
        category = "travel"

    elif any(x in text for x in ("familia", "pareja", "amigos", "equipo", "reunion", "reunión")):
        category = "people"

    elif any(x in text for x in ("deporte", "correr", "pesas", "entrenamiento")):
        category = "sports"

    if any(x in text for x in ("celebra", "celebrando", "logro", "logros", "trofeo", "éxito", "exito")):
        editors_choice = True

    # ligero patrón determinista para diversificar sin romper baseline
    if ((int(scene_index) % 4) == 0) and category in {"people", "business"}:
        editors_choice = True

    return {
        "lang": lang,
        "orientation": orientation,
        "category": category,
        "min_width": int(min_width),
        "editors_choice": bool(editors_choice),
    }


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
        image_query = _clean_visual_query(stock_query, narration, onscreen)

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
            sc["image_query"] = _clean_visual_query(sc.get("image_query"), sc.get("script_text"))

    for sc in scenes:
        q = _clean_visual_query(sc.get("image_query"), sc.get("script_text")) or "persona escritorio"
        sc["image_query"] = q

        ctx = _infer_pixabay_context(
            scene_text=_norm_text(sc.get("script_text")),
            image_query=q,
            scene_index=_safe_int(sc.get("index"), 0),
        )

        r = resolve_image_for_scene(
            pack_dir=pack_dir,
            query=q,
            seed=seed,
            replay_strict=replay_strict,
            cache=stock_cache,
            placeholder_path=None,
            lang=str(ctx["lang"]),
            orientation=str(ctx["orientation"]),
            category=str(ctx["category"]),
            min_width=int(ctx["min_width"]),
            editors_choice=bool(ctx["editors_choice"]),
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
            "lang": str(ctx["lang"]),
            "orientation": str(ctx["orientation"]),
            "category": str(ctx["category"]),
            "min_width": int(ctx["min_width"]),
            "editors_choice": bool(ctx["editors_choice"]),
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
