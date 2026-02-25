from __future__ import annotations
from pathlib import Path
import re, shutil
from datetime import datetime

p = Path("app/video_pipeline.py")
if not p.exists():
    raise SystemExit("No existe app/video_pipeline.py")

ts = datetime.now().strftime("%Y%m%d_%H%M%S")
bak = p.with_name(p.name + f".bak_rebuild_blocks_{ts}")
shutil.copy2(p, bak)
print("Backup:", bak)

txt = p.read_text(encoding="utf-8")

# ---------- 1) BLOQUE IMÁGENES: desde "img = ProviderImage()" hasta antes de "if args.subs:" ----------
pat_img = re.compile(
    r"(?ms)^(?P<i>[ \t]*)img\s*=\s*ProviderImage\(\)\s*\r?\n.*?(?=^(?P=i)if\s+args\.subs:)"
)
m = pat_img.search(txt)
if not m:
    raise SystemExit("No encontré bloque de imágenes (img = ProviderImage() ... hasta if args.subs:)")

i = m.group("i")
img_block = "\n".join([
f"{i}img = ProviderImage()",
f"{i}img_paths: List[str] = []",
f"{i}img_meta: List[Dict[str, Any]] = []",
f"{i}",
f"{i}for j, s in enumerate(scenes, start=1):",
f"{i}    out_path = os.path.join(dirs[\"images_dir\"], f\"{s['scene_id']}.png\")",
f"{i}    if os.path.exists(out_path):",
f"{i}        img_paths.append(out_path)",
f"{i}        img_meta.append({{'provider':'REUSE_RENDER','model':'','mode':'REUSE','cache_hit':True,'cache_key':'','note':'reused existing render/image'}})",
f"{i}        continue",
f"{i}",
f"{i}    full_prompt = \"Imagen vertical 9:16, alta calidad, lista para reel.\\n\\n\" + s[\"image_prompt\"]",
f"{i}    r = img.generate(purpose=f\"scene_image_{'{'}j:02d{'}'}\", prompt=full_prompt, seed=args.seed)",
f"{i}",
f"{i}    if os.path.abspath(r[\"path\"]) != os.path.abspath(out_path):",
f"{i}        try:",
f"{i}            with open(r[\"path\"], \"rb\") as src, open(out_path, \"wb\") as dst:",
f"{i}                dst.write(src.read())",
f"{i}        except Exception:",
f"{i}            out_path = r[\"path\"]",
f"{i}",
f"{i}    img_paths.append(out_path)",
f"{i}    img_meta.append({{k: r.get(k) for k in (\"provider\",\"model\",\"mode\",\"cache_hit\",\"cache_key\",\"note\")}})",
f"{i}",
])
txt = pat_img.sub(img_block, txt, count=1)
print("OK: bloque imágenes reconstruido")

# ---------- 2) BLOQUE AUDIO: desde "tts = ProviderVoice()" hasta antes de "# 5) Render" ----------
pat_aud = re.compile(
    r"(?ms)^(?P<i>[ \t]*)tts\s*=\s*ProviderVoice\(\)\s*\r?\n.*?(?=^(?P=i)#\s*5\)\s*Render)"
)
m2 = pat_aud.search(txt)
if not m2:
    # fallback: antes de video_out =
    pat_aud2 = re.compile(
        r"(?ms)^(?P<i>[ \t]*)tts\s*=\s*ProviderVoice\(\)\s*\r?\n.*?(?=^(?P=i)video_out\s*=)"
    )
    m2 = pat_aud2.search(txt)
    if not m2:
        raise SystemExit("No encontré bloque de audio (tts = ProviderVoice() ... hasta # 5) Render / video_out=)")

i2 = m2.group("i")
aud_block = "\n".join([
f"{i2}tts = ProviderVoice()",
f"{i2}audio_paths: List[str] = []",
f"{i2}audio_meta: List[Dict[str, Any]] = []",
f"{i2}",
f"{i2}for j, s in enumerate(scenes, start=1):",
f"{i2}    existing = None",
f"{i2}    for ext in (\".wav\",\".mp3\",\".m4a\",\".aac\",\".flac\",\".ogg\"):",
f"{i2}        cand = os.path.join(dirs[\"audio_dir\"], f\"{s['scene_id']}{'{'}ext{'}'}\")",
f"{i2}        if os.path.exists(cand):",
f"{i2}            existing = cand",
f"{i2}            break",
f"{i2}",
f"{i2}    if existing:",
f"{i2}        audio_paths.append(existing)",
f"{i2}        audio_meta.append({{'provider':'REUSE_RENDER','model':'','mode':'REUSE','cache_hit':True,'cache_key':'','note':'reused existing render/audio'}})",
f"{i2}        continue",
f"{i2}",
f"{i2}    text = str(s.get(\"voiceover\") or \"\").strip() or \" \"",
f"{i2}    r = tts.speak(purpose=f\"scene_voice_{'{'}j:02d{'}'}\", text=text, seed=args.seed)",
f"{i2}",
f"{i2}    ext = os.path.splitext(r[\"path\"])[1] or \".wav\"",
f"{i2}    out_path = os.path.join(dirs[\"audio_dir\"], f\"{s['scene_id']}{'{'}ext{'}'}\")",
f"{i2}",
f"{i2}    if os.path.abspath(r[\"path\"]) != os.path.abspath(out_path):",
f"{i2}        try:",
f"{i2}            with open(r[\"path\"], \"rb\") as src, open(out_path, \"wb\") as dst:",
f"{i2}                dst.write(src.read())",
f"{i2}        except Exception:",
f"{i2}            out_path = r[\"path\"]",
f"{i2}",
f"{i2}    audio_paths.append(out_path)",
f"{i2}    audio_meta.append({{k: r.get(k) for k in (\"provider\",\"model\",\"mode\",\"cache_hit\",\"cache_key\",\"note\")}})",
f"{i2}",
])
# reemplaza usando el patrón que haya matcheado
if "pat_aud2" in locals() and pat_aud2.search(txt):
    txt = pat_aud2.sub(aud_block, txt, count=1)
else:
    txt = pat_aud.sub(aud_block, txt, count=1)

print("OK: bloque audio reconstruido")

# escribir sin BOM
p.write_text(txt, encoding="utf-8", newline="\n")
print("DONE")
