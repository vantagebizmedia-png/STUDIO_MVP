param(
  # Compat con smoke:
  [Parameter(Mandatory=$false)][string]$LiveDir,

  # Compat alternativa:
  [Parameter(Mandatory=$false)][string]$WorkspaceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null

# Resolver LIVE dir
if (-not $LiveDir -or $LiveDir.Trim().Length -eq 0) {
  if (-not $WorkspaceRoot -or $WorkspaceRoot.Trim().Length -eq 0) {
    throw "Falta -LiveDir o -WorkspaceRoot"
  }
  $LiveDir = Join-Path $WorkspaceRoot "runs\smoke_live_latest"
}

$live = (Resolve-Path $LiveDir).Path
if (-not (Test-Path -LiteralPath $live)) { throw "No existe LIVE: $live" }

$videoBase = Join-Path $live "video.mp4"
if (-not (Test-Path -LiteralPath $videoBase)) { throw "Falta video.mp4 en LIVE: $videoBase" }

$musicAuto = Join-Path $live "video_music_auto.mp4"
$final     = Join-Path $live "video_final.mp4"

# Baseline determinista:
# - Si faltan, los creamos como copia exacta de video.mp4 (sin inventar música todavía)
if (-not (Test-Path -LiteralPath $musicAuto)) {
  Copy-Item -LiteralPath $videoBase -Destination $musicAuto -Force
  Write-Host "WARN: faltaba video_music_auto.mp4 -> creado como copia determinista de video.mp4" -ForegroundColor DarkYellow
}

if (-not (Test-Path -LiteralPath $final)) {
  Copy-Item -LiteralPath $videoBase -Destination $final -Force
  Write-Host "WARN: faltaba video_final.mp4 -> creado como copia determinista de video.mp4" -ForegroundColor DarkYellow
}

$lenB = (Get-Item -LiteralPath $videoBase).Length
$lenM = (Get-Item -LiteralPath $musicAuto).Length
$lenF = (Get-Item -LiteralPath $final).Length

Write-Host "OK: ensure outputs live v03 -> video=$lenB music_auto=$lenM final=$lenF" -ForegroundColor Green
