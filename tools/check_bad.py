import re
from pathlib import Path

t = Path("app/main.py").read_text(encoding="utf-8")
pat = r"(?:\u00C3.|\u00C2.|\u00E2\u0080.|\uFFFD)"
ms = list(re.finditer(pat, t))
print("BAD=", bool(ms))
print("sample=", [m.group(0) for m in ms[:10]])
