import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from app.video_pipeline import _collect_scenes
from app.providers.image_provider import ProviderImage

pack = REPO_ROOT / "_scene_provider_routing_smoke"
prompts = pack / "prompts"
prompts.mkdir(parents=True, exist_ok=True)

storyboard = [
    {
        "scene_id": "scene_01",
        "from_clip_id": "clip_01",
        "image_prompt_ref": "prompts/scene_01.txt",
        "image_source_mode": "stock",
        "stock_query": "productive person working at desk laptop home office vertical portrait"
    }
]

clips = [
    {
        "clip_id": "clip_01",
        "voiceover": "Validación de routing por escena hacia Pixabay."
    }
]

(pack / "storyboard.json").write_text(
    json.dumps(storyboard, ensure_ascii=False, indent=2),
    encoding="utf-8"
)

(pack / "script_by_clips.json").write_text(
    json.dumps(clips, ensure_ascii=False, indent=2),
    encoding="utf-8"
)

(prompts / "scene_01.txt").write_text(
    "persona trabajando en laptop, oficina moderna, retrato vertical 9:16",
    encoding="utf-8"
)

scenes = _collect_scenes(str(pack))
scene = scenes[0]

default_img = ProviderImage()

cfg_obj = json.loads(Path(default_img.config_path).read_text(encoding="utf-8"))
cfg_obj.setdefault("image", {})
cfg_obj["image"]["active_provider"] = "pixabay_images"

tmp_cfg = REPO_ROOT / "_scene_provider_routing_smoke_provider.json"
tmp_cfg.write_text(json.dumps(cfg_obj, ensure_ascii=False, indent=2), encoding="utf-8")

pixabay_img = ProviderImage(config_path=str(tmp_cfg))

full_prompt = "Imagen vertical 9:16, alta calidad, lista para reel.\n\n" + str(scene["image_prompt"])
stock_query = str(scene.get("stock_query") or scene.get("image_stock_query") or "").strip()

r = pixabay_img.generate(
    purpose="scene_provider_routing_validate",
    prompt=full_prompt,
    seed=321,
    stock_query=stock_query,
)

meta = json.loads(Path(r["path"]).with_suffix(".json").read_text(encoding="utf-8"))
m = meta.get("meta", {})

print("=== ROUTING VALIDATION ===")
print("scene_id              :", scene.get("scene_id"))
print("image_source_mode     :", scene.get("image_source_mode"))
print("default_provider      :", default_img.active_provider)
print("forced_provider_used  :", r.get("provider"))
print("asset_id              :", m.get("asset_id"))
print("redacted_ok           :", "***REDACTED***" in str(m.get("api_search_url", "")))
print("stock_query           :", stock_query)
print("png_path              :", r.get("path"))
print("routing_ok            :", r.get("provider") == "pixabay_images")
