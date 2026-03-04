param(
  [string]$WorkspaceRoot = $env:STUDIO_WORKSPACE,
  [string]$Query = "naturaleza agua cascada vertical"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Fail([string]$msg) { throw "SMOKE PIXABAY FAIL: $msg" }

$repo = (Resolve-Path -LiteralPath ".").Path
if (-not $WorkspaceRoot) { Fail "WorkspaceRoot vacío (pasa -WorkspaceRoot o setea STUDIO_WORKSPACE)" }
$ws = (Resolve-Path -LiteralPath $WorkspaceRoot).Path

$out = Join-Path $ws "runs\_pixabay_smoke"
New-Item -ItemType Directory -Force -Path $out | Out-Null

Write-Host "== SMOKE PIXABAY ENGINE v01 =="
Write-Host "Repo : $repo"
Write-Host "WS   : $ws"
Write-Host "Out  : $out"
Write-Host "Query: $Query"

# Usa el python del venv si existe, si no python normal
$py = "python"
if (Test-Path -LiteralPath ".\.venv\Scripts\python.exe") { $py = ".\.venv\Scripts\python.exe" }

$code = @"
from pathlib import Path
from studio.pixabay_engine_v01 import fetch_and_normalize
p, hit = fetch_and_normalize(r'''$Query''', out_dir=Path(r'''$out'''))
print("OK:", str(p))
if hit:
  print("HIT:", hit.id, hit.width, hit.height, hit.size, hit.page_url)
"@

& $py -c $code

# asserts
$files = Get-ChildItem -LiteralPath $out -File | Select-Object -ExpandProperty FullName
if (-not ($files | Where-Object { $_ -like "*_9x16.mp4" })) { Fail "No se generó *_9x16.mp4 en $out" }
if (-not ($files | Where-Object { $_ -like "*_raw.mp4" }))  { Fail "No se generó *_raw.mp4 en $out" }

Write-Host "SMOKE OK: pixabay_engine_v01 descargó y normalizó en: $out"
