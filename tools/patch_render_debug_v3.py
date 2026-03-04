import time, shutil
from pathlib import Path

TARGET = Path("tools/render_pack_v03.py")
if not TARGET.exists():
    raise SystemExit(f"No existe: {TARGET}")

src = TARGET.read_text(encoding="utf-8", errors="replace")

MARK = "# STUDIO_RENDER_DEBUG_PATCH v3"
if MARK in src:
    print("Patch v3 ya estaba aplicado. OK.")
    raise SystemExit(0)

backup = TARGET.with_suffix(f".py.bak_{time.strftime('%Y%m%d_%H%M%S')}")
shutil.copy2(TARGET, backup)
print(f"Backup: {backup}")

inject = r"""
# STUDIO_RENDER_DEBUG_PATCH v3
import os as _studio_os
import tempfile as _studio_tempfile
import subprocess as _studio_subprocess

_STUDIO_ORIG_run        = _studio_subprocess.run
_STUDIO_ORIG_Popen      = _studio_subprocess.Popen
_STUDIO_ORIG_check_call = _studio_subprocess.check_call
_STUDIO_ORIG_call       = _studio_subprocess.call
_STUDIO_ORIG_check_out  = _studio_subprocess.check_output

def _studio_is_ffmpeg(cmd0) -> bool:
    b = _studio_os.path.basename(str(cmd0)).lower()
    return "ffmpeg" in b

def _studio_print_cmd(cmd):
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

def _studio_rewrite_filter_complex(cmd):
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
    td = _studio_tempfile.mkdtemp(prefix="ffmpeg_fg_")
    path = _studio_os.path.join(td, "filter_complex.txt")
    with open(path, "w", encoding="utf-8", newline="\\n") as f:
        f.write(fg_s.strip() + "\\n")

    if _studio_os.environ.get("STUDIO_RENDER_DEBUG", "0") == "1":
        print(f"[debug] wrote filter_complex_script: {path} (len={len(fg_s)})")

    new = list(cmd)
    new[i] = "-filter_complex_script"
    new[i + 1] = path
    return new

def _studio_timeout_kwargs(k: dict) -> dict:
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

lines = src.splitlines(True)

# Inserta DESPUÉS de from __future__ import ...
i = 0
if i < len(lines) and lines[i].startswith("#!"):
    i += 1

for _ in range(2):
    if i < len(lines) and "coding" in lines[i] and lines[i].lstrip().startswith("#"):
        i += 1

while i < len(lines) and (lines[i].strip() == "" or lines[i].lstrip().startswith("#")):
    i += 1

def _starts_doc(s):
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

while i < len(lines) and lines[i].lstrip().startswith("from __future__ import"):
    i += 1

out = "".join(lines[:i]) + inject.lstrip("\n") + "\n" + "".join(lines[i:])
TARGET.write_text(out, encoding="utf-8", newline="\n")
print("Patch v3 aplicado. OK.")
