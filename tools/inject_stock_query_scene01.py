import json
from pathlib import Path

run_root = Path(r"C:\Users\vanta\Documents\STUDIO_MVP\_v03_hf_latam_video_20260226_140523")
candidates = sorted(run_root.rglob("storyboard.json"))

if not candidates:
    raise SystemExit("No encontré storyboard.json bajo el run_root")

print("=== STORYBOARD CANDIDATES ===")
for p in candidates:
    print(p)

storyboard_path = candidates[0]
backup_path = storyboard_path.with_name(storyboard_path.name + ".bak_pixabay_scene01")

data = json.loads(storyboard_path.read_text(encoding="utf-8"))
if not isinstance(data, list) or not data:
    raise SystemExit(f"storyboard inválido: {storyboard_path}")

scene = None
for item in data:
    if isinstance(item, dict) and str(item.get("scene_id", "")).strip() == "scene_01":
        scene = item
        break

if scene is None:
    scene = data[0]

stock_query = "productive person working at desk laptop home office vertical portrait"

backup_path.write_text(
    storyboard_path.read_text(encoding="utf-8"),
    encoding="utf-8",
)

scene["stock_query"] = stock_query

storyboard_path.write_text(
    json.dumps(data, ensure_ascii=False, indent=2),
    encoding="utf-8",
)

print()
print("=== UPDATED STORYBOARD ===")
print("STORYBOARD :", storyboard_path)
print("BACKUP     :", backup_path)
print("SCENE_ID   :", scene.get("scene_id"))
print("STOCK_QUERY:", scene.get("stock_query"))
print("PROMPT_PREV:", str(scene.get("image_prompt", ""))[:220])
