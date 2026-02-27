from pathlib import Path

path = Path(r".\app\video_pipeline.py")
text = path.read_text(encoding="utf-8")

old_collect = '''        out.append(
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

new_collect = '''        out.append(
            {
                "scene_id": scene_id,
                "clip_id": from_clip,
                "voiceover": voiceover,
                "image_prompt": prompt_txt,
                "stock_query": str(s.get("stock_query") or "").strip(),
                "image_stock_query": str(s.get("image_stock_query") or "").strip(),
                "image_source_mode": str(s.get("image_source_mode") or "").strip(),
                "image_provider_override": str(s.get("image_provider_override") or "").strip(),
            }
        )
'''

if old_collect not in text:
    raise SystemExit("No encontré el bloque _collect_scenes esperado")
text = text.replace(old_collect, new_collect, 1)

old_init = '''    # 3) Generar imágenes (REUSE si ya existen para ahorrar API)
    img = ProviderImage()
    img_paths: List[str] = []
    img_meta: List[Dict[str, Any]] = []
'''

new_init = '''    # 3) Generar imágenes (REUSE si ya existen para ahorrar API)
    default_img = ProviderImage()
    img_paths: List[str] = []
    img_meta: List[Dict[str, Any]] = []

    def _build_image_provider_override(provider_name: str) -> ProviderImage:
        cfg_obj = _read_json(default_img.config_path)
        cfg_obj.setdefault("image", {})
        cfg_obj["image"]["active_provider"] = provider_name

        tmp_cfg_path = os.path.join(dirs["render_dir"], f"_providers_image_{provider_name}.json")
        _write_json(tmp_cfg_path, cfg_obj)
        return ProviderImage(config_path=tmp_cfg_path)

    image_provider_cache: Dict[str, ProviderImage] = {
        default_img.active_provider: default_img
    }
'''

if old_init not in text:
    raise SystemExit("No encontré el bloque de inicialización de ProviderImage")
text = text.replace(old_init, new_init, 1)

old_loop = '''        full_prompt = "Imagen vertical 9:16, alta calidad, lista para reel.\\n\\n" + s["image_prompt"]
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

new_loop = '''        full_prompt = "Imagen vertical 9:16, alta calidad, lista para reel.\\n\\n" + s["image_prompt"]
        stock_query = str(s.get("stock_query") or s.get("image_stock_query") or "").strip()
        image_source_mode = str(s.get("image_source_mode") or "").strip().lower()
        provider_override = str(s.get("image_provider_override") or "").strip()

        chosen_provider_name = provider_override
        if not chosen_provider_name and image_source_mode == "stock":
            chosen_provider_name = "pixabay_images"

        current_img = default_img
        if chosen_provider_name:
            if chosen_provider_name not in image_provider_cache:
                image_provider_cache[chosen_provider_name] = _build_image_provider_override(chosen_provider_name)
            current_img = image_provider_cache[chosen_provider_name]

        gen_kwargs = {}
        if stock_query:
            gen_kwargs["stock_query"] = stock_query

        r = current_img.generate(
            purpose=f"scene_image_{j:02d}",
            prompt=full_prompt,
            seed=args.seed,
            **gen_kwargs,
        )
'''

if old_loop not in text:
    raise SystemExit("No encontré el bloque de generate por escena")
text = text.replace(old_loop, new_loop, 1)

path.write_text(text, encoding="utf-8")
print("OK: app/video_pipeline.py parcheado con routing por escena")
