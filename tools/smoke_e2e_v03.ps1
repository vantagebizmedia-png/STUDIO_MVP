param(
  # LIVE (smoke) dir opcional. Si no lo pasas, usa _v03_smoke_cfg\artifacts o autodiscovery.
  [string]$LiveDir = "",

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

function Resolve-LiveDir {
  param([string]$LiveDirIn)

  if ($LiveDirIn -and $LiveDirIn.Trim().Length -ge 3) {
    return (Resolve-Path $LiveDirIn).Path
  }

  $cand = Join-Path $repo "_v03_smoke_cfg\artifacts"
  if (Test-Path -LiteralPath $cand) { return (Resolve-Path $cand).Path }

  # fallback: busca manifest_v03.json más reciente fuera de exports/_freeze
  $man = Get-ChildItem -LiteralPath $repo -Recurse -File -Filter manifest_v03.json -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\exports\\|\\_freeze_|\\__pycache__\\|\\.venv\\' } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

  if (-not $man) { throw "No pude descubrir LIVE dir: no encontré manifest_v03.json LIVE dentro del repo." }
  return (Split-Path $man.FullName -Parent)
}

# -------------------------
# 0) Preflight: scripts requeridos
# -------------------------
$studioSmoke = Join-Path $repo "tools\studio.ps1"
$smLiveMan   = Join-Path $repo "tools\smoke_live_manifest_v03.ps1"
$apSubsLive  = Join-Path $repo "tools\apply_subtitles_live_v03.ps1"
$smSubsLive  = Join-Path $repo "tools\smoke_subtitles_live_v03.ps1"

Require-File $studioSmoke
Require-File $smLiveMan
Require-File $apSubsLive
Require-File $smSubsLive

# Pack-related (opcionales si PackDir)
$smFinalizeFull = Join-Path $repo "tools\smoke_finalize_full_v03.ps1"
if ($PackDir -and $PackDir.Trim().Length -ge 3) {
  Require-File $smFinalizeFull
}

Write-Host "== SMOKE E2E v0.3 ==" -ForegroundColor Cyan
Write-Host ("Repo     : " + $repo) -ForegroundColor DarkGray
Write-Host ("MaxScenes : " + $MaxScenes) -ForegroundColor DarkGray
# -------------------------
# 1) LIVE: corre smoke y COPIA live artifacts al WORKSPACE (ruta estable)
# -------------------------
Write-Host "`n[1/5] LIVE: smoke -> workspace (stable live dir)" -ForegroundColor Yellow
$smToWs = Join-Path $repo "tools\smoke_live_to_workspace_v03.ps1"
Require-File $smToWs

$wsRoot = $env:STUDIO_WORKSPACE
if (-not $wsRoot) { throw "Falta env:STUDIO_WORKSPACE (setéalo antes de correr smoke_e2e_v03.ps1)" }

# capturamos el LIVE_WORKSPACE_DIR desde la salida
$outLines = & pwsh -NoProfile -ExecutionPolicy Bypass -File $smToWs -WorkspaceRoot $wsRoot -CleanRepoOutputs
$line = ($outLines | Where-Object { param(
  # LIVE (smoke) dir opcional. Si no lo pasas, usa _v03_smoke_cfg\artifacts o autodiscovery.
  [string]$LiveDir = "",

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

function Resolve-LiveDir {
  param([string]$LiveDirIn)

  if ($LiveDirIn -and $LiveDirIn.Trim().Length -ge 3) {
    return (Resolve-Path $LiveDirIn).Path
  }

  $cand = Join-Path $repo "_v03_smoke_cfg\artifacts"
  if (Test-Path -LiteralPath $cand) { return (Resolve-Path $cand).Path }

  # fallback: busca manifest_v03.json más reciente fuera de exports/_freeze
  $man = Get-ChildItem -LiteralPath $repo -Recurse -File -Filter manifest_v03.json -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\exports\\|\\_freeze_|\\__pycache__\\|\\.venv\\' } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

  if (-not $man) { throw "No pude descubrir LIVE dir: no encontré manifest_v03.json LIVE dentro del repo." }
  return (Split-Path $man.FullName -Parent)
}

# -------------------------
# 0) Preflight: scripts requeridos
# -------------------------
$studioSmoke = Join-Path $repo "tools\studio.ps1"
$smLiveMan   = Join-Path $repo "tools\smoke_live_manifest_v03.ps1"
$apSubsLive  = Join-Path $repo "tools\apply_subtitles_live_v03.ps1"
$smSubsLive  = Join-Path $repo "tools\smoke_subtitles_live_v03.ps1"

Require-File $studioSmoke
Require-File $smLiveMan
Require-File $apSubsLive
Require-File $smSubsLive

# Pack-related (opcionales si PackDir)
$smFinalizeFull = Join-Path $repo "tools\smoke_finalize_full_v03.ps1"
if ($PackDir -and $PackDir.Trim().Length -ge 3) {
  Require-File $smFinalizeFull
}

Write-Host "== SMOKE E2E v0.3 ==" -ForegroundColor Cyan
Write-Host ("Repo     : " + $repo) -ForegroundColor DarkGray
Write-Host ("MaxScenes : " + $MaxScenes) -ForegroundColor DarkGray

# -------------------------
# 1) LIVE: corre smoke estándar (genera _v03_smoke_cfg\artifacts)
# -------------------------
Write-Host "`n[1/5] LIVE: tools/studio.ps1 -Mode smoke" -ForegroundColor Yellow
pwsh -NoProfile -ExecutionPolicy Bypass -File $studioSmoke -Mode smoke

# -------------------------
# 2) LIVE: validar manifest v03 (scene_builder_v03 + scenes_v03)
# -------------------------
$live = Resolve-LiveDir -LiveDirIn $LiveDir
Write-Host "`n[2/5] LIVE: smoke_live_manifest_v03 (live=$live)" -ForegroundColor Yellow
pwsh -NoProfile -ExecutionPolicy Bypass -File $smLiveMan -LiveDir $live -MaxScenes $MaxScenes

# -------------------------
# 3) LIVE: aplicar subtítulos (si hace falta crea video.mp4 base)
# -------------------------
Write-Host "`n[3/5] LIVE: apply_subtitles_live_v03 (burn-in + SRT)" -ForegroundColor Yellow
pwsh -NoProfile -ExecutionPolicy Bypass -File $apSubsLive `
  -LiveDir $live `
  -SrtName $SrtName `
  -FontSize $FontSize -MarginV $MarginV -Outline $Outline

# -------------------------
# 4) LIVE: smoke subtitles (valida video.mp4, srt y video_subtitles.mp4)
# -------------------------
Write-Host "`n[4/5] LIVE: smoke_subtitles_live_v03" -ForegroundColor Yellow
pwsh -NoProfile -ExecutionPolicy Bypass -File $smSubsLive -LiveDir $live -MaxScenes $MaxScenes -SrtName $SrtName

# -------------------------
# 5) PACK (opcional): finalize full + smoke finalize
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

Write-Host "`nSMOKE OK: E2E v0.3 (LIVE + optional PACK)" -ForegroundColor Green
 -match "^LIVE_WORKSPACE_DIR=" } | Select-Object -Last 1)
if (-not $line) { throw "No pude leer LIVE_WORKSPACE_DIR desde smoke_live_to_workspace_v03.ps1" }
$live = ($line -replace "^LIVE_WORKSPACE_DIR=", "").Trim()
if (-not (Test-Path $live)) { throw "LIVE_WORKSPACE_DIR no existe: $live" }

# -------------------------
# 2) LIVE: validar manifest v03 (scene_builder_v03 + scenes_v03)
# -------------------------
Write-Host "`n[2/5] LIVE: smoke_live_manifest_v03 (live=$live)" -ForegroundColor Yellow
Write-Host "`n[2/5] LIVE: smoke_live_manifest_v03 (live=$live)" -ForegroundColor Yellow
pwsh -NoProfile -ExecutionPolicy Bypass -File $smLiveMan -LiveDir $live -MaxScenes $MaxScenes

# -------------------------
# 3) LIVE: aplicar subtítulos (si hace falta crea video.mp4 base)
# -------------------------
Write-Host "`n[3/5] LIVE: apply_subtitles_live_v03 (burn-in + SRT)" -ForegroundColor Yellow
pwsh -NoProfile -ExecutionPolicy Bypass -File $apSubsLive `
  -LiveDir $live `
  -SrtName $SrtName `
  -FontSize $FontSize -MarginV $MarginV -Outline $Outline

# -------------------------
# 4) LIVE: smoke subtitles (valida video.mp4, srt y video_subtitles.mp4)
# -------------------------
Write-Host "`n[4/5] LIVE: smoke_subtitles_live_v03" -ForegroundColor Yellow
pwsh -NoProfile -ExecutionPolicy Bypass -File $smSubsLive -LiveDir $live -MaxScenes $MaxScenes -SrtName $SrtName

# -------------------------
# 5) PACK (opcional): finalize full + smoke finalize
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

Write-Host "`nSMOKE OK: E2E v0.3 (LIVE + optional PACK)" -ForegroundColor Green

