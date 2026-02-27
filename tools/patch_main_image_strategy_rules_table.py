from pathlib import Path
import re

path = Path(r".\app\main.py")
text = path.read_text(encoding="utf-8")

pattern = r'''def _pick_auto_image_strategy\(clip: Dict\[str, Any\]\) -> Dict\[str, str\]:.*?def build_storyboard\(clips: List\[Dict\[str, Any\]\]\) -> List\[Dict\[str, Any\]\]:'''

replacement = '''IMAGE_STRATEGY_RULES = [
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
'''

new_text, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
if count != 1:
    raise SystemExit("No pude reemplazar el bloque _pick_auto_image_strategy/build_storyboard en app/main.py")

path.write_text(new_text, encoding="utf-8")
print("OK: app/main.py ahora usa IMAGE_STRATEGY_RULES editable")
