param(
  # Workspace root (si vacío usa env:STUDIO_WORKSPACE)
  [string]$WorkspaceRoot = "",

  # Pack opcional (exports/pack_v03_...). Si lo pasas, corre finalize full + smoke finalize también.
  [string]$PackDir = "",

  # Scene Builder
  [int]$MaxScenes = 6,

  # Subtitles style
  [string]$SrtName = "captions_v03.srt",
  [int]$FontSize = 52,
  [int]$MarginV  = 120,
  [int]$Outline  = 3,

  # Music (opcional) para finalize pack
  [string]$MusicFile = "",
  [double]$MusicVolume = 0.22,
  [double]$DuckingRatio = 8.0,

  # Expect music outputs (solo aplica si PackDir)
  [switch]$ExpectMusic
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null

$repo = (Resolve-Path ".").Path

function Require-File {
  param([Parameter(Mandatory=$true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { throw "Falta: $Path" }
}

if (-not $WorkspaceRoot -or $WorkspaceRoot.Trim().Length -lt 3) {
  $WorkspaceRoot = $env:STUDIO_WORKSPACE
}
if (-not $WorkspaceRoot -or $WorkspaceRoot.Trim().Length -lt 3) {
  throw "Falta WorkspaceRoot y env:STUDIO_WORKSPACE no está seteado."
}

# -------------------------
# Preflight: scripts requeridos
# -------------------------
$smToWs       = Join-Path $repo "tools\smoke_live_to_workspace_v03.ps1"
$smLiveMan    = Join-Path $repo "tools\smoke_live_manifest_v03.ps1"
$apSubsLive   = Join-Path $repo "tools\apply_subtitles_live_v03.ps1"
$smSubsLive   = Join-Path $repo "tools\smoke_subtitles_live_v03.ps1"

Require-File $smToWs
Require-File $smLiveMan
Require-File $apSubsLive
Require-File $smSubsLive

$smFinalizeFull = Join-Path $repo "tools\smoke_finalize_full_v03.ps1"
if ($PackDir -and $PackDir.Trim().Length -ge 3) {
  Require-File $smFinalizeFull
}

Write-Host "== SMOKE E2E v0.3 ==" -ForegroundColor Cyan
Write-Host ("Repo      : " + $repo) -ForegroundColor DarkGray
Write-Host ("Workspace : " + $WorkspaceRoot) -ForegroundColor DarkGray
Write-Host ("MaxScenes : " + $MaxScenes) -ForegroundColor DarkGray

# -------------------------
# 1) LIVE -> workspace stable dir
# -------------------------
Write-Host "`n[1/5] LIVE: smoke -> workspace (stable live dir)" -ForegroundColor Yellow
$outLines = & pwsh -NoProfile -ExecutionPolicy Bypass -File $smToWs -WorkspaceRoot $WorkspaceRoot -CleanRepoOutputs
$line = ($outLines | Where-Object { $_ -match '^LIVE_WORKSPACE_DIR=' } | Select-Object -Last 1)
if (-not $line) {
  throw "No pude leer LIVE_WORKSPACE_DIR desde smoke_live_to_workspace_v03.ps1. Salida=`n$($outLines -join "`n")"
}
$live = ($line -replace '^LIVE_WORKSPACE_DIR=', '').Trim()
if (-not (Test-Path $live)) { throw "LIVE_WORKSPACE_DIR no existe: $live" }

# -------------------------
# 2) LIVE: validar manifest v03
# -------------------------
Write-Host "`n[2/5] LIVE: smoke_live_manifest_v03 (live=$live)" -ForegroundColor Yellow
pwsh -NoProfile -ExecutionPolicy Bypass -File $smLiveMan -LiveDir $live -MaxScenes $MaxScenes

# -------------------------
# 3) LIVE: aplicar subtítulos (crea video.mp4 base si hace falta)
# -------------------------
Write-Host "`n[3/5] LIVE: apply_subtitles_live_v03 (burn-in + SRT)" -ForegroundColor Yellow
pwsh -NoProfile -ExecutionPolicy Bypass -File $apSubsLive `
  -LiveDir $live `
  -SrtName $SrtName `
  -FontSize $FontSize -MarginV $MarginV -Outline $Outline

# -------------------------
# 4) LIVE: smoke subtitles
# -------------------------
Write-Host "`n[4/5] LIVE: smoke_subtitles_live_v03" -ForegroundColor Yellow
pwsh -NoProfile -ExecutionPolicy Bypass -File $smSubsLive -LiveDir $live -MaxScenes $MaxScenes -SrtName $SrtName

# -------------------------
# 5) PACK (opcional)
# -------------------------
if ($PackDir -and $PackDir.Trim().Length -ge 3) {
  $pack = (Resolve-Path $PackDir).Path
  Write-Host "`n[5/5] PACK: smoke_finalize_full_v03 (pack=$pack)" -ForegroundColor Yellow

  if ($MusicFile -and $MusicFile.Trim().Length -gt 0) {
    pwsh -NoProfile -ExecutionPolicy Bypass -File $smFinalizeFull `
      -PackDir $pack `
      -MaxScenes $MaxScenes `
      -SrtName $SrtName -FontSize $FontSize -MarginV $MarginV -Outline $Outline `
      -MusicFile $MusicFile -MusicVolume $MusicVolume -DuckingRatio $DuckingRatio `
      $(if ($ExpectMusic) { "-ExpectMusic" } else { "" })
  } else {
    pwsh -NoProfile -ExecutionPolicy Bypass -File $smFinalizeFull `
      -PackDir $pack `
      -MaxScenes $MaxScenes `
      -SrtName $SrtName -FontSize $FontSize -MarginV $MarginV -Outline $Outline `
      $(if ($ExpectMusic) { "-ExpectMusic" } else { "" })
  }
} else {
  Write-Host "`n[5/5] PACK: (omitido) No pasaste -PackDir" -ForegroundColor DarkYellow
}

Write-Host "`nSMOKE OK: E2E v0.3 (LIVE(workspace) + optional PACK)" -ForegroundColor Green
