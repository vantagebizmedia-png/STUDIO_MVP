import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from app.video_pipeline import _collect_scenes

pack = Path(r".\_pixabay_scene_smoke_pack")
prompts = pack / "prompts"
prompts.mkdir(parents=True, exist_ok=True)

storyboard = [
    {
        "scene_id": "scene_01",
        "from_clip_id": "clip_01",
        "image_prompt_ref": "prompts/scene_01.txt",
        "stock_query": "productive person working at desk laptop home office vertical portrait"
    }
]

clips = [
    {
        "clip_id": "clip_01",
        "voiceover": "Hola, aquí validamos que stock_query pase desde storyboard hasta la colección de escenas."
    }
]

(prompt := prompts / "scene_01.txt").write_text(
    "persona enfocada trabajando en laptop, oficina moderna, retrato vertical 9:16",
    encoding="utf-8"
)

(pack / "storyboard.json").write_text(
    json.dumps(storyboard, ensure_ascii=False, indent=2),
    encoding="utf-8"
)

(pack / "script_by_clips.json").write_text(
    json.dumps(clips, ensure_ascii=False, indent=2),
    encoding="utf-8"
)

scenes = _collect_scenes(str(pack))

print("=== PACK ===")
print(pack.resolve())
print()

print("=== COLLECTED SCENES ===")
print(json.dumps(scenes, ensure_ascii=False, indent=2))
print()

if not scenes:
    raise SystemExit("ERROR: _collect_scenes devolvió vacío")

scene = scenes[0]
print("scene_id          :", scene.get("scene_id"))
print("clip_id           :", scene.get("clip_id"))
print("stock_query       :", scene.get("stock_query"))
print("image_stock_query :", scene.get("image_stock_query"))
print("image_prompt      :", scene.get("image_prompt"))
print("voiceover         :", scene.get("voiceover"))
print()
print("stock_query_ok    :", scene.get("stock_query") == "productive person working at desk laptop home office vertical portrait")
