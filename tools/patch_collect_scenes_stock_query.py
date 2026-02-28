from pathlib import Path

path = Path(r".\app\video_pipeline.py")
text = path.read_text(encoding="utf-8")

old = '''        out.append(
            {
                "scene_id": scene_id,
                "clip_id": from_clip,
                "voiceover": voiceover,
                "image_prompt": prompt_txt,
            }
        )
'''

new = '''        out.append(
            {
                "scene_id": scene_id,
                "clip_id": from_clip,
                "voiceover": voiceover,
                "image_prompt": prompt_txt,
                "stock_query": str(s.get("stock_query") or "").strip(),
                "image_stock_query": str(s.get("image_stock_query") or "").strip(),
            }
        )
'''

if old not in text:
    raise SystemExit("No encontré el bloque out.append esperado en _collect_scenes")

text = text.replace(old, new, 1)
path.write_text(text, encoding="utf-8")
print("OK: app/video_pipeline.py parcheado para preservar stock_query desde storyboard")
