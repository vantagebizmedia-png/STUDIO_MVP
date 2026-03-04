import re, time, shutil
from pathlib import Path

TARGET = Path("tools/render_pack_v03.py")
if not TARGET.exists():
    raise SystemExit(f"No existe: {TARGET}")

src = TARGET.read_text(encoding="utf-8", errors="replace")

MARK = "# STUDIO_RENDER_DEBUG_PATCH v1"
if MARK in src:
    print("Patch ya estaba aplicado. OK.")
    raise SystemExit(0)

backup = TARGET.with_suffix(f".py.bak_{time.strftime('%Y%m%d_%H%M%S')}")
shutil.copy2(TARGET, backup)
print(f"Backup: {backup}")

inject = r'''
{mark}
import os as _studio_os
import subprocess as _studio_subprocess

_STUDIO_ORIG_RUN = _studio_subprocess.run

def _studio_dbg_run(*p, **k):
    # Activa con: $env:STUDIO_RENDER_DEBUG="1"
    if _studio_os.environ.get("STUDIO_RENDER_DEBUG", "0") == "1":
        cmd = None
        if p:
            cmd = p[0]
        else:
            cmd = k.get("args")

        try:
            print("\\n--- SUBPROCESS CMD (debug) ---")
            if isinstance(cmd, (list, tuple)):
                for i, a in enumerate(cmd):
                    print(f"[{i:02d}] {a}")
                try:
                    print("CMDLINE:", _studio_subprocess.list2cmdline([str(x) for x in cmd]))
                except Exception:
                    pass
            else:
                print(cmd)
            print("--- /SUBPROCESS CMD ---\\n")
        except Exception:
            pass

    return _STUDIO_ORIG_RUN(*p, **k)

_studio_subprocess.run = _studio_dbg_run
# (si el script usa "import subprocess", es el mismo módulo y ya queda parcheado)
'''.format(mark=MARK)

# Inserta después del bloque inicial de imports (robusto)
m = re.search(r'(?ms)\A((?:\s*(?:from\s+\S+\s+import\s+.+|import\s+.+)\s*\n)+)', src)
if not m:
    # fallback: inserta al inicio
    out = inject.lstrip("\n") + "\n" + src
else:
    out = src[:m.end(1)] + inject + src[m.end(1):]

TARGET.write_text(out, encoding="utf-8", newline="\n")
print("Patch aplicado. OK.")
