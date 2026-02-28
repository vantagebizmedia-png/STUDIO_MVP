import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from app.video_pipeline import _collect_scenes
from app.providers.image_provider import ProviderImage

pack = Path(r".\_pixabay_scene_smoke_pack")
scenes = _collect_scenes(str(pack))
if not scenes:
    raise SystemExit("ERROR: _collect_scenes devolvió vacío")

scene = scenes[0]

full_prompt = "Imagen vertical 9:16, alta calidad, lista para reel.\n\n" + str(scene["image_prompt"])
stock_query = str(scene.get("stock_query") or scene.get("image_stock_query") or "").strip()

gen_kwargs = {}
if stock_query:
    gen_kwargs["stock_query"] = stock_query

p = ProviderImage()
r = p.generate(
    purpose="pixabay_scene_e2e_smoke",
    prompt=full_prompt,
    seed=888,
    **gen_kwargs,
)

img_path = Path(r["path"])
meta_path = img_path.with_suffix(".json")
meta = json.loads(meta_path.read_text(encoding="utf-8"))
m = meta.get("meta", {})

print("=== E2E SCENE RESULT ===")
print("scene_id     :", scene.get("scene_id"))
print("clip_id      :", scene.get("clip_id"))
print("stock_query  :", stock_query)
print("result       :", r)
print()

print("=== META ===")
print("asset_id     :", m.get("asset_id"))
print("user         :", m.get("user"))
print("tags         :", m.get("tags"))
print("redacted_ok  :", "***REDACTED***" in str(m.get("api_search_url", "")))
print("img_path     :", img_path)
print("json_path    :", meta_path)
