from pathlib import Path

path = Path(r".\app\providers\image_provider.py")
text = path.read_text(encoding="utf-8")

old1 = '        meta = {\n            "status": status,\n            "content_type": ctype,\n            "image_content_type": img_ctype,\n'
new1 = '        redacted_search_url = re.sub(r"([?&]key=)[^&]+", r"\\1***REDACTED***", search_url)\n\n        meta = {\n            "status": status,\n            "content_type": ctype,\n            "image_content_type": img_ctype,\n'
if old1 not in text:
    raise SystemExit("No encontré el bloque meta de Pixabay para insertar redaction")
text = text.replace(old1, new1, 1)

old2 = '            "api_search_url": search_url,\n'
new2 = '            "api_search_url": redacted_search_url,\n'
if old2 not in text:
    raise SystemExit("No encontré api_search_url para redacción")
text = text.replace(old2, new2, 1)

old3 = '        return img_bytes, meta\n\n    def _placeholder_png(self) -> bytes:\n'
new3 = '''        return img_bytes, meta

    def _normalize_image_bytes_to_png(self, img_bytes: bytes) -> bytes:
        import io
        from PIL import Image

        try:
            src = Image.open(io.BytesIO(img_bytes))
            if src.mode not in ("RGB", "RGBA"):
                src = src.convert("RGB")
            elif src.mode == "RGBA":
                bg = Image.new("RGB", src.size, (255, 255, 255))
                bg.paste(src, mask=src.split()[-1])
                src = bg

            out = io.BytesIO()
            src.save(out, format="PNG", optimize=True)
            return out.getvalue()
        except Exception as e:
            raise RuntimeError(f"No se pudo normalizar imagen a PNG: {e!r}")

    def _placeholder_png(self) -> bytes:
'''
if old3 not in text:
    raise SystemExit("No encontré el punto para insertar _normalize_image_bytes_to_png")
text = text.replace(old3, new3, 1)

old4 = '        img_bytes, http_meta = self._http_call_with_retry(prompt, params)\n        with open(img_path, "wb") as f:\n'
new4 = '        img_bytes, http_meta = self._http_call_with_retry(prompt, params)\n        if self.provider_type == "pixabay_stock":\n            img_bytes = self._normalize_image_bytes_to_png(img_bytes)\n        with open(img_path, "wb") as f:\n'
if old4 not in text:
    raise SystemExit("No encontré el bloque de escritura de cache LIVE")
text = text.replace(old4, new4, 1)

path.write_text(text, encoding="utf-8")
print("OK: app/providers/image_provider.py parcheado")
