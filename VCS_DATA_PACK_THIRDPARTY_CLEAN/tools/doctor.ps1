Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$repo = $RepoRoot
. "$PSScriptRoot\resolve_python.ps1"
$py = Resolve-PythonExe -RepoRoot $RepoRoot

function Fail($msg) { Write-Host $msg -ForegroundColor Red; exit 1 }

$ws = $env:STUDIO_WORKSPACE
if (-not $ws) {
  Fail "FATAL: STUDIO_WORKSPACE no está seteado. Ejemplo (persistente):
  [Environment]::SetEnvironmentVariable('STUDIO_WORKSPACE', '$env:USERPROFILE\Documents\STUDIO_WORKSPACE', 'User')"
}

if (-not [IO.Path]::IsPathRooted($ws)) {
  Fail "FATAL: STUDIO_WORKSPACE debe ser ruta absoluta. Actual: $ws"
}

if (!(Test-Path $ws)) { Fail "FATAL: STUDIO_WORKSPACE no existe: $ws" }

$runs = Join-Path $ws "runs"
$out  = Join-Path $ws "output"
$cache = Join-Path $ws "cache"
New-Item -ItemType Directory -Force $runs  | Out-Null
New-Item -ItemType Directory -Force $out   | Out-Null
New-Item -ItemType Directory -Force $cache | Out-Null

# python
Write-Host "python: $py" -ForegroundColor Green

# ffmpeg
try { $ff = (Get-Command ffmpeg -ErrorAction Stop).Source; Write-Host "ffmpeg: $ff" -ForegroundColor Green }
catch { Write-Host "WARN: ffmpeg no está en PATH (render puede fallar si lo necesitas)." -ForegroundColor Yellow }

Write-Host "OK: STUDIO_WORKSPACE = $ws" -ForegroundColor Cyan
Write-Host "OK: runs   = $runs" -ForegroundColor Cyan
Write-Host "OK: output = $out"  -ForegroundColor Cyan
Write-Host "OK: cache  = $cache"  -ForegroundColor Cyan
