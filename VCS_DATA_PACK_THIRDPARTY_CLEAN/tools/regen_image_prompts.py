import os, sys, json

pack = sys.argv[1]

def rj(p):
    with open(p, "r", encoding="utf-8") as f:
        return json.load(f)

def wtxt(p, s):
    d = os.path.dirname(p)
    if d:
        os.makedirs(d, exist_ok=True)
    with open(p, "w", encoding="utf-8", newline="\n") as f:
        f.write((s or "").rstrip() + "\n")

manifest = rj(os.path.join(pack, "manifest.json"))
story_bible = rj(os.path.join(pack, "story_bible.json"))
clips = rj(os.path.join(pack, "script_by_clips.json"))
scenes = rj(os.path.join(pack, "storyboard.json"))
topic_summary = manifest.get("topic_summary") or {}

# Importa el generador oficial (determinista)
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))  # repo root
from app.main import build_image_prompt

clip_by_id = {str(c.get("clip_id","")).strip(): c for c in clips if isinstance(c, dict)}

written = 0
missing_clip = 0
refs = []

for s in scenes:
    if not isinstance(s, dict):
        continue
    scene_id = str(s.get("scene_id") or s.get("id") or "").strip()
    from_clip = str(s.get("from_clip_id") or s.get("clip_id") or s.get("from_clip") or "").strip()
    if not scene_id or not from_clip:
        continue

    clip = clip_by_id.get(from_clip)
    if not clip:
        missing_clip += 1
        continue

    prompt = build_image_prompt(s, clip, story_bible, topic_summary)
    ref = str(s.get("image_prompt_ref") or f"image_prompts/{scene_id}.txt").strip()
    out_path = os.path.join(pack, ref.replace("/", os.sep))

    wtxt(out_path, prompt)
    refs.append(ref)
    written += 1

print("== REGEN IMAGE PROMPTS ==")
print("written:", written, "missing_clip:", missing_clip)
for ref in refs[:6]:
    print("ok:", ref)
