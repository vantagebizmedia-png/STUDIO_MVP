import json
import shutil
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from app.video_pipeline import _collect_scenes
from app.providers.image_provider import ProviderImage

src_pack = REPO_ROOT / "_pixabay_render_smoke_src"
export_pack = REPO_ROOT / "_pixabay_render_smoke_export"

if export_pack.exists():
    shutil.rmtree(export_pack, ignore_errors=True)
if src_pack.exists():
    shutil.rmtree(src_pack, ignore_errors=True)

(src_pack / "prompts").mkdir(parents=True, exist_ok=True)
(export_pack / "artifacts").mkdir(parents=True, exist_ok=True)

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
        "voiceover": "Hola, este es un smoke render completo usando imagen desde Pixabay y audio real existente."
    }
]

(src_pack / "prompts" / "scene_01.txt").write_text(
    "persona enfocada trabajando en laptop, oficina moderna, retrato vertical 9:16",
    encoding="utf-8"
)

(src_pack / "storyboard.json").write_text(
    json.dumps(storyboard, ensure_ascii=False, indent=2),
    encoding="utf-8"
)

(src_pack / "script_by_clips.json").write_text(
    json.dumps(clips, ensure_ascii=False, indent=2),
    encoding="utf-8"
)

scenes = _collect_scenes(str(src_pack))
if not scenes:
    raise SystemExit("ERROR: _collect_scenes devolvió vacío")

scene = scenes[0]
full_prompt = "Imagen vertical 9:16, alta calidad, lista para reel.\n\n" + str(scene["image_prompt"])
stock_query = str(scene.get("stock_query") or scene.get("image_stock_query") or "").strip()

gen_kwargs = {}
if stock_query:
    gen_kwargs["stock_query"] = stock_query

provider = ProviderImage()
result = provider.generate(
    purpose="pixabay_render_smoke_scene_01",
    prompt=full_prompt,
    seed=999,
    **gen_kwargs,
)

generated_image = Path(result["path"])
if not generated_image.exists():
    raise SystemExit(f"ERROR: no existe imagen generada: {generated_image}")

audio_src = Path(r"C:\Users\vanta\Documents\STUDIO_MVP\_v03_hf_latam_video_20260226_140523\workspace\exports\pack_v03_42e0fd6e\artifacts\audio.wav")
if not audio_src.exists():
    raise SystemExit(f"ERROR: no existe audio fuente: {audio_src}")

image_dst = export_pack / "artifacts" / "image.png"
audio_dst = export_pack / "artifacts" / "audio.wav"

shutil.copy2(generated_image, image_dst)
shutil.copy2(audio_src, audio_dst)

pack_json = {
    "pack_version": "pixabay_render_smoke_v1",
    "tag": "pixabay_render_smoke",
    "created_at_utc": "2026-02-26T00:00:00Z",
    "source": {
        "providers": {
            "image": "pixabay_images"
        }
    },
    "paths": {
        "image": "artifacts/image.png",
        "audio": "artifacts/audio.wav"
    }
}

(export_pack / "pack.json").write_text(
    json.dumps(pack_json, ensure_ascii=False, indent=2),
    encoding="utf-8"
)

print("OK")
print("SRC_PACK     :", src_pack)
print("EXPORT_PACK  :", export_pack)
print("SCENE_ID     :", scene.get("scene_id"))
print("STOCK_QUERY  :", stock_query)
print("GENERATED    :", generated_image)
print("IMAGE_DST    :", image_dst)
print("AUDIO_DST    :", audio_dst)
