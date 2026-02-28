from pathlib import Path

path = Path(r".\app\video_pipeline.py")
text = path.read_text(encoding="utf-8")

old = '''        full_prompt = "Imagen vertical 9:16, alta calidad, lista para reel.\\n\\n" + s["image_prompt"]
        r = img.generate(purpose=f"scene_image_{j:02d}", prompt=full_prompt, seed=args.seed)
'''

new = '''        full_prompt = "Imagen vertical 9:16, alta calidad, lista para reel.\\n\\n" + s["image_prompt"]
        stock_query = str(s.get("stock_query") or s.get("image_stock_query") or "").strip()

        gen_kwargs = {}
        if stock_query:
            gen_kwargs["stock_query"] = stock_query

        r = img.generate(
            purpose=f"scene_image_{j:02d}",
            prompt=full_prompt,
            seed=args.seed,
            **gen_kwargs,
        )
'''

if old not in text:
    raise SystemExit("No encontré el bloque de generación de imagen esperado en app/video_pipeline.py")

text = text.replace(old, new, 1)
path.write_text(text, encoding="utf-8")
print("OK: app/video_pipeline.py parcheado para stock_query opcional")
