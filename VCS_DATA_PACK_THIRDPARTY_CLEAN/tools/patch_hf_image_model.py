import re, time, shutil
from pathlib import Path

TARGET = Path("studio/providers/image/hf_image.py")
src = TARGET.read_text(encoding="utf-8", errors="replace")

MARK = "# STUDIO_HF_IMAGE_MODEL_CONFIG_v1"
if MARK in src:
    print("Patch ya aplicado. OK.")
    raise SystemExit(0)

bak = TARGET.with_suffix(".py.bak_" + time.strftime("%Y%m%d_%H%M%S"))
shutil.copy2(TARGET, bak)
print("Backup:", bak)

# 1) Insertar DEFAULT_MODEL después del bloque de imports (seguro)
m = re.search(r'(?ms)\A((?:\s*(?:from\s+\S+\s+import\s+.+|import\s+.+)\s*\n)+)', src)
insert = f'\n{MARK}\nDEFAULT_MODEL = "black-forest-labs/FLUX.1-schnell"\n'
if m:
    src = src[:m.end(1)] + insert + src[m.end(1):]
else:
    src = insert + src

# 2) Ajustar __init__: usar config/model si existe
# Busca una línea self.model = "...." o self.model = SOMEVAR
# y la reemplaza por config fallback.
src2 = re.sub(
    r'(?m)^\s*self\.model\s*=\s*.+$',
    '        self.model = (config.get("model") if isinstance(config, dict) and config.get("model") else DEFAULT_MODEL)',
    src,
    count=1
)

if src2 == src:
    print("WARN: no encontré 'self.model = ...' para reemplazar. No se cambió esa parte.")
src = src2

TARGET.write_text(src, encoding="utf-8", newline="\n")
print("Patch aplicado. OK.")
