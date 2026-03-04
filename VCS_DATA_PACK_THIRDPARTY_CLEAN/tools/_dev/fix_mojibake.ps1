param(
  [string]$Path = ".\app\video_pipeline.py",
  [int]$MaxPasses = 3
)

$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

if (!(Test-Path $Path)) { throw "No existe: $Path" }

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
Copy-Item $Path "$Path.bak_mojibake_$ts" -Force
Write-Host "Backup: $Path.bak_mojibake_$ts"

$py = @'
from __future__ import annotations
from pathlib import Path
import sys

p = Path(sys.argv[1])
max_passes = int(sys.argv[2])

s = p.read_text(encoding="utf-8", errors="replace")

def score(x: str) -> int:
    bad = [
        "\uFFFD",
        "\u00C3", "\u00C2", "\u00E2", "\u0192",
        "\u252C", "\u251C", "\u255E",
        "\u2020", "\u20AC", "\u2122"
    ]
    return sum(x.count(ch) for ch in bad)

orig = s
orig_score = score(orig)

for _ in range(max_passes):
    cand = s.encode("cp1252", errors="replace").decode("utf-8", errors="replace")
    if score(cand) < score(s):
        s = cand
    else:
        break

new_score = score(s)

if s != orig:
    p.write_text(s, encoding="utf-8", newline="\n")
    print(f"OK: mojibake reducido score {orig_score} -> {new_score}")
else:
    print(f"OK: sin cambios (score={new_score})")

lines = s.splitlines()
if len(lines) > 1:
    print("PREVIEW_LINE_2:", lines[1])
'@

$tmp = Join-Path $env:TEMP "fix_mojibake_tmp.py"
Set-Content -LiteralPath $tmp -Value $py -Encoding UTF8
python $tmp $Path $MaxPasses
Remove-Item $tmp -Force

python -c "import py_compile; py_compile.compile(r'app/video_pipeline.py', doraise=True); print('PASS: compila')"
Write-Host "OK: fix mojibake ejecutado"