import re, time, shutil, os, tempfile
from pathlib import Path

TARGET = Path("tools/render_pack_v03.py")
if not TARGET.exists():
    raise SystemExit(f"No existe: {TARGET}")

src = TARGET.read_text(encoding="utf-8", errors="replace")

MARK = "# STUDIO_RENDER_DEBUG_PATCH v2"
if MARK in src:
    print("Patch v2 ya estaba aplicado. OK.")
    raise SystemExit(0)

backup = TARGET.with_suffix(f".py.bak_{time.strftime('%Y%m%d_%H%M%S')}")
shutil.copy2(TARGET, backup)
print(f"Backup: {backup}")

inject = r"""
# STUDIO_RENDER_DEBUG_PATCH v2
import os as _studio_os
import tempfile as _studio_tempfile
import subprocess as _studio_subprocess

_STUDIO_ORIG_run        = _studio_subprocess.run
_STUDIO_ORIG_Popen      = _studio_subprocess.Popen
_STUDIO_ORIG_check_call = _studio_subprocess.check_call
_STUDIO_ORIG_call       = _studio_subprocess.call
_STUDIO_ORIG_check_out  = _studio_subprocess.check_output

def _studio_is_ffmpeg(cmd0: str) -> bool:
    b = _studio_os.path.basename(str(cmd0)).lower()
    return "ffmpeg" in b

def _studio_rewrite_filter_complex(cmd):
    # Convierte: -filter_complex "<string>"  ->  -filter_complex_script "<file>"
    if not isinstance(cmd, (list, tuple)) or len(cmd) < 3:
        return cmd
    if not _studio_is_ffmpeg(cmd[0]):
        return cmd

    try:
        i = list(cmd).index("-filter_complex")
    except ValueError:
        return cmd

    if i + 1 >= len(cmd):
        return cmd

    if _studio_os.environ.get("STUDIO_FILTER_SCRIPT", "1") != "1":
        return cmd

    fg = cmd[i + 1]
    if fg is None:
        return cmd

    fg_s = str(fg)
    # Si es corto, igual lo pasamos a script para evitar parser/quoting en Windows
    td = _studio_tempfile.mkdtemp(prefix="ffmpeg_fg_")
    path = _studio_os.path.join(td, "filter_complex.txt")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(fg_s.strip() + "\n")

    new = list(cmd)
    new[i] = "-filter_complex_script"
    new[i + 1] = path
    return new

def _studio_print_cmd(cmd):
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

def _studio_timeout_kwargs(k: dict) -> dict:
    # opcional: STUDIO_SUBPROC_TIMEOUT=600
    t = _studio_os.environ.get("STUDIO_SUBPROC_TIMEOUT", "").strip()
    if t and "timeout" not in k:
        try:
            k["timeout"] = int(t)
        except Exception:
            pass
    return k

def run(*p, **k):
    cmd = p[0] if p else k.get("args")
    cmd2 = _studio_rewrite_filter_complex(cmd)
    if _studio_os.environ.get("STUDIO_RENDER_DEBUG", "0") == "1":
        _studio_print_cmd(cmd2)
    if p:
        p = (cmd2,) + tuple(p[1:])
    else:
        k["args"] = cmd2
    k = _studio_timeout_kwargs(k)
    return _STUDIO_ORIG_run(*p, **k)

def Popen(*p, **k):
    cmd = p[0] if p else k.get("args")
    cmd2 = _studio_rewrite_filter_complex(cmd)
    if _studio_os.environ.get("STUDIO_RENDER_DEBUG", "0") == "1":
        _studio_print_cmd(cmd2)
    if p:
        p = (cmd2,) + tuple(p[1:])
    else:
        k["args"] = cmd2
    return _STUDIO_ORIG_Popen(*p, **k)

def check_call(*p, **k):
    cmd = p[0] if p else k.get("args")
    cmd2 = _studio_rewrite_filter_complex(cmd)
    if _studio_os.environ.get("STUDIO_RENDER_DEBUG", "0") == "1":
        _studio_print_cmd(cmd2)
    if p:
        p = (cmd2,) + tuple(p[1:])
    else:
        k["args"] = cmd2
    return _STUDIO_ORIG_check_call(*p, **k)

def call(*p, **k):
    cmd = p[0] if p else k.get("args")
    cmd2 = _studio_rewrite_filter_complex(cmd)
    if _studio_os.environ.get("STUDIO_RENDER_DEBUG", "0") == "1":
        _studio_print_cmd(cmd2)
    if p:
        p = (cmd2,) + tuple(p[1:])
    else:
        k["args"] = cmd2
    return _STUDIO_ORIG_call(*p, **k)

def check_output(*p, **k):
    cmd = p[0] if p else k.get("args")
    cmd2 = _studio_rewrite_filter_complex(cmd)
    if _studio_os.environ.get("STUDIO_RENDER_DEBUG", "0") == "1":
        _studio_print_cmd(cmd2)
    if p:
        p = (cmd2,) + tuple(p[1:])
    else:
        k["args"] = cmd2
    return _STUDIO_ORIG_check_out(*p, **k)

_studio_subprocess.run = run
_studio_subprocess.Popen = Popen
_studio_subprocess.check_call = check_call
_studio_subprocess.call = call
_studio_subprocess.check_output = check_output
"""

# Inserta después del bloque inicial de imports (si no, al inicio)
m = re.search(r'(?ms)\A((?:\s*(?:from\s+\S+\s+import\s+.+|import\s+.+)\s*\n)+)', src)
if not m:
    out = inject.lstrip("\n") + "\n" + src
else:
    out = src[:m.end(1)] + inject + src[m.end(1):]

TARGET.write_text(out, encoding="utf-8", newline="\n")
print("Patch v2 aplicado. OK.")
