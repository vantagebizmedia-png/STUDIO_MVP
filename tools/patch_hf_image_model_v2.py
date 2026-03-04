import re, time, shutil
from pathlib import Path

TARGET = Path("studio/providers/image/hf_image.py")
src = TARGET.read_text(encoding="utf-8", errors="replace")

MARK = "# STUDIO_HF_IMAGE_MODEL_CONFIG_v2"
if MARK in src:
    print("Patch v2 ya aplicado. OK.")
    raise SystemExit(0)

bak = TARGET.with_suffix(".py.bak_" + time.strftime("%Y%m%d_%H%M%S"))
shutil.copy2(TARGET, bak)
print("Backup:", bak)

lines = src.splitlines(True)

# --- calcular índice seguro de inserción: después de shebang/encoding/docstring y después de from __future__ ---
i = 0
if i < len(lines) and lines[i].startswith("#!"):
    i += 1

for _ in range(2):
    if i < len(lines) and "coding" in lines[i] and lines[i].lstrip().startswith("#"):
        i += 1

while i < len(lines) and (lines[i].strip() == "" or lines[i].lstrip().startswith("#")):
    i += 1

def _starts_doc(s: str) -> bool:
    ss = s.lstrip()
    return ss.startswith('"""') or ss.startswith("'''")

if i < len(lines) and _starts_doc(lines[i]):
    q = '"""' if lines[i].lstrip().startswith('"""') else "'''"
    if lines[i].count(q) >= 2:
        i += 1
    else:
        i += 1
        while i < len(lines) and q not in lines[i]:
            i += 1
        if i < len(lines):
            i += 1

while i < len(lines) and (lines[i].strip() == "" or lines[i].lstrip().startswith("#")):
    i += 1

# consumir from __future__ import ...
while i < len(lines) and lines[i].lstrip().startswith("from __future__ import"):
    i += 1

insert = f'\n{MARK}\nDEFAULT_MODEL = "black-forest-labs/FLUX.1-schnell"\n'
src = "".join(lines[:i]) + insert + "".join(lines[i:])

# --- patch model configurable solo si __init__ tiene arg config/cfg ---
m_init = re.search(r'(?m)^\s*def\s+__init__\s*\(([^)]*)\)\s*:', src)
cfg_name = None
if m_init:
    params = m_init.group(1)
    # detecta nombre de arg para dict config
    for cand in ("config", "cfg"):
        if re.search(rf'(^|[\s,]){cand}([\s,=:]|$)', params):
            cfg_name = cand
            break

if cfg_name:
    # reemplaza la primera asignación a self.model dentro del archivo (solo 1)
    src2, n = re.subn(
        r'(?m)^(\s*self\.model\s*=\s*).+$',
        rf'\1({cfg_name}.get("model") if isinstance({cfg_name}, dict) and {cfg_name}.get("model") else DEFAULT_MODEL)',
        src,
        count=1
    )
    src = src2
    print(f"OK: model configurable via {cfg_name}.")
else:
    print("WARN: __init__ no tiene arg config/cfg; solo se agregó DEFAULT_MODEL (sin config).")

TARGET.write_text(src, encoding="utf-8", newline="\n")
print("Patch v2 aplicado. OK.")
