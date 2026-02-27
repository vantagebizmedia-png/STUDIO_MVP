from pathlib import Path

path = Path(r".\app\main.py")
text = path.read_text(encoding="utf-8")

old = '''def build_storyboard(clips: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    scenes: List[Dict[str, Any]] = []
    for i, c in enumerate(clips, start=1):
        visual_type = "motion_ready" if c.get("purpose") in ("hook", "close") else "static_image"
        motion_notes = ""
        if visual_type == "motion_ready":
            motion_notes = "slow zoom / parallax suave; separar en capas (fondo/medio/foreground)"

        scene_id = f"scene_{i:02d}"
        scenes.append({
            "scene_id": scene_id,
            "from_clip_id": c.get("clip_id"),
            "visual_type": visual_type,
            "camera_motion_notes": motion_notes,
            "composition_notes": "texto breve arriba/centro; dejar margen inferior para subtitulos; foco en 1 idea",
            "asset_notes": "iconos simples; 1 grafico maximo si aplica; alto contraste",
            "image_prompt_ref": f"image_prompts/{scene_id}.txt",
        })
    return scenes
'''

new = '''def _compact_image_strategy_text(*parts: Any) -> str:
    raw = " ".join(str(p or "") for p in parts)
    raw = raw.replace("\\r", " ").replace("\\n", " ").lower()
    raw = re.sub(r"\\s+", " ", raw).strip()
    return raw


def _pick_auto_image_strategy(clip: Dict[str, Any]) -> Dict[str, str]:
    text = _compact_image_strategy_text(
        clip.get("purpose"),
        clip.get("on_screen_text"),
        clip.get("voiceover"),
    )

    fantasy_keywords = [
        "dragon", "dragón", "monster", "monstruo", "alien", "robot",
        "cyberpunk", "sci-fi", "scifi", "futurista", "futuristic",
        "galax", "space", "spaceship", "nave espacial", "magic", "magia",
        "mágic", "surreal", "abstract", "abstracto", "fantasy", "fantasia",
        "fantasía", "myth", "mitologico", "mitológico", "apocalipsis",
        "postapocalipt", "steampunk", "neon", "neón", "dream", "sueño",
        "sueños", "portal", "demon", "demonio", "creature", "criatura",
    ]
    if any(k in text for k in fantasy_keywords):
        return {
            "image_source_mode": "generate",
            "image_provider_override": "",
            "stock_query": "",
            "image_strategy_reason": "fantasy_or_stylized_detected",
        }

    productivity_keywords = [
        "disciplina", "discipline", "productividad", "productivity",
        "trabajo", "trabajar", "working", "work", "oficina", "office",
        "escritorio", "desk", "laptop", "home office", "rutina", "routine",
        "hábito", "habito", "habit", "pomodoro", "enfoque", "focus",
        "concentración", "concentracion", "study", "estudio",
    ]
    wellness_keywords = [
        "ejercicio", "exercise", "meditacion", "meditación", "meditation",
        "lectura", "reading", "respirar", "breathing", "calma", "calm",
        "caminar", "walking", "salud", "health",
    ]
    kitchen_keywords = [
        "cocina", "kitchen", "cooking", "cook", "meal", "comida",
        "preparando", "preparing food",
    ]
    phone_keywords = [
        "telefono", "teléfono", "phone", "smartphone", "redes sociales",
        "social media", "scroll", "notificaciones", "notifications",
    ]
    organization_keywords = [
        "organizar", "organizado", "organized", "organize",
        "limpieza", "cleanup", "declutter", "desorden", "workspace",
        "setup", "desk setup",
    ]
    finance_keywords = [
        "dinero", "money", "finanzas", "finance", "budget", "presupuesto",
        "ahorro", "saving", "negocio", "business", "emprend",
    ]

    if any(k in text for k in productivity_keywords):
        query = "productive person working at desk laptop home office vertical portrait"
        reason = "productivity_office_detected"
    elif any(k in text for k in wellness_keywords):
        query = "person healthy routine meditation exercise calm lifestyle vertical portrait"
        reason = "wellness_lifestyle_detected"
    elif any(k in text for k in kitchen_keywords):
        query = "person cooking in kitchen at home vertical portrait"
        reason = "kitchen_lifestyle_detected"
    elif any(k in text for k in phone_keywords):
        query = "person using smartphone at home vertical portrait"
        reason = "phone_social_detected"
    elif any(k in text for k in organization_keywords):
        query = "organized desk workspace cleanup home office vertical portrait"
        reason = "organization_workspace_detected"
    elif any(k in text for k in finance_keywords):
        query = "business person planning money finances laptop desk vertical portrait"
        reason = "finance_business_detected"
    else:
        query = "person explaining topic in modern studio vertical portrait"
        reason = "default_real_world_stock"

    return {
        "image_source_mode": "stock",
        "image_provider_override": "pixabay_images",
        "stock_query": query,
        "image_strategy_reason": reason,
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
'''

if old not in text:
    raise SystemExit("No encontré el bloque exacto de build_storyboard en app/main.py")

text = text.replace(old, new, 1)
path.write_text(text, encoding="utf-8")
print("OK: app/main.py parcheado con heurística automática de imagen")
