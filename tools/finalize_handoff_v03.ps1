param(
  # Compat con smoke actual:
  [Parameter(Mandatory=$false)][string]$LiveDir,

  # Compat alternativa:
  [Parameter(Mandatory=$false)][string]$WorkspaceRoot,

  [Parameter(Mandatory=$true)][string]$OutDir,

  # passthrough opcional hacia finalize_handoff_v03.py (solo si existe pack.json)
  [switch]$AutoMusic,
  [string]$MusicDir = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null

$repo = (Resolve-Path ".").Path

# Resolver LIVE dir
if (-not $LiveDir -or $LiveDir.Trim().Length -eq 0) {
  if (-not $WorkspaceRoot -or $WorkspaceRoot.Trim().Length -eq 0) {
    throw "Falta -LiveDir o -WorkspaceRoot"
  }
  $LiveDir = Join-Path $WorkspaceRoot "runs\smoke_live_latest"
}

$live = (Resolve-Path $LiveDir).Path
if (-not (Test-Path -LiteralPath $live)) { throw "No existe LIVE: $live" }

# Asegura directorio de salida
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# Requeridos base en LIVE (smoke/live contract)
$need = @(
  (Join-Path $live "manifest_v03.json"),
  (Join-Path $live "video.mp4"),
  (Join-Path $live "video_final.mp4"),
  (Join-Path $live "video_music_auto.mp4"),
  (Join-Path $live "captions_v03.srt")
)
foreach ($p in $need) {
  if (-not (Test-Path -LiteralPath $p)) { throw "Falta required LIVE output: $p" }
}

# Subtitles canon preferido + fallback legacy
$subsCanon  = Join-Path $live "video_subtitles.mp4"
$subsLegacy = Join-Path $live "video_subs.mp4"

if (-not (Test-Path -LiteralPath $subsCanon)) {
  if (Test-Path -LiteralPath $subsLegacy) {
    Copy-Item -LiteralPath $subsLegacy -Destination $subsCanon -Force
    Write-Host "WARN: faltaba video_subtitles.mp4; reusando legacy video_subs.mp4 -> canon" -ForegroundColor DarkYellow
  } else {
    throw "Falta subtitles video en LIVE: $subsCanon (y tampoco existe legacy $subsLegacy)"
  }
}

# ---------------------------------------------------------
# IMPORTANTE:
# finalize_handoff_v03.py requiere pack.json (modo pack).
# En smoke/live NO hay pack.json => NO lo llamamos.
# ---------------------------------------------------------
$packJson = Join-Path $live "pack.json"
$py = Join-Path $repo "tools\finalize_handoff_v03.py"

if (Test-Path -LiteralPath $packJson) {
  if (-not (Test-Path -LiteralPath $py)) { throw "Falta: $py (pero existe pack.json, esperado en modo pack)" }

  $pyArgs = @("--pack-dir", $live)
  if ($AutoMusic) { $pyArgs += "--auto-music" }
  if ($MusicDir -and $MusicDir.Trim().Length -gt 0) { $pyArgs += @("--music-dir", $MusicDir) }

  & python $py @pyArgs
  if ($LASTEXITCODE -ne 0) { throw "FAIL: finalize_handoff_v03.py ExitCode=$LASTEXITCODE" }

  Write-Host "OK: finalize_handoff_v03.py ejecutado (pack.json presente)" -ForegroundColor DarkGray
} else {
  Write-Host "WARN: no existe pack.json en LIVE -> skip finalize_handoff_v03.py (modo smoke/live)" -ForegroundColor DarkYellow
}

# 1) Construye handoff canon en OutDir (determinista, explícito)
Copy-Item -LiteralPath (Join-Path $live "manifest_v03.json")       -Destination (Join-Path $OutDir "manifest_v03.json")       -Force
Copy-Item -LiteralPath (Join-Path $live "video.mp4")              -Destination (Join-Path $OutDir "video.mp4")              -Force
Copy-Item -LiteralPath (Join-Path $live "video_final.mp4")        -Destination (Join-Path $OutDir "video_final.mp4")        -Force
Copy-Item -LiteralPath (Join-Path $live "video_music_auto.mp4")   -Destination (Join-Path $OutDir "video_music_auto.mp4")   -Force
Copy-Item -LiteralPath (Join-Path $live "video_subtitles.mp4")    -Destination (Join-Path $OutDir "video_subtitles.mp4")    -Force
Copy-Item -LiteralPath (Join-Path $live "captions_v03.srt")       -Destination (Join-Path $OutDir "captions_v03.srt")       -Force

# 2) Validación mínima para no llegar roto a handoff_pack
$must = @(
  (Join-Path $OutDir "manifest_v03.json"),
  (Join-Path $OutDir "video.mp4"),
  (Join-Path $OutDir "video_final.mp4"),
  (Join-Path $OutDir "video_music_auto.mp4"),
  (Join-Path $OutDir "video_subtitles.mp4"),
  (Join-Path $OutDir "captions_v03.srt")
)
foreach ($p in $must) {
  if (-not (Test-Path -LiteralPath $p)) { throw "FAIL: finalize no dejó required en handoff: $p" }
}

Write-Host "OK: finalize_handoff_v03.ps1 -> $OutDir" -ForegroundColor Green
