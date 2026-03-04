from __future__ import annotations
import os, re, zipfile
from pathlib import Path

EXCLUDE_PREFIXES = (
    ".venv/",
    "venv/",
    ".mypy_cache/",
    ".pytest_cache/",
    ".git/",
    "workspace/",
    "_trash/",
    "_vcs_extract/",
    "releases/",
    "_release/",
    "output/",
    "music/",
)

EXCLUDE_CONTAINS = ("/__pycache__/", "\\__pycache__\\")
EXCLUDE_EXTS = {".pyc",".pyo",".pyd",".mp4",".mov",".avi",".mkv",".mp3",".wav",".m4a",".aac"}
EXCLUDE_NAME_RE = re.compile(r".*\.bak(_.*)?$|.*\.tmp$|.*~$|.*\.log$", re.IGNORECASE)

def should_keep(rel_posix: str) -> bool:
    p = rel_posix.replace("\\", "/")
    for pref in EXCLUDE_PREFIXES:
        if p.startswith(pref):
            return False
    for c in EXCLUDE_CONTAINS:
        if c.replace("\\", "/") in p:
            return False
    base = os.path.basename(p)
    if EXCLUDE_NAME_RE.match(base):
        return False
    ext = os.path.splitext(base)[1].lower()
    if ext in EXCLUDE_EXTS:
        return False
    return True

def main() -> None:
    repo_root = Path(__file__).resolve().parents[1]
    out_zip = repo_root / "releases" / "STUDIO_MVP_source_clean.zip"
    out_zip.parent.mkdir(parents=True, exist_ok=True)

    kept = 0
    skipped = 0

    with zipfile.ZipFile(out_zip, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for path in repo_root.rglob("*"):
            if path.is_dir():
                continue
            rel = path.relative_to(repo_root).as_posix()
            if not should_keep(rel):
                skipped += 1
                continue
            z.write(path, arcname=f"STUDIO_MVP/{rel}")
            kept += 1

    print(f"OK: {out_zip}")
    print(f"Files kept: {kept} | skipped: {skipped}")

if __name__ == "__main__":
    main()

