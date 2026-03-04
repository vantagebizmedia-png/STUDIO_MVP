from pathlib import Path

p = Path(r"app/providers/image_provider.py")
s = p.read_text(encoding="utf-8").splitlines(True)

# Encuentra el inicio de la función _placeholder_png
start = None
for i, line in enumerate(s):
    if line.lstrip().startswith("def _placeholder_png") and "->" in line and "bytes" in line:
        start = i
        break

if start is None:
    raise SystemExit("NO ENCONTRÉ: def _placeholder_png(self) -> bytes:")

# La indentación real de esa función (para no romper el archivo)
indent = s[start].split("def")[0]

# Encuentra el final de la función: el siguiente 'def ' al mismo nivel de indent
end = None
for j in range(start + 1, len(s)):
    if s[j].startswith(indent + "def "):
        end = j
        break
if end is None:
    end = len(s)

# Nuevo cuerpo robusto (720x1280)  siempre válido para MoviePy/Pillow
new_block = [
    f"{indent}def _placeholder_png(self) -> bytes:\n",
    f"{indent}    # Placeholder robusto 9:16 (siempre válido para MoviePy/Pillow)\n",
    f"{indent}    import io\n",
    f"{indent}    from PIL import Image, ImageDraw\n",
    "\n",
    f"{indent}    w, h = 720, 1280\n",
    f"{indent}    img = Image.new('RGB', (w, h), (0, 0, 0))\n",
    f"{indent}    d = ImageDraw.Draw(img)\n",
    f"{indent}    d.text((40, 40), 'STUDIO DRY', fill=(255, 255, 255))\n",
    "\n",
    f"{indent}    buf = io.BytesIO()\n",
    f"{indent}    img.save(buf, format='PNG', optimize=True)\n",
    f"{indent}    return buf.getvalue()\n",
    "\n",
]

s2 = s[:start] + new_block + s[end:]
p.write_text("".join(s2), encoding="utf-8")
print("OK: _placeholder_png reemplazado (robusto 720x1280)")
