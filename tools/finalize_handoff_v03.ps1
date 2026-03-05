param(
  [Parameter(Mandatory=$false)][string]$LiveDir,
  [Parameter(Mandatory=$false)][string]$WorkspaceRoot,

  # salida estándar en LIVE:
  [string]$HandoffDirName = "handoff_v03",

  # si quieres forzar regeneración del handoff
  [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null

$repo = (Resolve-Path ".").Path

# Resolver LIVE dir
if (-not $LiveDir -or $LiveDir.Trim().Length -eq 0) {
  if (-not $WorkspaceRoot -or $WorkspaceRoot.Trim().Length -eq 0) { throw "Falta -LiveDir o -WorkspaceRoot" }
  $LiveDir = Join-Path $WorkspaceRoot "runs\smoke_live_latest"
}
$live = (Resolve-Path $LiveDir).Path
if (-not (Test-Path -LiteralPath $live)) { throw "No existe LIVE: $live" }

# Tools requeridos
$ensure = Join-Path $repo "tools\ensure_outputs_live_v03.ps1"
$handoff = Join-Path $repo "tools\handoff_v03.ps1"

if (-not (Test-Path -LiteralPath $ensure))  { throw "Falta tool: $ensure" }
if (-not (Test-Path -LiteralPath $handoff)) { throw "Falta tool: $handoff" }

# 1) Asegura outputs (video / music_auto / final)
pwsh -NoProfile -ExecutionPolicy Bypass -File $ensure -LiveDir $live | Out-Null

$video        = Join-Path $live "video.mp4"
$musicAuto    = Join-Path $live "video_music_auto.mp4"
$final        = Join-Path $live "video_final.mp4"

if (-not (Test-Path -LiteralPath $video))     { throw "Falta output: $video" }
if (-not (Test-Path -LiteralPath $musicAuto)) { throw "Falta output: $musicAuto" }
if (-not (Test-Path -LiteralPath $final))     { throw "Falta output: $final" }

# 2) Handoff dir
$handoffDir = Join-Path $live $HandoffDirName
if ((Test-Path -LiteralPath $handoffDir) -and $Force) {
  Remove-Item -LiteralPath $handoffDir -Recurse -Force
}
# 3) Genera handoff (zip + hashes + ready)
pwsh -NoProfile -ExecutionPolicy Bypass -File $handoff -LiveDir $live -OutDir $handoffDir | Out-Null

$ready  = Join-Path $handoffDir "HANDOFF_READY.txt"
$hashes = Join-Path $handoffDir "HASHES_SHA256.txt"

if (-not (Test-Path -LiteralPath $ready))  { throw "Falta HANDOFF_READY: $ready" }
if (-not (Test-Path -LiteralPath $hashes)) { throw "Falta HASHES: $hashes" }

Write-Host "OK: finalize_handoff_v03 -> $handoffDir" -ForegroundColor Green