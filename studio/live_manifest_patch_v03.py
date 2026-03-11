# studio/live_manifest_patch_v03.py
# Fuente de verdad v03:
# - si ya existe manifest["scenes"] legacy bien armado, derivar scenes_v03 desde ahí
# - si no existe, usar build_scenes_v03(script_text, ...)
# - resolver 1 imagen por escena con cache determinista
# - preservar compatibilidad
# - sanear visual queries para Pixabay
# - enriquecer contexto visual con orientation/category/lang
# - generar queries por intención visual controlada

from __future__ import annotations

from typing import Dict, Any, List
import re

from studio.scene_builder_v03 import build_scenes_v03
from studio.stock_query_pixabay_v03 import resolve_image_for_scene, resolve_video_for_scene

_STOPWORDS = {
    "a","al","con","de","del","el","en","la","las","lo","los","para","por","sin","un","una","unos","unas","y","o",
    "the","and","with","without","for","from","of","in","on","at","to"
}

_ABSTRACT = {
    "disciplina","motivacion","motivación","habito","habitos","hábito","hábitos","constancia","enfoque","claridad",
    "mejora","progreso","resultado","objetivo","objetivos","meta","metas","cambio","crecimiento","avance",
    "mentalidad","mindset","idea","ideas","estrategia","estrategias","proceso","valor","valores","transformar",
    "transformarán","transformara","vida","lograrlo","ayudaran","ayudarán","comparto","comparto","quieres"
}

_HOOK_TERMS = {
    "quieres","quieres?","quieresser","transforma","transformarán","transformara","cambiar","cambio","mejorar",
    "mejora","vida","hoy","ahora","aqui","aquí","tres","habitos","hábitos","disciplina"
}

_ROUTINE_TERMS = {
    "rutina","rutinas","diaria","diarias","agenda","horario","horarios","plan","planes","planifica","planificar",
    "organiza","organizar","calendario","lista","listas","tiempo","bloque","bloques","prioridad","prioridades",
    "actividad","actividades","dedica","dedicar","establece","establecer"
}

_FOCUS_TERMS = {
    "distraccion","distracciones","enfoque","concentracion","concentración","interrupciones",
    "silencio","ordenado","orden","limpio","ambiente","motiva","motive","enfocarte"
}

_NOTES_TERMS = {
    "nota","notas","postit","post-it","recordatorio","recordatorios","papel","papeles","pared","visual","visuales"
}

_SOCIAL_TERMS = {
    "grupo","equipo","amigos","amigo","reunion","reunión","acompañado","acompanado",
    "influencia","positiva","rodeate","rodéate","juntos"
}

_SELF_DISCIPLINE_TERMS = {
    "autodisciplina","disciplina","desafio","desafío","desafios","desafíos","reto","retos",
    "constancia","practica","práctica","esfuerzo","superacion","superación"
}

_CELEBRATION_TERMS = {
    "celebra","celebrar","celebrando","logro","logros","cumplida","cumplido","avance","éxito","exito","trofeo"
}


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


def _scene_terms(*values: Any) -> List[str]:
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
    return tokens


def _has_any(tokens: List[str], pool: set[str]) -> bool:
    return any(t in pool for t in tokens)


def _pick_visual_query(*values: Any) -> str:
    tokens = _scene_terms(*values)

    if not tokens:
        return "persona escritorio agenda"

    concrete = [w for w in tokens if w not in _ABSTRACT]
    if len(concrete) >= 2:
        tokens = concrete

    has_celebration = _has_any(tokens, _CELEBRATION_TERMS)
    has_notes = _has_any(tokens, _NOTES_TERMS)
    has_hook = _has_any(tokens, _HOOK_TERMS)
    has_routine = _has_any(tokens, _ROUTINE_TERMS)
    has_focus = _has_any(tokens, _FOCUS_TERMS)
    has_social = _has_any(tokens, _SOCIAL_TERMS)
    has_self_discipline = _has_any(tokens, _SELF_DISCIPLINE_TERMS)

    celebration_closure = any(
        t in {
            "celebra", "celebrar", "celebrando", "celebracion", "celebración",
            "logro", "logros", "recompensa", "recompensarte", "premio",
            "motivacion", "motivación", "meta", "metas", "exito", "éxito"
        }
        for t in tokens
    )

    if has_hook:
        return "persona mirando camara oficina"

    if has_notes:
        return "notas recordatorio escritorio"

    if has_social:
        return "grupo personas reunion apoyo"

    if has_focus and has_routine:
        return "persona escribiendo agenda escritorio"

    if has_routine:
        if any(t in {"lista", "listas", "plan", "planes", "prioridad", "prioridades"} for t in tokens):
            return "lista tareas escritorio lapiz"
        if any(t in {"horario", "horarios", "calendario", "tiempo", "bloque", "bloques"} for t in tokens):
            return "calendario agenda escritorio"
        return "persona escribiendo agenda escritorio"

    if has_focus:
        if any(t in {"distraccion", "distracciones", "interrupciones", "silencio"} for t in tokens):
            return "espacio trabajo ordenado"
        if any(t in {"ambiente", "ordenado", "orden", "limpio"} for t in tokens):
            return "laptop escritorio limpio"
        return "persona trabajando escritorio ordenado"

    if has_celebration and celebration_closure:
        return "persona celebrando logro sonrisa"

    if has_self_discipline:
        return "persona superando desafio"

    if any(t in {"reloj", "alarma", "despertador"} for t in tokens):
        return "reloj despertador agenda"

    if any(t in {"camara", "cámara", "rostro", "cara"} for t in tokens):
        return "persona mirando camara oficina"

    if any(t in {"laptop", "computadora", "oficina", "escritorio"} for t in tokens):
        return "persona trabajando laptop oficina"

    if any(t in {"cuaderno", "mano", "manos", "lapiz", "lápiz"} for t in tokens):
        return "manos escribiendo cuaderno escritorio"

    if all(t in _ABSTRACT for t in tokens):
        return "persona mirando camara oficina"

    top = tokens[:4]
    if len(top) == 1:
        return ("persona " + top[0]).strip()

    return " ".join(top).strip() or "persona escritorio agenda"


def _infer_pixabay_context(scene_text: str, image_query: str, scene_index: int) -> Dict[str, Any]:
    text = f"{_norm_text(scene_text)} {_norm_text(image_query)}".lower()

    lang = "es"
    orientation = "vertical"
    min_width = 1080
    editors_choice = False
    category = "people"

    if any(x in text for x in ("agenda", "rutina", "calendario", "horario", "plan", "lista", "escribiendo")):
        category = "business"
    elif any(x in text for x in ("oficina", "escritorio", "laptop", "computadora", "trabajando", "productividad", "espacio", "trabajo", "ordenado")):
        category = "business"
    elif any(x in text for x in ("nota", "notas", "recordatorio", "recordatorios", "papel", "papeles")):
        category = "business"
    elif any(x in text for x in ("celebrando", "logro", "logros", "trofeo", "sonrisa")):
        category = "people"
        editors_choice = True
    elif any(x in text for x in ("salud", "bienestar", "ejercicio", "gym", "gimnasio", "pesas")):
        category = "health"
    elif any(x in text for x in ("comida", "cocina", "desayuno", "almuerzo", "cena", "receta")):
        category = "food"
    elif any(x in text for x in ("viaje", "aeropuerto", "maleta", "vacaciones", "turismo")):
        category = "travel"
    elif any(x in text for x in ("deporte", "correr", "entrenamiento")):
        category = "sports"
    else:
        category = "people"

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
        video_rel = _norm_text(arts.get("video"))

        scene_text = narration or onscreen or stock_query or f"Escena {i+1:02d}"
        image_query = _pick_visual_query(stock_query, narration, onscreen)

        visual_kind = "video" if (video_rel and not image_rel) else "image"
        visual_source_kind = "stock_video" if visual_kind == "video" else "stock_image"
        visual_capability = visual_source_kind

        out.append(
            {
                "id": f"s{i+1:02d}",
                "index": i,
                "start_ms": int(start_ms),
                "end_ms": int(end_ms),
                "duration_ms": int(max(0, end_ms - start_ms)),
                "script_text": scene_text,
                "image_query": image_query,
                "visual_kind": visual_kind,
                "visual_source_kind": visual_source_kind,
                "visual_capability": visual_capability,
                "assets": {
                    "image": image_rel or None,
                    "video": video_rel or None,
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

    scenes = _build_from_legacy_scenes(manifest, total_ms)

    if not scenes:
        scenes = build_scenes_v03(
            script_text=str(script_text or ""),
            max_scenes=int(max_scenes or 1),
            total_audio_ms=int(total_ms or 0),
        )
        for sc in scenes:
            sc["image_query"] = _pick_visual_query(sc.get("image_query"), sc.get("script_text"))

    used_assets: Dict[str, Any] = {
        "paths": set(),
        "source_urls": set(),
        "hit_ids": set(),
    }

    for sc in scenes:
        q = _pick_visual_query(sc.get("image_query"), sc.get("script_text")) or "persona escritorio agenda"
        sc["image_query"] = q

        ctx = _infer_pixabay_context(
            scene_text=_norm_text(sc.get("script_text")),
            image_query=q,
            scene_index=_safe_int(sc.get("index"), 0),
        )

        assets = sc.get("assets")
        if not isinstance(assets, dict):
            assets = {}
            sc["assets"] = assets

        requested_capability = _norm_text(sc.get("visual_capability")).lower()
        if requested_capability not in {"stock_image", "stock_video"}:
            requested_kind = _norm_text(sc.get("visual_kind")).lower()
            requested_capability = "stock_video" if requested_kind == "video" else "stock_image"

        if requested_capability == "stock_video":
            r = resolve_video_for_scene(
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
                used_assets=used_assets,
            )
        else:
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
                used_assets=used_assets,
            )

        actual_kind = _norm_text(r.get("media_kind") or "image").lower()
        actual_source_kind = _norm_text(r.get("source_kind")).lower()

        if actual_kind == "video":
            assets["video"] = r["path"]
            assets["image"] = None

            sc["visual_kind"] = "video"
            sc["visual_source_kind"] = actual_source_kind or "stock_video"
            sc["visual_capability"] = "stock_video"

            if "image_meta" in assets:
                del assets["image_meta"]

            video_meta = {
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

            if r.get("source_url"):
                video_meta["source_url"] = r["source_url"]
            if r.get("thumbnail_url"):
                video_meta["thumbnail_url"] = r["thumbnail_url"]
            if r.get("hit_id") not in (None, ""):
                video_meta["hit_id"] = r["hit_id"]
            if r.get("duration_sec") not in (None, ""):
                video_meta["duration_sec"] = _safe_int(r.get("duration_sec"), 0)

            assets["video_meta"] = video_meta
        else:
            assets["image"] = r["path"]
            assets["video"] = None

            sc["visual_kind"] = "image"
            sc["visual_source_kind"] = actual_source_kind or "stock_image"
            sc["visual_capability"] = "stock_image"

            if "video_meta" in assets:
                del assets["video_meta"]

            image_meta = {
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

            if r.get("source_url"):
                image_meta["source_url"] = r["source_url"]

            if r.get("hit_id") not in (None, ""):
                image_meta["hit_id"] = r["hit_id"]

            assets["image_meta"] = image_meta

    manifest["scenes_v03"] = scenes
    manifest["scene_builder_v03"] = {
        "max_scenes": len(scenes),
        "total_audio_ms": int(total_ms),
        "note": "generated by live_manifest_patch_v03 using legacy scenes as priority source",
    }

    if "scenes" not in manifest or not isinstance(manifest.get("scenes"), list):
        manifest["scenes"] = scenes

    return manifest

