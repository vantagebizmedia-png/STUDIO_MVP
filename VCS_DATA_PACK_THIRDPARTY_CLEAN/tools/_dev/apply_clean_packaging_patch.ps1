param([switch]$MakeZip)

function Write-File([string]$Path, [string]$Content) {
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
  [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false, $false)))
  Write-Host ("OK: escrito {0}" -f $Path)
}# 1) .gitignore (append simple; no rompe nada)
$marker = '# --- STUDIO_MVP: runtime/basura NO versionada ---'
if (!(Test-Path .\.gitignore)) { Set-Content .\.gitignore '' -Encoding UTF8 }
$gi = Get-Content .\.gitignore -Raw
if ($gi -notmatch [regex]::Escape($marker)) {
  Add-Content .\.gitignore @'
# --- STUDIO_MVP: runtime/basura NO versionada ---
_trash/
_vcs_extract/
output/
workspace/
__pycache__/
*.pyc
*.pyo
*.pyd
music/*.mp3
music/*.wav
music/*.m4a
music/*.aac
*.mp4
*.mov
*.avi
*.mkv
# --- end ---
'@
  Write-Host 'OK: .gitignore actualizado'
} else {
  Write-Host 'OK: .gitignore ya tenía el bloque'
}

# 2) make_release_zip.py
$zipPy = @'
from __future__ import annotations
import os, re, zipfile
from pathlib import Path

EXCLUDE_PREFIXES = (
    ".git/","workspace/","_trash/","_vcs_extract/","releases/","_release/","output/","music/",
)
EXCLUDE_CONTAINS = ("/__pycache__/", "\\\\__pycache__\\\\")
EXCLUDE_EXTS = {".pyc",".pyo",".pyd",".mp4",".mov",".avi",".mkv",".mp3",".wav",".m4a",".aac"}
EXCLUDE_NAME_RE = re.compile(r".*\\.bak(_.*)?$|.*\\.tmp$|.*~$|.*\\.log$", re.IGNORECASE)

def should_keep(rel_posix: str) -> bool:
    p = rel_posix.replace("\\\\", "/")
    for pref in EXCLUDE_PREFIXES:
        if p.startswith(pref): return False
    for c in EXCLUDE_CONTAINS:
        if c.replace("\\\\","/") in p: return False
    base = os.path.basename(p)
    if EXCLUDE_NAME_RE.match(base): return False
    ext = os.path.splitext(base)[1].lower()
    if ext in EXCLUDE_EXTS: return False
    return True

def main() -> None:
    repo_root = Path(__file__).resolve().parents[1]
    out_zip = repo_root / "releases" / "STUDIO_MVP_source_clean.zip"
    out_zip.parent.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(out_zip, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for path in repo_root.rglob("*"):
            if path.is_dir():
                continue
            rel = path.relative_to(repo_root).as_posix()
            if not should_keep(rel):
                continue
            z.write(path, arcname=f"STUDIO_MVP/{rel}")

    print(f"OK: {out_zip}")

if __name__ == "__main__":
    main()
'@

Write-File .\tools\make_release_zip.py $zipPy
Write-File .\tools\make_release_zip.ps1 "python .\tools\make_release_zip.py
"

python -m compileall .\app -q
Write-Host 'OK: compileall .\app'

if ($MakeZip) {
  python .\tools\make_release_zip.py
  Write-Host 'OK: ZIP generado'
} else {
  Write-Host 'TIP: para generar ZIP: .\tools\make_release_zip.ps1'
}
