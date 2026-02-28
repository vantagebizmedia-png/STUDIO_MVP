import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from app.providers.image_provider import ProviderImage

run_root = Path(r"C:\Users\vanta\Documents\STUDIO_MVP\_v03_hf_latam_video_20260226_140523")
candidates = sorted(run_root.rglob("storyboard.json"))
if not candidates:
    raise SystemExit("No encontré storyboard.json")

storyboard_path = candidates[0]
storyboard = json.loads(storyboard_path.read_text(encoding="utf-8"))

scene = None
for item in storyboard:
    if isinstance(item, dict) and str(item.get("scene_id", "")).strip() == "scene_01":
        scene = item
        break
if scene is None:
    scene = storyboard[0]

full_prompt = "Imagen vertical 9:16, alta calidad, lista para reel.\n\n" + str(scene["image_prompt"])
stock_query = str(scene.get("stock_query") or scene.get("image_stock_query") or "").strip()

gen_kwargs = {}
if stock_query:
    gen_kwargs["stock_query"] = stock_query

p = ProviderImage()
r = p.generate(
    purpose="scene_stock_query_smoke_01",
    prompt=full_prompt,
    seed=777,
    **gen_kwargs,
)

img_path = Path(r["path"])
meta_path = img_path.with_suffix(".json")
meta = json.loads(meta_path.read_text(encoding="utf-8"))
m = meta.get("meta", {})

print("=== SCENE STOCK SMOKE ===")
print("STORYBOARD   :", storyboard_path)
print("SCENE_ID     :", scene.get("scene_id"))
print("STOCK_QUERY  :", stock_query)
print("RESULT       :", r)
print()
print("=== META ===")
print("asset_id     :", m.get("asset_id"))
print("page_url     :", m.get("page_url"))
print("user         :", m.get("user"))
print("tags         :", m.get("tags"))
print("redacted_ok  :", "***REDACTED***" in str(m.get("api_search_url", "")))
print("png_path     :", img_path)
print("json_path    :", meta_path)
