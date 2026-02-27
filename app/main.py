# -*- coding: utf-8 -*-
# app/main.py â€” STUDIO_MVP V2 (Studio puro)
# Comandos:
#   generate   -> crea content_pack (plan maestro + prompts + metadata)
#   finalize   -> crea 3 formatos finales (final_document.md, production_table.csv, prompts_bundle/)
#   validate   -> valida coherencia mÃ­nima y crea run_summary.txt
#   regenerate -> regenera SOLO una parte (subset core menÃº 23) sin destruir el resto
#   export     -> exporta content_pack a ZIP
#
# V2.4+ (texto por API):
# - Integra ProviderText (DRY/LIVE/REPLAY + cache) para:
#   script_by_clips, captions, hashtags, description, music_prompt
# - Si text.mode = DRY => usa builders deterministas (NO API).
# - Si text.mode = LIVE/REPLAY => usa ProviderText (API/cache o cache replay).
#
# V2.4.1 (REPLAY strict friendly):
# - Si REPLAY strict no encuentra cache para una parte: NO crashea.
#   Hace fallback determinista y deja meta "REPLAY_FALLBACK" en manifest.

import csv
import json
import logging
import os
import re
import argparse
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import List, Dict, Any, Optional, Tuple

# ProviderText (texto multi-IA)
try:
    from app.providers.text_provider import ProviderText
except Exception:
    ProviderText = None  # type: ignore

logger = logging.getLogger(__name__)
WORKSPACE_DIR = os.getenv("STUDIO_WORKSPACE", "workspace")
RUNS_DIR = os.path.join(WORKSPACE_DIR, "runs")
PACK_DIRNAME = "content_pack"


# -------------------------
# Utils
# -------------------------

# ==============================
# TEXT GEN MANIFEST INFRA (V2)
# ==============================


def _tg_safe_read_json(path: Path) -> Optional[Dict[str, Any]]:
    try:
        if not path.exists():
            return None
        with path.open("r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def _tg_safe_write_json(path: Path, data: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    tmp.replace(path)


def _tg_ensure_text_generation_section(manifest: Dict[str, Any]) -> Dict[str, Any]:
    tg = manifest.get("text_generation")
    if not isinstance(tg, dict):
        tg = {}
        manifest["text_generation"] = tg
    return tg


def _tg_project_root_from_main_py() -> Path:
    # app/main.py -> project_root is parent of "app"
    return Path(__file__).resolve().parents[1]


def _tg_infer_cached_mode_from_cache_file(cache_key: str) -> str:
    # Intenta leer el JSON cacheado y extraer el 'mode' original (p.ej. LIVE).
    # Devuelve "" si no se puede inferir.
    if not cache_key:
        return ""

    root = _tg_project_root_from_main_py()
    ws = Path(os.getenv("STUDIO_WORKSPACE", "workspace"))
    ws_root = ws if ws.is_absolute() else (root / ws)
    cache_file = ws_root / "cache" / "text" / "openai_responses" / f"{cache_key}.json"
    payload = _tg_safe_read_json(cache_file)
    if not isinstance(payload, dict):
        return ""

    for k in ("mode", "run_mode"):
        v = payload.get(k)
        if isinstance(v, str) and v.strip():
            return v.strip()

    meta = payload.get("meta")
    if isinstance(meta, dict):
        v = meta.get("mode") or meta.get("run_mode")
        if isinstance(v, str) and v.strip():
            return v.strip()

    metadata = payload.get("metadata")
    if isinstance(metadata, dict):
        v = metadata.get("mode") or metadata.get("run_mode")
        if isinstance(v, str) and v.strip():
            return v.strip()

    return ""


def _tg_build_textgen_entry(
    *,
    part: str,
    output_file: str,
    provider_obj: Any,
    cache_hit: bool,
    cache_key: str,
    note: str = "",
) -> Dict[str, Any]:
    mode = getattr(provider_obj, "mode", "") or ""
    replay_strict = bool(getattr(provider_obj, "replay_strict", False))
    active_provider = getattr(provider_obj, "active_provider", "") or ""

    entry: Dict[str, Any] = {
        "provider": active_provider,
        "mode": mode,
        "cached_mode": "",
        "cache_hit": bool(cache_hit),
        "cache_key": cache_key or "",
        "replay_strict": replay_strict,
        "note": note or "",
        "output_file": output_file,
    }

    # REPLAY strict + falta cache => fallback determinista con trazado claro
    if replay_strict and entry["mode"] == "REPLAY" and not entry["cache_hit"]:
        entry["provider"] = "fallback_deterministic"
        entry["mode"] = "REPLAY_FALLBACK"
        entry["cache_key"] = ""
        entry["cached_mode"] = ""
        if not entry["note"]:
            entry["note"] = f"{part}: missing cache in REPLAY strict -> deterministic fallback"

    # cache hit => intenta inferir cached_mode (p.ej. LIVE)
    if entry["cache_hit"] and entry["cache_key"]:
        entry["cached_mode"] = _tg_infer_cached_mode_from_cache_file(entry["cache_key"]) or ""

    return entry


def _tg_manifest_set_textgen_part(manifest: Dict[str, Any], *, part: str, entry: Dict[str, Any]) -> None:
    tg = _tg_ensure_text_generation_section(manifest)
    tg[part] = entry


TEXT_PART_OUTPUTS = {
    "description": "description.txt",
    "captions": "captions.txt",
    "hashtags": "hashtags.txt",
    "music_prompt": "music_prompt.txt",
    "script": "script_by_clips.json",
}


def tg_update_manifest_for_part(
    *,
    pack_dir: Path,
    part: str,
    provider_obj: Any,
    cache_hit: Optional[bool] = None,
    cache_key: Optional[str] = None,
    note: str = "",
) -> None:
    # Actualiza manifest.json con text_generation.<part> de forma consistente.
    # No crashea si falta manifest/cache o si el cache JSON no trae 'mode'.
    output_file = TEXT_PART_OUTPUTS.get(part, "")

    if cache_hit is None:
        cache_hit = bool(getattr(provider_obj, "last_cache_hit", False))
    if cache_key is None:
        cache_key = str(getattr(provider_obj, "last_cache_key", "") or "")
    if not note:
        note = str(getattr(provider_obj, "last_note", "") or "")

    manifest_path = pack_dir / "manifest.json"
    manifest = _tg_safe_read_json(manifest_path) or {}
    # CLEAR_STALE_TEXTGEN_ERRORS_V1
    # Limpia errores viejos si el part se regenerÃ³ OK (evita manifest confuso).
    try:
        tg = manifest.get('text_generation')
        if isinstance(tg, dict):
            if part == 'script':
                tg.pop('script_by_clips_error', None)
            if part in ('description', 'captions', 'hashtags', 'music_prompt'):
                tg.pop('text_parts_error', None)
    except Exception:
        pass
    entry = _tg_build_textgen_entry(
        part=part,
        output_file=output_file,
        provider_obj=provider_obj,
        cache_hit=bool(cache_hit),
        cache_key=str(cache_key or ""),
        note=note,
    )

    _tg_manifest_set_textgen_part(manifest, part=part, entry=entry)
    _tg_safe_write_json(manifest_path, manifest)

def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def make_run_id() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")


def ensure_dir(p: str) -> None:
    os.makedirs(p, exist_ok=True)


def read_text(path: str) -> str:
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def write_text(path: str, s: str) -> None:
    d = os.path.dirname(path)
    if d:
        ensure_dir(d)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write((s or "").rstrip() + "\n")


def read_json(path: str) -> Any:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def write_json(path: str, obj: Any) -> None:
    d = os.path.dirname(path)
    if d:
        ensure_dir(d)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)
        f.write("\n")


def _json_dumps_stable(obj: Any) -> str:
    return json.dumps(obj, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def split_topics(raw: str) -> List[str]:
    parts = re.split(r"[;,|]\s*", (raw or "").strip())
    topics = [p.strip() for p in parts if p.strip()]
    return topics if topics else ["tema general"]


def estimate_clip_seconds(text: str, voice_pacing: str) -> int:
    words = len(re.findall(r"\w+", text))
    wpm = {"rapido": 180, "medio": 140, "lento": 110}.get(voice_pacing, 140)
    seconds = max(4, int((words / wpm) * 60))
    return min(seconds, 60)


def _constraint_tags(constraints: List[str]) -> Dict[str, str]:
    """
    Detecta constraints tipo: 'preset_emocion: x'
    y los devuelve como tags.
    """
    out: Dict[str, str] = {}
    for c in constraints or []:
        m = re.match(r"^\s*([a-zA-Z0-9_]+)\s*:\s*(.+?)\s*$", c)
        if m:
            out[m.group(1).strip()] = m.group(2).strip()
    return out


# -------------------------
# Builders (Plan maestro)
# -------------------------
def build_topic_summary(topics: List[str]) -> Dict[str, Any]:
    core = topics[0]
    subs = topics[1:6]
    return {"core_topic": core, "subtopics": subs}


def build_story_bible(
    topics: List[str],
    style_id: str,
    language: str,
    audience_level: str,
    constraints: List[str],
) -> Dict[str, Any]:
    core = topics[0]
    tone = {"avanzado": "directo", "intermedio": "claro"}.get(audience_level, "educativo")

    tags = _constraint_tags(constraints)

    return {
        "tone": tone,
        "core_message": f"Entiende {core} con una estructura simple y aplicable.",
        "continuity_rules": [
            "Hook -> Desarrollo -> Cierre, sin contradicciones.",
            "Texto en pantalla breve; la voz lleva el ritmo narrativo.",
            "Mantener el mismo estilo visual en todas las escenas.",
        ],
        "visual_rules": {
            "style_id": style_id,
            "text_density": "baja",
            "iconography": "simple",
            "layout": "jerarquia clara, 1 idea por escena",
            "subtitle_safe_area": "dejar margen inferior para subtitulos",
        },
        "characters": [],
        "constraints": constraints,
        "constraint_tags": tags,  # Ãºtil para presets
        "language": language,
    }


def build_clips(topics: List[str], target_format: str, voice_pacing: str) -> List[Dict[str, Any]]:
    core = topics[0]
    subs = topics[1:]

    if target_format == "video_long":
        develop_count = min(8, max(4, 2 + len(subs)))
    else:
        develop_count = min(5, max(2, 1 + len(subs)))

    clips: List[Dict[str, Any]] = []

    hook_vo = f"Hoy vamos a entender {core} de forma simple y aplicable."
    clips.append({
        "clip_id": "clip_01",
        "purpose": "hook",
        "voiceover": hook_vo,
        "estimated_duration_s": estimate_clip_seconds(hook_vo, voice_pacing),
        "on_screen_text": f"{core} en simple",
        "key_points": ["Idea central", "Promesa clara"],
    })

    for i in range(develop_count):
        clip_id = f"clip_{i+2:02d}"
        if subs and i < len(subs):
            st = subs[i]
            vo = f"Subtema: {st}. QuÃ© es, por quÃ© importa, y cÃ³mo aplicarlo en un paso."
            on = f"{st}: 1 paso"
            kp = ["QuÃ© es", "Por quÃ© importa", "CÃ³mo aplicarlo"]
        else:
            step_n = i + 1
            vo = f"Paso {step_n}: identifica lo mÃ¡s importante de {core} y enfócate en lo esencial."
            on = f"Paso {step_n}"
            kp = ["Identifica", "Simplifica", "Aplica"]

        clips.append({
            "clip_id": clip_id,
            "purpose": "develop",
            "voiceover": vo,
            "estimated_duration_s": estimate_clip_seconds(vo, voice_pacing),
            "on_screen_text": on,
            "key_points": kp[:3],
        })

    close_vo = f"Resumen: {core}. Si quieres, hago parte 2 con ejemplos reales."
    clips.append({
        "clip_id": f"clip_{len(clips)+1:02d}",
        "purpose": "close",
        "voiceover": close_vo,
        "estimated_duration_s": estimate_clip_seconds(close_vo, voice_pacing),
        "on_screen_text": "Resumen + CTA",
        "key_points": ["Resumen", "CTA"],
    })

    return clips


def _compact_image_strategy_text(*parts: Any) -> str:
    raw = " ".join(str(p or "") for p in parts)
    raw = raw.replace("\r", " ").replace("\n", " ").lower()
    raw = re.sub(r"\s+", " ", raw).strip()
    return raw


IMAGE_STRATEGY_RULES = [
    {
        "reason": "fantasy_or_stylized_detected",
        "image_source_mode": "generate",
        "image_provider_override": "",
        "stock_query": "",
        "keywords": [
            "dragon", "dragón", "monster", "monstruo", "alien", "robot",
            "cyberpunk", "sci-fi", "scifi", "futurista", "futuristic",
            "galax", "space", "spaceship", "nave espacial", "magic", "magia",
            "mágic", "surreal", "abstract", "abstracto", "fantasy", "fantasia",
            "fantasía", "myth", "mitologico", "mitológico", "apocalipsis",
            "postapocalipt", "steampunk", "neon", "neón", "dream", "sueño",
            "sueños", "portal", "demon", "demonio", "creature", "criatura",
        ],
    },
    {
        "reason": "wellness_lifestyle_detected",
        "image_source_mode": "stock",
        "image_provider_override": "pixabay_images",
        "stock_query": "person healthy routine meditation exercise calm lifestyle vertical portrait",
        "keywords": [
            "ejercicio", "exercise", "meditacion", "meditación", "meditation",
            "lectura", "reading", "respirar", "breathing", "calma", "calm",
            "caminar", "walking", "salud", "health",
        ],
    },
    {
        "reason": "kitchen_lifestyle_detected",
        "image_source_mode": "stock",
        "image_provider_override": "pixabay_images",
        "stock_query": "person cooking in kitchen at home vertical portrait",
        "keywords": [
            "cocina", "kitchen", "cooking", "cook", "meal", "comida",
            "preparando", "preparing food",
        ],
    },
    {
        "reason": "phone_social_detected",
        "image_source_mode": "stock",
        "image_provider_override": "pixabay_images",
        "stock_query": "person using smartphone at home vertical portrait",
        "keywords": [
            "telefono", "teléfono", "phone", "smartphone", "redes sociales",
            "social media", "scroll", "notificaciones", "notifications",
        ],
    },
    {
        "reason": "organization_workspace_detected",
        "image_source_mode": "stock",
        "image_provider_override": "pixabay_images",
        "stock_query": "organized desk workspace cleanup home office vertical portrait",
        "keywords": [
            "organizar", "organizado", "organized", "organize",
            "limpieza", "cleanup", "declutter", "desorden", "workspace",
            "setup", "desk setup",
        ],
    },
    {
        "reason": "finance_business_detected",
        "image_source_mode": "stock",
        "image_provider_override": "pixabay_images",
        "stock_query": "business person planning money finances laptop desk vertical portrait",
        "keywords": [
            "dinero", "money", "finanzas", "finance", "budget", "presupuesto",
            "ahorro", "saving", "negocio", "business", "emprend",
        ],
    },
    {
        "reason": "productivity_office_detected",
        "image_source_mode": "stock",
        "image_provider_override": "pixabay_images",
        "stock_query": "productive person working at desk laptop home office vertical portrait",
        "keywords": [
            "disciplina", "discipline", "productividad", "productivity",
            "trabajo", "trabajar", "working", "work", "oficina", "office",
            "escritorio", "desk", "laptop", "home office", "rutina", "routine",
            "hábito", "habito", "habit", "pomodoro", "enfoque", "focus",
            "concentración", "concentracion", "study", "estudio",
        ],
    },
]

IMAGE_STRATEGY_DEFAULT = {
    "reason": "default_real_world_stock",
    "image_source_mode": "stock",
    "image_provider_override": "pixabay_images",
    "stock_query": "person explaining topic in modern studio vertical portrait",
}


def _pick_auto_image_strategy(clip: Dict[str, Any]) -> Dict[str, str]:
    text = _compact_image_strategy_text(
        clip.get("purpose"),
        clip.get("on_screen_text"),
        clip.get("voiceover"),
    )

    for rule in IMAGE_STRATEGY_RULES:
        keywords = list(rule.get("keywords") or [])
        if any(k in text for k in keywords):
            return {
                "image_source_mode": str(rule.get("image_source_mode") or "stock"),
                "image_provider_override": str(rule.get("image_provider_override") or ""),
                "stock_query": str(rule.get("stock_query") or ""),
                "image_strategy_reason": str(rule.get("reason") or "matched_rule"),
            }

    return {
        "image_source_mode": str(IMAGE_STRATEGY_DEFAULT.get("image_source_mode") or "stock"),
        "image_provider_override": str(IMAGE_STRATEGY_DEFAULT.get("image_provider_override") or ""),
        "stock_query": str(IMAGE_STRATEGY_DEFAULT.get("stock_query") or ""),
        "image_strategy_reason": str(IMAGE_STRATEGY_DEFAULT.get("reason") or "default_real_world_stock"),
    }


def build_storyboard(clips: List[Dict[str, Any]]) -> List[Dict[str, Any]]:

    scenes: List[Dict[str, Any]] = []
    for i, c in enumerate(clips, start=1):
        visual_type = "motion_ready" if c.get("purpose") in ("hook", "close") else "static_image"
        motion_notes = ""
        if visual_type == "motion_ready":
            motion_notes = "slow zoom / parallax suave; separar en capas (fondo/medio/foreground)"

        scene_id = f"scene_{i:02d}"
        strategy = _pick_auto_image_strategy(c)

        scenes.append({
            "scene_id": scene_id,
            "from_clip_id": c.get("clip_id"),
            "visual_type": visual_type,
            "camera_motion_notes": motion_notes,
            "composition_notes": "texto breve arriba/centro; dejar margen inferior para subtitulos; foco en 1 idea",
            "asset_notes": "iconos simples; 1 grafico maximo si aplica; alto contraste",
            "image_prompt_ref": f"image_prompts/{scene_id}.txt",
            "image_source_mode": strategy["image_source_mode"],
            "image_provider_override": strategy["image_provider_override"],
            "stock_query": strategy["stock_query"],
            "image_strategy_reason": strategy["image_strategy_reason"],
        })
    return scenes


def build_image_prompt(scene: Dict[str, Any], clip: Dict[str, Any], story_bible: Dict[str, Any], topic_summary: Dict[str, Any]) -> str:
    core = topic_summary["core_topic"]
    style_id = story_bible["visual_rules"]["style_id"]
    language = story_bible.get("language", "es")
    on_screen = clip.get("on_screen_text", "")
    purpose = clip.get("purpose", "")
    visual_type = scene.get("visual_type", "static_image")

    lines = [
        f"ESTILO: {style_id}.",
        f"IDIOMA: {language}.",
        f"TEMA TRONCAL: {core}.",
        f"OBJETIVO ESCENA: {purpose}.",
        f"TIPO VISUAL: {visual_type}.",
        "FORMATO: infografia clara, iconos simples, jerarquia visual fuerte, poco texto.",
        f"TEXTO EN PANTALLA (breve): \"{on_screen}\".",
        "REGLAS: consistencia tipografica/iconografica; alto contraste; 1 idea por escena.",
        "SUBTITULOS: dejar margen inferior libre (safe area).",
    ]

    tags = story_bible.get("constraint_tags") or {}
    if tags.get("preset_estilo_narrativo"):
        lines.append(f"PRESET estilo_narrativo: {tags['preset_estilo_narrativo']}.")
    if tags.get("preset_emocion"):
        lines.append(f"PRESET emocion: {tags['preset_emocion']}.")
    if tags.get("preset_subgenero"):
        lines.append(f"PRESET subgenero: {tags['preset_subgenero']}.")
    if tags.get("preset_cierre") and purpose == "close":
        lines.append(f"PRESET cierre: {tags['preset_cierre']}.")
    if visual_type == "motion_ready":
        lines.append("MOTION READY: sugerir capas (background/mid/foreground) para parallax; evitar texto al borde.")

    constraints = story_bible.get("constraints", []) or []
    if constraints:
        lines.append("RESTRICCIONES: " + "; ".join(constraints))

    return "\n".join(lines) + "\n"


def _compact_music_strategy_text(*parts: Any) -> str:
    raw = " ".join(str(p or "") for p in parts)
    raw = raw.replace("\r", " ").replace("\n", " ").lower()
    raw = re.sub(r"\s+", " ", raw).strip()
    return raw


MUSIC_STRATEGY_RULES = [
    {
        "reason": "fantasy_cinematic_detected",
        "music_source_mode": "stock",
        "music_provider_override": "pixabay_music",
        "music_query": "epic cinematic trailer background music fantasy sci fi",
        "keywords": [
            "dragon", "dragón", "monster", "monstruo", "alien", "robot",
            "cyberpunk", "sci-fi", "scifi", "futurista", "futuristic",
            "galax", "space", "spaceship", "nave espacial", "magic", "magia",
            "mágic", "surreal", "abstract", "abstracto", "fantasy", "fantasia",
            "fantasía", "myth", "mitologico", "mitológico", "apocalipsis",
            "postapocalipt", "steampunk", "neon", "neón", "dream", "sueño",
            "sueños", "portal", "demon", "demonio", "creature", "criatura",
            "épico", "epic", "trailer"
        ],
        "music_energy": "high",
    },
    {
        "reason": "wellness_calm_detected",
        "music_source_mode": "stock",
        "music_provider_override": "pixabay_music",
        "music_query": "calm ambient meditation relaxing background music",
        "keywords": [
            "ejercicio", "exercise", "meditacion", "meditación", "meditation",
            "lectura", "reading", "respirar", "breathing", "calma", "calm",
            "caminar", "walking", "salud", "health", "relax", "relaxing"
        ],
        "music_energy": "low",
    },
    {
        "reason": "kitchen_lifestyle_detected",
        "music_source_mode": "stock",
        "music_provider_override": "pixabay_music",
        "music_query": "light upbeat cooking lifestyle background music",
        "keywords": [
            "cocina", "kitchen", "cooking", "cook", "meal", "comida",
            "preparando", "preparing food"
        ],
        "music_energy": "medium",
    },
    {
        "reason": "phone_social_detected",
        "music_source_mode": "stock",
        "music_provider_override": "pixabay_music",
        "music_query": "modern social media upbeat background music",
        "keywords": [
            "telefono", "teléfono", "phone", "smartphone", "redes sociales",
            "social media", "scroll", "notificaciones", "notifications"
        ],
        "music_energy": "medium",
    },
    {
        "reason": "organization_workspace_detected",
        "music_source_mode": "stock",
        "music_provider_override": "pixabay_music",
        "music_query": "clean corporate minimal background music workspace",
        "keywords": [
            "organizar", "organizado", "organized", "organize",
            "limpieza", "cleanup", "declutter", "desorden", "workspace",
            "setup", "desk setup"
        ],
        "music_energy": "medium",
    },
    {
        "reason": "finance_business_detected",
        "music_source_mode": "stock",
        "music_provider_override": "pixabay_music",
        "music_query": "business corporate motivational background music",
        "keywords": [
            "dinero", "money", "finanzas", "finance", "budget", "presupuesto",
            "ahorro", "saving", "negocio", "business", "emprend"
        ],
        "music_energy": "medium",
    },
    {
        "reason": "productivity_office_detected",
        "music_source_mode": "stock",
        "music_provider_override": "pixabay_music",
        "music_query": "motivational corporate productivity background music upbeat",
        "keywords": [
            "disciplina", "discipline", "productividad", "productivity",
            "trabajo", "trabajar", "working", "work", "oficina", "office",
            "escritorio", "desk", "laptop", "home office", "rutina", "routine",
            "hábito", "habito", "habit", "pomodoro", "enfoque", "focus",
            "concentración", "concentracion", "study", "estudio"
        ],
        "music_energy": "medium_high",
    },
]

MUSIC_STRATEGY_DEFAULT = {
    "reason": "default_background_stock",
    "music_source_mode": "stock",
    "music_provider_override": "pixabay_music",
    "music_query": "background music inspirational soft corporate",
    "music_energy": "medium",
}


def _pick_auto_music_strategy(
    core_topic: str,
    subtopics: List[str],
    target_format: str,
    voice_pacing: str,
    constraints: List[str],
) -> Dict[str, str]:
    text = _compact_music_strategy_text(
        core_topic,
        " ".join(subtopics or []),
        target_format,
        voice_pacing,
        " ".join(constraints or []),
    )

    for rule in MUSIC_STRATEGY_RULES:
        keywords = list(rule.get("keywords") or [])
        if any(k in text for k in keywords):
            return {
                "music_source_mode": str(rule.get("music_source_mode") or "stock"),
                "music_provider_override": str(rule.get("music_provider_override") or ""),
                "music_query": str(rule.get("music_query") or ""),
                "music_strategy_reason": str(rule.get("reason") or "matched_rule"),
                "music_energy": str(rule.get("music_energy") or "medium"),
            }

    return {
        "music_source_mode": str(MUSIC_STRATEGY_DEFAULT.get("music_source_mode") or "stock"),
        "music_provider_override": str(MUSIC_STRATEGY_DEFAULT.get("music_provider_override") or ""),
        "music_query": str(MUSIC_STRATEGY_DEFAULT.get("music_query") or ""),
        "music_strategy_reason": str(MUSIC_STRATEGY_DEFAULT.get("reason") or "default_background_stock"),
        "music_energy": str(MUSIC_STRATEGY_DEFAULT.get("music_energy") or "medium"),
    }

def build_captions(core_topic: str) -> List[str]:
    return [
        f"{core_topic} explicado sin relleno. Guardalo.",
        f"Si esto te ayudo con {core_topic}, comenta 'parte 2'.",
        f"Guia rapida sobre {core_topic}.",
        f"{core_topic} en pasos simples para aplicar hoy.",
    ]


def build_hashtags(topics: List[str]) -> str:
    base = ["#educacion", "#aprende", "#reels", "#contenido", "#ia"]

    def tagify(t: str) -> str:
        t = re.sub(r"[^a-zA-Z0-9Ã¡Ã©Ã­Ã³ÃºÃ±ÃÃ‰ÃÃ“ÃšÃ‘ ]+", "", t).strip().lower()
        t = re.sub(r"\s+", "", t)
        return "#" + (t[:24] if t else "tema")

    topic_tags = [tagify(t) for t in topics[:10]]
    all_tags = base + topic_tags

    seen = set()
    out: List[str] = []
    for h in all_tags:
        if h not in seen:
            out.append(h)
            seen.add(h)

    return " ".join(out[:25])


def build_description(core_topic: str, subtopics: List[str]) -> str:
    if subtopics:
        subs = ", ".join(subtopics[:5])
        return (
            f"En este video te explico {core_topic} de forma clara y aplicable.\n\n"
            f"Tocamos: {subs}.\n\n"
            "Si quieres la parte 2 con ejemplos, comentarlo y lo preparo."
        )
    return (
        f"En este video te explico {core_topic} de forma clara y aplicable.\n\n"
        "Si quieres la parte 2 con ejemplos, comentarlo y lo preparo."
    )


def build_music_prompt(target_format: str, voice_pacing: str) -> str:
    dur = "30s" if target_format == "reel_short" else "2-4min"
    bpm = {"rapido": "120-140", "medio": "95-115", "lento": "75-95"}.get(voice_pacing, "95-115")
    return (
        "Musica instrumental, sin voces.\n"
        f"Duracion: {dur}.\n"
        f"Ritmo: {voice_pacing}. BPM aproximado: {bpm}.\n"
        "Mood: motivador/educativo, limpio, sin distracciones.\n"
        "Instrumentos sugeridos: percusion suave, synth calido, bajo ligero.\n"
        "Evitar: drops agresivos, vocal chops, sonidos estridentes.\n"
    )


# -------------------------
# V2.4 Texto por ProviderText
# -------------------------
_text_provider_singleton: Optional[Any] = None


def _get_text_provider() -> Any:
    global _text_provider_singleton
    if _text_provider_singleton is None:
        if ProviderText is None:
            raise ImportError("ProviderText no disponible. Verifica app/providers/text_provider.py")
        _text_provider_singleton = ProviderText()  # lee config/providers.json
    return _text_provider_singleton


def _ai_enabled() -> bool:
    """
    Solo usa IA cuando ProviderText estÃ¡ en LIVE o REPLAY.
    En DRY: mantiene builders deterministas (NO API).
    """
    p = _get_text_provider()
    return getattr(p, "mode", "").upper() in ("LIVE", "REPLAY")


def _ai_call(purpose: str, prompt: str, seed: Optional[int] = None) -> Tuple[str, Dict[str, Any]]:
    p = _get_text_provider()
    resp = p.complete(purpose, prompt=prompt, seed=seed)

    # meta "amigable" (aguanta distintos ProviderTextResponse)
    meta = {
        "provider": getattr(resp, "provider_name", getattr(p, "active_provider", "")),
        "model": getattr(resp, "model", ""),
        "mode": getattr(p, "mode", getattr(resp, "mode", "")),  # requested mode
        "cached_mode": "",                                     # se infiere abajo si hay cache_hit
        "cache_hit": getattr(resp, "cache_hit", False),
        "cache_key": getattr(resp, "cache_key", ""),
        "created_at_unix": getattr(resp, "created_at_unix", None),
        "replay_strict": getattr(p, "replay_strict", None),
    }

    # Inferir cached_mode desde el JSON cacheado (p.ej. "LIVE" aunque mode actual sea "REPLAY")
    try:
        if bool(meta.get("cache_hit")) and str(meta.get("cache_key") or "").strip():
            loader = getattr(p, "_load_cache", None)
            if callable(loader):
                hit = loader(str(meta["cache_key"]))
                if isinstance(hit, dict):
                    cm = hit.get("mode") or hit.get("run_mode") or ""
                    if isinstance(cm, str) and cm.strip():
                        meta["cached_mode"] = cm.strip()
    except Exception:
        pass

    return getattr(resp, "text", ""), meta



def _is_missing_cache_error(e: Exception) -> bool:
    s = str(e)
    return ("REPLAY strict" in s and "no existe cache" in s) or ("missing cache" in s.lower())


def _fallback_meta(purpose: str, note: str) -> Dict[str, Any]:
    return {
        "provider": "fallback_deterministic",
        "model": "none",
        "mode": "REPLAY_FALLBACK",
        "cached_mode": None,
        "cache_hit": False,
        "cache_key": "",
        "created_at_unix": int(datetime.now(timezone.utc).timestamp()),
        "replay_strict": True,
        "note": f"{purpose}: {note}",
    }


def _try_parse_json(s: str) -> Optional[Any]:
    try:
        return json.loads(s)
    except Exception:
        m = re.search(r"(\{.*\}|\[.*\])", s, flags=re.DOTALL)
        if m:
            try:
                return json.loads(m.group(1))
            except Exception:
                return None
    return None


def _validate_clips(clips: List[Dict[str, Any]]) -> bool:
    if not isinstance(clips, list) or len(clips) < 3:
        return False
    purposes = [c.get("purpose") for c in clips]
    if "hook" not in purposes or "close" not in purposes:
        return False
    for c in clips:
        if not c.get("clip_id") or not c.get("purpose"):
            return False
        if not isinstance(c.get("voiceover", ""), str) or not c.get("voiceover", "").strip():
            return False
    return True


def ai_generate_clips(
    topics: List[str],
    target_format: str,
    voice_pacing: str,
    audience_level: str,
    constraints: List[str],
    seed: int,
    language: str,
    style_id: str,
    topic_summary: Dict[str, Any],
) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
    core = topic_summary.get("core_topic", topics[0])
    subs = topic_summary.get("subtopics") or topics[1:6]

    base = build_clips(topics, target_format, voice_pacing)
    clip_skeleton = [{"clip_id": c["clip_id"], "purpose": c["purpose"]} for c in base]

    prompt = (
        "Sos un guionista de videos cortos. Escribi un guion por clips.\n"
        "Reglas:\n"
        f"- Idioma: {language}\n"
        f"- Formato: {target_format} (hook -> develop -> close)\n"
        f"- Ritmo de voz: {voice_pacing}\n"
        f"- Nivel audiencia: {audience_level}\n"
        f"- Estilo visual: {style_id} (texto breve en pantalla)\n"
        f"- Restricciones: {('; '.join(constraints) if constraints else 'ninguna')}\n"
        f"- Tema troncal: {core}\n"
        f"- Subtemas: {(', '.join(subs) if subs else 'ninguno')}\n"
        "\n"
        "DevolvÃ© SOLO JSON (sin markdown), como lista de objetos. Cada objeto:\n"
        "{\"clip_id\":\"clip_01\",\"purpose\":\"hook|develop|close\",\"voiceover\":\"...\",\"on_screen_text\":\"...\",\"key_points\":[\"..\",\"..\"]}\n"
        "\n"
        "Clips a completar (NO cambies clip_id ni purpose):\n"
        f"{_json_dumps_stable(clip_skeleton)}\n"
    )

    try:
        text, meta = _ai_call("script_by_clips", prompt, seed=seed)
    except Exception as e:
        if _is_missing_cache_error(e):
            return base, _fallback_meta("script_by_clips", "missing cache in REPLAY strict -> deterministic fallback")
        raise

    data = _try_parse_json(text)
    if not isinstance(data, list):
        raise ValueError("AI no devolvio lista JSON para clips.")

    by_id = {str(x.get("clip_id")): x for x in data if isinstance(x, dict)}
    out: List[Dict[str, Any]] = []

    for c in base:
        cid = c["clip_id"]
        src = by_id.get(cid, {})
        voiceover = str(src.get("voiceover", "")).strip()
        on_screen = str(src.get("on_screen_text", "")).strip()
        kps = src.get("key_points") or c.get("key_points") or []
        if not isinstance(kps, list):
            kps = []
        kps = [str(x).strip() for x in kps if str(x).strip()][:3]

        if not voiceover:
            voiceover = c["voiceover"]
        if not on_screen:
            on_screen = c["on_screen_text"]

        out.append({
            "clip_id": cid,
            "purpose": c["purpose"],
            "voiceover": voiceover,
            "estimated_duration_s": estimate_clip_seconds(voiceover, voice_pacing),
            "on_screen_text": on_screen,
            "key_points": kps if kps else c.get("key_points", []),
        })

    if not _validate_clips(out):
        raise ValueError("Clips AI invalidos tras normalizacion.")

    return out, meta


def _generate_text_part(
    purpose: str,
    prompt: str,
    fallback_fn: Any,
    seed: int,
    post_process=None,
) -> Tuple[str, Dict[str, Any]]:
    """
    Centraliza el patrón try/fallback para todas las partes de texto AI.
    - Si REPLAY strict y no hay cache: devuelve fallback determinista + meta REPLAY_FALLBACK.
    - Si falla por otro motivo: lanza la excepción (no la silencia).
    - post_process: función opcional para transformar el texto devuelto por la AI.
    """
    try:
        text, meta = _ai_call(purpose, prompt, seed=seed)
    except Exception as e:
        if _is_missing_cache_error(e):
            logger.warning("%s: cache miss en REPLAY strict, usando fallback determinista", purpose)
            fallback_text = fallback_fn().strip() + "\n"
            return fallback_text, _fallback_meta(purpose, "missing cache in REPLAY strict -> deterministic fallback")
        logger.warning("%s: error en AI call: %s", purpose, e)
        raise

    if post_process is not None:
        text = post_process(text)
    return (text.strip() + "\n"), meta


def ai_generate_captions(core_topic: str, constraints: List[str], seed: int) -> Tuple[str, Dict[str, Any]]:
    prompt = (
        "Genera 4 captions cortos en espaÃ±ol para un reel educativo.\n"
        f"Tema: {core_topic}\n"
        f"Restricciones: {('; '.join(constraints) if constraints else 'ninguna')}\n"
        "DevolvÃ© SOLO JSON (sin markdown) como lista de strings.\n"
    )

    def _post(text: str) -> str:
        data = _try_parse_json(text)
        if isinstance(data, list) and data:
            lines = [str(x).strip() for x in data if str(x).strip()]
            return "\n".join(lines[:6])
        return text.strip()

    return _generate_text_part(
        "captions", prompt,
        fallback_fn=lambda: "\n".join(build_captions(core_topic)),
        seed=seed, post_process=_post,
    )


def ai_generate_hashtags(topics: List[str], constraints: List[str], seed: int) -> Tuple[str, Dict[str, Any]]:
    prompt = (
        "Genera una linea de 12 a 25 hashtags (sin comas, separados por espacios).\n"
        f"Temas: {', '.join(topics[:10])}\n"
        f"Restricciones: {('; '.join(constraints) if constraints else 'ninguna')}\n"
        "DevolvÃ© SOLO texto (una linea).\n"
    )
    return _generate_text_part(
        "hashtags", prompt,
        fallback_fn=lambda: build_hashtags(topics),
        seed=seed,
    )


def ai_generate_description(core_topic: str, subtopics: List[str], constraints: List[str], seed: int) -> Tuple[str, Dict[str, Any]]:
    prompt = (
        "Escribi una descripcion para un reel educativo en espaÃ±ol (max 600 caracteres).\n"
        f"Tema: {core_topic}\n"
        f"Subtemas: {(', '.join(subtopics[:5]) if subtopics else 'ninguno')}\n"
        f"Restricciones: {('; '.join(constraints) if constraints else 'ninguna')}\n"
        "DevolvÃ© SOLO texto.\n"
    )
    return _generate_text_part(
        "description", prompt,
        fallback_fn=lambda: build_description(core_topic, subtopics),
        seed=seed,
    )


def ai_generate_music_prompt(target_format: str, voice_pacing: str, constraints: List[str], seed: int) -> Tuple[str, Dict[str, Any]]:
    prompt = (
        "Genera un prompt de musica instrumental para edicion de video.\n"
        f"Formato: {target_format}\n"
        f"Ritmo de voz: {voice_pacing}\n"
        f"Restricciones: {('; '.join(constraints) if constraints else 'ninguna')}\n"
        "Inclui: duracion sugerida, bpm aproximado, mood, instrumentos, evitar.\n"
        "DevolvÃ© SOLO texto.\n"
    )
    return _generate_text_part(
        "music_prompt", prompt,
        fallback_fn=lambda: build_music_prompt(target_format, voice_pacing),
        seed=seed,
    )


# -------------------------
# Core operations
# -------------------------
def generate_pack(
    topics: List[str],
    target_format: str,
    language: str,
    style_id: str,
    voice_pacing: str,
    audience_level: str,
    constraints: List[str],
    seed: int,
) -> str:
    rid = make_run_id()
    pack_dir = os.path.join(RUNS_DIR, rid, PACK_DIRNAME)
    prompts_dir = os.path.join(pack_dir, "image_prompts")
    ensure_dir(prompts_dir)

    topic_summary = build_topic_summary(topics)
    story_bible = build_story_bible(topics, style_id, language, audience_level, constraints)

    text_gen_meta: Dict[str, Any] = {}

    # Script/clips (AI opcional)
    if ProviderText is not None:
        try:
            if _ai_enabled():
                clips, meta = ai_generate_clips(
                    topics=topics,
                    target_format=target_format,
                    voice_pacing=voice_pacing,
                    audience_level=audience_level,
                    constraints=constraints,
                    seed=seed,
                    language=language,
                    style_id=style_id,
                    topic_summary=topic_summary,
                )
                text_gen_meta["script"] = meta
                text_gen_meta["script_by_clips"] = meta
            else:
                clips = build_clips(topics, target_format, voice_pacing)
        except Exception as e:
            clips = build_clips(topics, target_format, voice_pacing)
            text_gen_meta["script_by_clips_error"] = str(e)
    else:
        clips = build_clips(topics, target_format, voice_pacing)

    scenes = build_storyboard(clips)

    # Metadata textos (AI opcional)
    core = topic_summary["core_topic"]
    subs = topic_summary["subtopics"]

    captions_txt = "\n".join(build_captions(core)) + "\n"
    hashtags_txt = build_hashtags(topics) + "\n"
    desc_txt = build_description(core, subs) + "\n"
    music_strategy = _pick_auto_music_strategy(core, subs, target_format, voice_pacing, constraints)
    music_txt = build_music_prompt(target_format, voice_pacing) + "\n"

    if ProviderText is not None:
        try:
            if _ai_enabled():
                captions_txt, meta = ai_generate_captions(core, constraints, seed)
                text_gen_meta["captions"] = meta

                hashtags_txt, meta = ai_generate_hashtags(topics, constraints, seed)
                text_gen_meta["hashtags"] = meta

                desc_txt, meta = ai_generate_description(core, subs, constraints, seed)
                text_gen_meta["description"] = meta

                music_txt, meta = ai_generate_music_prompt(target_format, voice_pacing, constraints, seed)
                text_gen_meta["music_prompt"] = meta
        except Exception as e:
            text_gen_meta["text_parts_error"] = str(e)

    music_txt = music_txt.rstrip() + "\n\n" + "\n".join([
        "[AUTO_MUSIC_STRATEGY]",
        f"source_mode={music_strategy['music_source_mode']}",
        f"provider_override={music_strategy['music_provider_override']}",
        f"music_query={music_strategy['music_query']}",
        f"reason={music_strategy['music_strategy_reason']}",
        f"energy={music_strategy['music_energy']}",
    ]) + "\n"

    # Manifest V2 schema
    write_json(os.path.join(pack_dir, "manifest.json"), {
        "schema": "STUDIO_PACK_V2",
        "created_at_utc": utc_now_iso(),
        "inputs": {
            "topics": topics,
            "target_format": target_format,
            "language": language,
            "style_id": style_id,
            "voice_pacing": voice_pacing,
            "audience_level": audience_level,
            "constraints": constraints,
            "seed": seed,
        },
        "topic_summary": topic_summary,
        "counts": {"clips": len(clips), "scenes": len(scenes), "image_prompts": len(scenes)},
        "text_generation": text_gen_meta,
        "music_strategy": music_strategy,
        "final_outputs": {},
        "validation": {},
    })

    write_json(os.path.join(pack_dir, "story_bible.json"), story_bible)
    write_json(os.path.join(pack_dir, "script_by_clips.json"), clips)
    write_json(os.path.join(pack_dir, "storyboard.json"), scenes)

    write_text(os.path.join(pack_dir, "captions.txt"), captions_txt)
    write_text(os.path.join(pack_dir, "hashtags.txt"), hashtags_txt)
    write_text(os.path.join(pack_dir, "description.txt"), desc_txt)
    write_text(os.path.join(pack_dir, "music_prompt.txt"), music_txt)
    write_json(os.path.join(pack_dir, "music_strategy.json"), music_strategy)

    clip_by_id = {c["clip_id"]: c for c in clips}
    for s in scenes:
        clip = clip_by_id[s["from_clip_id"]]
        prompt = build_image_prompt(s, clip, story_bible, topic_summary)
        write_text(os.path.join(prompts_dir, f"{s['scene_id']}.txt"), prompt)

    return os.path.abspath(pack_dir)


def export_pack(pack_dir: str, zip_path: str) -> Dict[str, Any]:
    """
    Export determinista:
      - orden estable
      - timestamps fijos en el ZIP
      - sha256 del ZIP resultante
    NO modifica el pack (no toca manifest).
    """
    # DETERMINISTIC_EXPORT_ZIP_V3
    import hashlib

    pack_dir = os.path.abspath(pack_dir)
    zip_path = os.path.abspath(zip_path)

    if not os.path.isdir(pack_dir):
        raise FileNotFoundError(f"No existe pack_dir: {pack_dir}")

    ensure_dir(os.path.dirname(zip_path))

    items: List[Tuple[str, str]] = []
    zip_abs = os.path.abspath(zip_path)

    for root, dirs, files in os.walk(pack_dir):
        dirs.sort()
        files.sort()
        for fn in files:
            full = os.path.abspath(os.path.join(root, fn))
            if full == zip_abs:
                continue
            rel = Path(full).relative_to(Path(pack_dir)).as_posix()
            items.append((full, rel))

    FIXED_DT = (1980, 1, 1, 0, 0, 0)

    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as z:
        for full, rel in items:
            with open(full, "rb") as f:
                data = f.read()
            zi = zipfile.ZipInfo(rel, date_time=FIXED_DT)
            zi.compress_type = zipfile.ZIP_DEFLATED
            zi.create_system = 0
            zi.external_attr = (0o644 & 0xFFFF) << 16
            z.writestr(zi, data)

    h = hashlib.sha256()
    with open(zip_path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)

    return {
        "zip_path": zip_path,
        "zip_sha256": h.hexdigest(),
        "files_count": len(items),
        "deterministic": True,
    }
# -------------------------
# Final formats (3 outputs)
# -------------------------
def finalize_pack(pack_dir: str) -> Dict[str, str]:
    """
    Crea:
      - final_document.md
      - production_table.csv
      - prompts_bundle/...
    Actualiza manifest.final_outputs.
    """
    pack_dir = os.path.abspath(pack_dir)
    manifest_path = os.path.join(pack_dir, "manifest.json")
    manifest = read_json(manifest_path)
    story_bible = read_json(os.path.join(pack_dir, "story_bible.json"))
    storyboard = read_json(os.path.join(pack_dir, "storyboard.json"))
    clips = read_json(os.path.join(pack_dir, "script_by_clips.json"))
    topic_summary = manifest.get("topic_summary", {})

    # 1) final_document.md
    md_path = os.path.join(pack_dir, "final_document.md")
    md: List[str] = []
    md.append("# Documento final - STUDIO_MVP\n")
    md.append(f"- Generado: {utc_now_iso()}\n")
    md.append(f"- Tema troncal: **{topic_summary.get('core_topic','')}**\n")
    subs = topic_summary.get("subtopics") or []
    if subs:
        md.append(f"- Subtemas: {', '.join(subs)}\n")

    tags = story_bible.get("constraint_tags") or {}
    if tags:
        md.append("\n## Presets / Tags\n")
        for k, v in tags.items():
            md.append(f"- **{k}**: {v}\n")

    md.append("\n## Guion por clips\n")
    for c in clips:
        md.append(f"### {c['clip_id']} - {c['purpose']}\n")
        md.append(f"- Duracion est.: {c.get('estimated_duration_s','')}s\n")
        md.append(f"- Texto en pantalla: {c.get('on_screen_text','')}\n")
        md.append(f"- Voiceover:\n\n{c.get('voiceover','')}\n\n")

    md.append("\n## Storyboard\n")
    for s in storyboard:
        md.append(f"- {s['scene_id']} -> {s['from_clip_id']} | {s['visual_type']}\n")

    md.append("\n## Prompts\n")
    md.append("### Musica\n")
    md.append("```text\n" + read_text(os.path.join(pack_dir, "music_prompt.txt")).strip() + "\n```\n")
    md.append("\n### Imagen (por escena)\n")
    for s in storyboard:
        p = os.path.join(pack_dir, s["image_prompt_ref"])
        if os.path.exists(p):
            md.append(f"#### {s['scene_id']}\n")
            md.append("```text\n" + read_text(p).strip() + "\n```\n")

    md.append("\n## Metadata\n")
    md.append("### Description\n")
    md.append(read_text(os.path.join(pack_dir, "description.txt")).strip() + "\n")
    md.append("\n### Captions\n")
    md.append("```text\n" + read_text(os.path.join(pack_dir, "captions.txt")).strip() + "\n```\n")
    md.append("\n### Hashtags\n")
    md.append(read_text(os.path.join(pack_dir, "hashtags.txt")).strip() + "\n")

    write_text(md_path, "\n".join(md))

    # 2) production_table.csv
    csv_path = os.path.join(pack_dir, "production_table.csv")
    clip_by_id = {c["clip_id"]: c for c in clips}
    with open(csv_path, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["scene_id", "clip_id", "purpose", "visual_type", "on_screen_text", "duration_s", "image_prompt_file"])
        for s in storyboard:
            c = clip_by_id.get(s["from_clip_id"], {})
            w.writerow([
                s["scene_id"],
                s["from_clip_id"],
                c.get("purpose", ""),
                s.get("visual_type", ""),
                c.get("on_screen_text", ""),
                c.get("estimated_duration_s", ""),
                s.get("image_prompt_ref", ""),
            ])

    # 3) prompts_bundle/
    bundle_dir = os.path.join(pack_dir, "prompts_bundle")
    ensure_dir(bundle_dir)
    ensure_dir(os.path.join(bundle_dir, "image"))
    ensure_dir(os.path.join(bundle_dir, "music"))
    ensure_dir(os.path.join(bundle_dir, "text"))

    # music
    write_text(os.path.join(bundle_dir, "music", "music_prompt.txt"), read_text(os.path.join(pack_dir, "music_prompt.txt")))

    # image prompts
    for s in storyboard:
        src = os.path.join(pack_dir, s["image_prompt_ref"])
        if os.path.exists(src):
            dst = os.path.join(bundle_dir, "image", os.path.basename(src))
            write_text(dst, read_text(src))

    # text prompts (referencia a metadata)
    write_text(os.path.join(bundle_dir, "text", "description.txt"), read_text(os.path.join(pack_dir, "description.txt")))
    write_text(os.path.join(bundle_dir, "text", "captions.txt"), read_text(os.path.join(pack_dir, "captions.txt")))
    write_text(os.path.join(bundle_dir, "text", "hashtags.txt"), read_text(os.path.join(pack_dir, "hashtags.txt")))

    # update manifest
    manifest["final_outputs"] = {
        "final_document_md": "final_document.md",
        "production_table_csv": "production_table.csv",
        "prompts_bundle_dir": "prompts_bundle",
        "generated_at_utc": utc_now_iso(),
    }
    write_json(manifest_path, manifest)

    return {
        "final_document_md": md_path,
        "production_table_csv": csv_path,
        "prompts_bundle_dir": bundle_dir,
    }


# -------------------------
# Validation + summary
# -------------------------
def validate_pack(pack_dir: str) -> Dict[str, Any]:
    pack_dir = os.path.abspath(pack_dir)
    manifest_path = os.path.join(pack_dir, "manifest.json")
    clips = read_json(os.path.join(pack_dir, "script_by_clips.json"))
    storyboard = read_json(os.path.join(pack_dir, "storyboard.json"))
    story_bible = read_json(os.path.join(pack_dir, "story_bible.json"))

    issues: List[str] = []
    purposes = [c.get("purpose") for c in clips]
    if "hook" not in purposes:
        issues.append("Falta hook en script_by_clips.")
    if "close" not in purposes:
        issues.append("Falta close en script_by_clips.")
    if len(clips) < 3:
        issues.append("Muy pocos clips (min recomendado 3).")
    if len(storyboard) != len(clips):
        issues.append("Storyboard y clips no coinciden en cantidad.")
    if story_bible.get("visual_rules", {}).get("style_id") in (None, ""):
        issues.append("Falta style_id en story_bible.visual_rules.")

    # Safe area en prompts (mÃ­nimo: "safe area" en cada prompt)
    prompts_dir = os.path.join(pack_dir, "image_prompts")
    if os.path.isdir(prompts_dir):
        for s in storyboard:
            p = os.path.join(pack_dir, s["image_prompt_ref"])
            if os.path.exists(p):
                txt = read_text(p)
                if "safe area" not in txt.lower():
                    issues.append(f"{s['scene_id']}: prompt sin menciÃ³n de safe area.")
            else:
                issues.append(f"{s['scene_id']}: falta archivo prompt {s['image_prompt_ref']}")

    ok = len(issues) == 0
    result = {
        "ok": ok,
        "issues": issues,
        "validated_at_utc": utc_now_iso(),
        "counts": {"clips": len(clips), "scenes": len(storyboard)},
    }

    # write run_summary.txt
    summary_path = os.path.join(pack_dir, "run_summary.txt")
    lines: List[str] = []
    lines.append("STUDIO_MVP - run_summary")
    lines.append(f"validated_at_utc: {result['validated_at_utc']}")
    lines.append(f"ok: {ok}")
    lines.append(f"clips: {len(clips)} | scenes: {len(storyboard)}")
    if issues:
        lines.append("issues:")
        for it in issues:
            lines.append(f"- {it}")
    write_text(summary_path, "\n".join(lines))

    # update manifest.validation
    manifest = read_json(manifest_path)
    manifest["validation"] = result
    write_json(manifest_path, manifest)

    return result


# -------------------------
# Regenerate subset core
# -------------------------
def _regen_load_context(pack_dir: str) -> Dict[str, Any]:
    """Carga el contexto completo de un pack para regenerate()."""
    manifest_path = os.path.join(pack_dir, "manifest.json")
    manifest = read_json(manifest_path)
    inputs = manifest.get("inputs", {})
    topics = inputs.get("topics", ["tema general"])
    target_format = inputs.get("target_format", "reel_short")
    language = inputs.get("language", "es")
    style_id = inputs.get("style_id", "infografia")
    voice_pacing = inputs.get("voice_pacing", "medio")
    audience_level = inputs.get("audience_level", "principiante")
    constraints = inputs.get("constraints", [])
    seed = inputs.get("seed", 123)
    topic_summary = manifest.get("topic_summary") or build_topic_summary(topics)

    story_bible_path = os.path.join(pack_dir, "story_bible.json")
    storyboard_path = os.path.join(pack_dir, "storyboard.json")
    clips_path = os.path.join(pack_dir, "script_by_clips.json")
    prompts_dir = os.path.join(pack_dir, "image_prompts")

    def _load_story_bible():
        if os.path.exists(story_bible_path):
            return read_json(story_bible_path)
        return build_story_bible(topics, style_id, language, audience_level, constraints)

    def _load_clips():
        if os.path.exists(clips_path):
            return read_json(clips_path)
        return build_clips(topics, target_format, voice_pacing)

    def _load_storyboard(clips):
        if os.path.exists(storyboard_path):
            return read_json(storyboard_path)
        return build_storyboard(clips)

    return {
        "manifest": manifest,
        "manifest_path": manifest_path,
        "topics": topics,
        "target_format": target_format,
        "language": language,
        "style_id": style_id,
        "voice_pacing": voice_pacing,
        "audience_level": audience_level,
        "constraints": constraints,
        "seed": seed,
        "topic_summary": topic_summary,
        "storyboard_path": storyboard_path,
        "clips_path": clips_path,
        "prompts_dir": prompts_dir,
        "load_story_bible": _load_story_bible,
        "load_clips": _load_clips,
        "load_storyboard": _load_storyboard,
    }


def _regen_write_text_part(ctx: Dict, part_key: str, ai_fn, fallback_fn, filename: str) -> Dict[str, Any]:
    """Handler genérico para partes de texto (captions/hashtags/description/music_prompt)."""
    pack_dir = ctx["pack_dir"]
    manifest = ctx["manifest"]
    manifest_path = ctx["manifest_path"]
    choice = ctx["choice"]

    if ProviderText is not None and _ai_enabled():
        txt, meta = ai_fn()
        manifest.setdefault("text_generation", {})[part_key] = meta
        write_json(manifest_path, manifest)
        write_text(os.path.join(pack_dir, filename), txt)
    else:
        write_text(os.path.join(pack_dir, filename), fallback_fn())
    return {"ok": True, "choice": choice, "updated": [filename]}


def _regen_choice_3(ctx: Dict) -> Dict[str, Any]:
    """Regenera guion completo (clips + storyboard + prompts imagen)."""
    pack_dir, manifest, manifest_path = ctx["pack_dir"], ctx["manifest"], ctx["manifest_path"]
    topics, target_format, voice_pacing = ctx["topics"], ctx["target_format"], ctx["voice_pacing"]
    audience_level, constraints, seed = ctx["audience_level"], ctx["constraints"], ctx["seed"]
    language, style_id, topic_summary = ctx["language"], ctx["style_id"], ctx["topic_summary"]
    storyboard_path, clips_path, prompts_dir = ctx["storyboard_path"], ctx["clips_path"], ctx["prompts_dir"]
    choice = ctx["choice"]

    if ProviderText is not None and _ai_enabled():
        clips, meta = ai_generate_clips(
            topics=topics, target_format=target_format, voice_pacing=voice_pacing,
            audience_level=audience_level, constraints=constraints, seed=seed,
            language=language, style_id=style_id, topic_summary=topic_summary,
        )
        tg = manifest.setdefault("text_generation", {})
        if isinstance(meta, dict) and meta.get("provider") == "fallback_deterministic":
            note = meta.get("note")
            if isinstance(note, str) and note.startswith("script_by_clips:"):
                meta = dict(meta)
                meta["note"] = "script:" + note[len("script_by_clips:"):]
        tg["script"] = meta
        tg["script_by_clips"] = meta
        write_json(manifest_path, manifest)
    else:
        clips = build_clips(topics, target_format, voice_pacing)

    write_json(clips_path, clips)
    storyboard = build_storyboard(clips)
    write_json(storyboard_path, storyboard)

    ensure_dir(prompts_dir)
    story_bible = ctx["load_story_bible"]()
    clip_by_id = {c["clip_id"]: c for c in clips}
    for s in storyboard:
        clip = clip_by_id[s["from_clip_id"]]
        prompt = build_image_prompt(s, clip, story_bible, topic_summary)
        write_text(os.path.join(prompts_dir, f"{s['scene_id']}.txt"), prompt)

    return {"ok": True, "choice": choice, "updated": ["script_by_clips.json", "storyboard.json", "image_prompts/*"]}


def _regen_choice_6(ctx: Dict) -> Dict[str, Any]:
    """Regenera storyboard + prompts imagen."""
    pack_dir, storyboard_path, prompts_dir = ctx["pack_dir"], ctx["storyboard_path"], ctx["prompts_dir"]
    topic_summary, choice = ctx["topic_summary"], ctx["choice"]
    clips = ctx["load_clips"]()
    storyboard = build_storyboard(clips)
    write_json(storyboard_path, storyboard)
    story_bible = ctx["load_story_bible"]()
    ensure_dir(prompts_dir)
    clip_by_id = {c["clip_id"]: c for c in clips}
    for s in storyboard:
        clip = clip_by_id[s["from_clip_id"]]
        prompt = build_image_prompt(s, clip, story_bible, topic_summary)
        write_text(os.path.join(prompts_dir, f"{s['scene_id']}.txt"), prompt)
    return {"ok": True, "choice": choice, "updated": ["storyboard.json", "image_prompts/*"]}


def _regen_choice_7(ctx: Dict) -> Dict[str, Any]:
    """Regenera todos los prompts de imagen."""
    pack_dir, prompts_dir, topic_summary, choice = ctx["pack_dir"], ctx["prompts_dir"], ctx["topic_summary"], ctx["choice"]
    clips = ctx["load_clips"]()
    storyboard = ctx["load_storyboard"](clips)
    story_bible = ctx["load_story_bible"]()
    ensure_dir(prompts_dir)
    clip_by_id = {c["clip_id"]: c for c in clips}
    for s in storyboard:
        clip = clip_by_id[s["from_clip_id"]]
        prompt = build_image_prompt(s, clip, story_bible, topic_summary)
        write_text(os.path.join(prompts_dir, f"{s['scene_id']}.txt"), prompt)
    return {"ok": True, "choice": choice, "updated": ["image_prompts/*"]}


def _regen_choice_8(ctx: Dict) -> Dict[str, Any]:
    """Regenera prompt de una escena específica."""
    scene_id = ctx["scene_id"]
    if not scene_id:
        raise ValueError("Para choice=8 necesitas --scene_id scene_XX")
    pack_dir, prompts_dir, topic_summary, choice = ctx["pack_dir"], ctx["prompts_dir"], ctx["topic_summary"], ctx["choice"]
    clips = ctx["load_clips"]()
    storyboard = ctx["load_storyboard"](clips)
    story_bible = ctx["load_story_bible"]()
    clip_by_id = {c["clip_id"]: c for c in clips}
    scene = next((x for x in storyboard if x["scene_id"] == scene_id), None)
    if not scene:
        raise ValueError(f"No existe scene_id: {scene_id}")
    clip = clip_by_id[scene["from_clip_id"]]
    prompt = build_image_prompt(scene, clip, story_bible, topic_summary)
    ensure_dir(prompts_dir)
    write_text(os.path.join(prompts_dir, f"{scene_id}.txt"), prompt)
    return {"ok": True, "choice": choice, "updated": [f"image_prompts/{scene_id}.txt"]}


def regenerate(pack_dir: str, choice: int, scene_id: str = "") -> Dict[str, Any]:
    """
    Subset core V2 — tabla dispatch:
      3: guion completo (clips)     6: storyboard     7: prompts imagen (todas)
      8: prompt imagen (1 escena)   9: music_prompt   10: captions
      11: hashtags                  12: description   13: finalize
      14: export zip                18: validate      20: replay
    """
    pack_dir = os.path.abspath(pack_dir)

    if choice == 20:
        return {"ok": True, "choice": choice, "note": "REPLAY: no recalculado."}
    if choice == 13:
        return {"ok": True, "choice": choice, "final_outputs": finalize_pack(pack_dir)}
    if choice == 14:
        zip_path = os.path.join(os.path.dirname(pack_dir), "content_pack.zip")
        return {"ok": True, "choice": choice, "zip_path": export_pack(pack_dir, zip_path)}
    if choice == 18:
        return {"ok": True, "choice": choice, "validation": validate_pack(pack_dir)}

    # Para el resto necesitamos el contexto completo
    ctx = _regen_load_context(pack_dir)
    ctx["pack_dir"] = pack_dir
    ctx["choice"] = choice
    ctx["scene_id"] = scene_id

    # Tabla dispatch para choices visuales y de texto
    _REGEN_DISPATCH: Dict[int, Any] = {
        3: _regen_choice_3,
        6: _regen_choice_6,
        7: _regen_choice_7,
        8: _regen_choice_8,
        9: lambda c: _regen_write_text_part(
            c, "music_prompt",
            ai_fn=lambda: ai_generate_music_prompt(c["target_format"], c["voice_pacing"], c["constraints"], c["seed"]),
            fallback_fn=lambda: build_music_prompt(c["target_format"], c["voice_pacing"]),
            filename="music_prompt.txt",
        ),
        10: lambda c: _regen_write_text_part(
            c, "captions",
            ai_fn=lambda: ai_generate_captions(c["topic_summary"].get("core_topic", c["topics"][0]), c["constraints"], c["seed"]),
            fallback_fn=lambda: "\n".join(build_captions(c["topic_summary"].get("core_topic", c["topics"][0]))),
            filename="captions.txt",
        ),
        11: lambda c: _regen_write_text_part(
            c, "hashtags",
            ai_fn=lambda: ai_generate_hashtags(c["topics"], c["constraints"], c["seed"]),
            fallback_fn=lambda: build_hashtags(c["topics"]),
            filename="hashtags.txt",
        ),
        12: lambda c: _regen_write_text_part(
            c, "description",
            ai_fn=lambda: ai_generate_description(
                c["topic_summary"].get("core_topic", c["topics"][0]),
                c["topic_summary"].get("subtopics") or c["topics"][1:6],
                c["constraints"], c["seed"],
            ),
            fallback_fn=lambda: build_description(
                c["topic_summary"].get("core_topic", c["topics"][0]),
                c["topic_summary"].get("subtopics") or c["topics"][1:6],
            ),
            filename="description.txt",
        ),
    }

    handler = _REGEN_DISPATCH.get(choice)
    if handler is None:
        raise ValueError(f"Choice no implementado en V2 core: {choice}")
    return handler(ctx)


# -------------------------
# CLI
# -------------------------
PART_TO_CHOICE: Dict[str, int] = {
    "script": 3,
    "script_by_clips": 3,
    "storyboard": 6,
    "image_prompts": 7,
    "image_prompt": 7,
    "image_scene": 8,
    "music_prompt": 9,
    "captions": 10,
    "hashtags": 11,
    "description": 12,
}


def main() -> None:
    logging.basicConfig(level=logging.WARNING, format="%(levelname)s %(name)s: %(message)s")
    ap = argparse.ArgumentParser(prog="studio_mvp_v2")
    sub = ap.add_subparsers(dest="cmd", required=True)

    g = sub.add_parser("generate", help="Genera content_pack V2 (Studio puro)")
    g.add_argument("--topics", required=True, help='Ej: "finanzas personales,habitos,ansiedad"')
    g.add_argument("--target_format", default="reel_short", choices=["reel_short", "video_long"])
    g.add_argument("--language", default="es")
    g.add_argument("--style_id", default="infografia")
    g.add_argument("--voice_pacing", default="medio", choices=["rapido", "medio", "lento"])
    g.add_argument("--audience_level", default="principiante", choices=["principiante", "intermedio", "avanzado"])
    g.add_argument("--constraints", default="", help='Ej: "sin humor; sin marcas"')
    g.add_argument("--seed", default=123, type=int)

    fz = sub.add_parser("finalize", help="Genera 3 formatos finales (md/csv/prompts_bundle)")
    fz.add_argument("--pack_dir", required=True)

    v = sub.add_parser("validate", help="Valida coherencia mÃ­nima y escribe run_summary.txt")
    v.add_argument("--pack_dir", required=True)

    r = sub.add_parser("regenerate", help="Regenera SOLO una parte (subset core menÃº 23)")
    r.add_argument("--pack_dir", required=True)

    mex = r.add_mutually_exclusive_group(required=True)
    mex.add_argument("--choice", type=int, help="NÃºmero del menÃº (compat, ej: 7)")
    mex.add_argument(
        "--part",
        choices=[
            "captions",
            "description",
            "hashtags",
            "image_prompt",
            "image_prompts",
            "image_scene",
            "music_prompt",
            "script",
            "script_by_clips",
            "storyboard",
        ],
        help=(
            "Alias estable:\n"
            "script|captions|hashtags|description|music_prompt|image_prompts|storyboard|image_scene"
        ),
    )
    r.add_argument("--scene_id", default="", help="Solo para choice=8 / part=image_scene (scene_XX)")

    e = sub.add_parser("export", help="Exporta un content_pack a ZIP")
    e.add_argument("--pack_dir", required=True)
    e.add_argument("--zip_path", default="", help="Si vacÃ­o, crea junto al pack: content_pack.zip")

    args = ap.parse_args()

    if args.cmd == "generate":
        topics = split_topics(args.topics)
        constraints = [c.strip() for c in re.split(r"[;|,]\s*", args.constraints) if c.strip()]
        pack_dir = generate_pack(
            topics=topics,
            target_format=args.target_format,
            language=args.language,
            style_id=args.style_id,
            voice_pacing=args.voice_pacing,
            audience_level=args.audience_level,
            constraints=constraints,
            seed=args.seed,
        )
        print(json.dumps({"ok": True, "pack_dir": pack_dir}, ensure_ascii=False))
        return

    if args.cmd == "finalize":
        outs = finalize_pack(args.pack_dir)
        print(json.dumps({"ok": True, "final_outputs": outs}, ensure_ascii=False))
        return

    if args.cmd == "validate":
        res = validate_pack(args.pack_dir)
        print(json.dumps({"ok": True, "validation": res}, ensure_ascii=False))
        return

    if args.cmd == "regenerate":
        choice: int
        if args.choice is not None:
            choice = int(args.choice)
        else:
            choice = PART_TO_CHOICE[str(args.part)]
        res = regenerate(args.pack_dir, choice, args.scene_id)
        print(json.dumps(res, ensure_ascii=False))
        return
    if args.cmd == "export":
        zip_path = args.zip_path.strip()
        if not zip_path:
            zip_path = os.path.join(os.path.dirname(os.path.abspath(args.pack_dir)), "content_pack.zip")
        out = export_pack(args.pack_dir, zip_path)
        payload = {"ok": True}
        payload.update(out)
        print(json.dumps(payload, ensure_ascii=False))
        return
if __name__ == "__main__":
    main()




