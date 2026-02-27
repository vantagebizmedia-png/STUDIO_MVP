import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from app.main import build_storyboard

clips = [
    {
        "clip_id": "clip_01",
        "purpose": "body",
        "on_screen_text": "Rutina de disciplina diaria",
        "voiceover": "Trabajar con enfoque en tu escritorio y usar Pomodoro mejora tu productividad."
    },
    {
        "clip_id": "clip_02",
        "purpose": "body",
        "on_screen_text": "Meditación y ejercicio",
        "voiceover": "Una rutina de ejercicio y meditación ayuda a mantener la calma."
    },
    {
        "clip_id": "clip_03",
        "purpose": "hook",
        "on_screen_text": "Ciudad cyberpunk con robot gigante",
        "voiceover": "Imagina un mundo futurista surreal con luces neón y una criatura mecánica."
    }
]

scenes = build_storyboard(clips)

print("=== AUTO IMAGE STRATEGY VALIDATION ===")
print(json.dumps(scenes, ensure_ascii=False, indent=2))
print()

for s in scenes:
    print("scene_id                :", s.get("scene_id"))
    print("image_source_mode       :", s.get("image_source_mode"))
    print("image_provider_override :", s.get("image_provider_override"))
    print("stock_query             :", s.get("stock_query"))
    print("image_strategy_reason   :", s.get("image_strategy_reason"))
    print("-" * 100)
