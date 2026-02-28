import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from app.main import _pick_auto_music_strategy

cases = [
    {
        "name": "productividad",
        "core_topic": "disciplina y productividad diaria",
        "subtopics": ["pomodoro", "enfoque", "trabajo profundo"],
        "target_format": "reel",
        "voice_pacing": "medium",
        "constraints": [],
    },
    {
        "name": "wellness",
        "core_topic": "meditación y ejercicio para sentir calma",
        "subtopics": ["respiración", "rutina saludable"],
        "target_format": "reel",
        "voice_pacing": "slow",
        "constraints": [],
    },
    {
        "name": "fantasia",
        "core_topic": "mundo cyberpunk futurista con robot gigante",
        "subtopics": ["ciudad neón", "ambiente épico"],
        "target_format": "reel",
        "voice_pacing": "fast",
        "constraints": [],
    },
]

print("=== MUSIC STRATEGY VALIDATION ===")
for case in cases:
    result = _pick_auto_music_strategy(
        case["core_topic"],
        case["subtopics"],
        case["target_format"],
        case["voice_pacing"],
        case["constraints"],
    )
    print()
    print("CASE:", case["name"])
    print(json.dumps(result, ensure_ascii=False, indent=2))
