param(
  # Compat con smoke actual:
  [Parameter(Mandatory=$false)][string]$LiveDir,

  # Compat alternativa (por si lo llamas así en otros lados):
  [Parameter(Mandatory=$false)][string]$WorkspaceRoot,

  [string]$SrtName = "captions_v03.srt",

  # Nombre “canon” nuevo:
  [string]$OutVideoName = "video_subtitles.mp4",

  # Compat nombre viejo:
  [string]$OutVideoLegacyName = "video_subs.mp4",

  # NUEVO: poblar scenes_v03.text desde script_*.txt (determinista)
  [switch]$PopulateFromScriptFiles,

  # NUEVO: permitir placeholder (para no romper smoke)
  [switch]$AllowPlaceholderText,

  # baseline style
  [int]$FontSize = 18,
  [int]$Outline = 2,
  [int]$Shadow = 1,
  [int]$MarginV = 80,
  [int]$Alignment = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null

$repo = (Resolve-Path ".").Path

# Defaults (compat): en smoke queremos robustez determinista
if (-not $PSBoundParameters.ContainsKey("PopulateFromScriptFiles")) { $PopulateFromScriptFiles = $true }
if (-not $PSBoundParameters.ContainsKey("AllowPlaceholderText"))    { $AllowPlaceholderText    = $true }

# Resolver LIVE dir
if (-not $LiveDir -or $LiveDir.Trim().Length -eq 0) {
  if (-not $WorkspaceRoot -or $WorkspaceRoot.Trim().Length -eq 0) {
    throw "Falta -LiveDir o -WorkspaceRoot"
  }
  $LiveDir = Join-Path $WorkspaceRoot "runs\smoke_live_latest"
}

$live = (Resolve-Path $LiveDir).Path
if (-not (Test-Path -LiteralPath $live)) { throw "No existe LIVE: $live" }

$man = Join-Path $live "manifest_v03.json"
if (-not (Test-Path -LiteralPath $man)) { throw "Falta manifest: $man" }

$videoIn = Join-Path $live "video.mp4"
if (-not (Test-Path -LiteralPath $videoIn)) { throw "Falta video.mp4 en LIVE: $videoIn" }

$makeSrt  = Join-Path $repo "tools\make_srt_from_scenes_v03.ps1"
$burnIn   = Join-Path $repo "tools\burn_in_srt_v03.ps1"
$popScene = Join-Path $repo "tools\populate_scene_text_from_scriptfiles_v03.ps1"

if (-not (Test-Path -LiteralPath $makeSrt)) { throw "Falta tool: $makeSrt" }
if (-not (Test-Path -LiteralPath $burnIn))  { throw "Falta tool: $burnIn" }

$srtOut      = Join-Path $live $SrtName
$videoOut    = Join-Path $live $OutVideoName
$videoLegacy = Join-Path $live $OutVideoLegacyName

# 0) (Opcional) Poblar texto real por escena desde script_*.txt (determinista)
if ($PopulateFromScriptFiles) {
  if (Test-Path -LiteralPath $popScene) {
    try {
      pwsh -NoProfile -ExecutionPolicy Bypass -File $popScene `
        -LiveDir $live | Out-Null
      Write-Host "OK: populate_scene_text_from_scriptfiles_v03 aplicado" -ForegroundColor DarkGray
    } catch {
      Write-Host ("WARN: populate_scene_text_from_scriptfiles_v03 falló (se continúa): {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
    }
  } else {
    Write-Host "WARN: tool no existe, se omite populate_scene_text_from_scriptfiles_v03.ps1" -ForegroundColor DarkYellow
  }
}

# 1) Genera SRT desde scenes_v03
if ($AllowPlaceholderText) {
  pwsh -NoProfile -ExecutionPolicy Bypass -File $makeSrt `
    -ManifestPath $man `
    -OutSrtPath $srtOut `
    -AllowPlaceholderText 2>$null | Out-Null
} else {
  pwsh -NoProfile -ExecutionPolicy Bypass -File $makeSrt `
    -ManifestPath $man `
    -OutSrtPath $srtOut 2>$null | Out-Null
}

if (-not (Test-Path -LiteralPath $srtOut)) { throw "No se generó SRT: $srtOut" }
$lenSrt = (Get-Item -LiteralPath $srtOut).Length
if ($lenSrt -lt 10) { throw "SRT demasiado pequeño (posible fallo): $srtOut (bytes=$lenSrt)" }

# 2) Burn-in al video (nombre canon)
pwsh -NoProfile -ExecutionPolicy Bypass -File $burnIn `
  -InVideo $videoIn `
  -SrtPath $srtOut `
  -OutVideo $videoOut `
  -FontSize $FontSize -Outline $Outline -Shadow $Shadow -MarginV $MarginV -Alignment $Alignment | Out-Null

if (-not (Test-Path -LiteralPath $videoOut)) { throw "No se generó video_subtitles: $videoOut" }

# 3) Compat: también escribe el nombre legacy (video_subs.mp4)
Copy-Item -LiteralPath $videoOut -Destination $videoLegacy -Force

$len = (Get-Item -LiteralPath $videoOut).Length
Write-Host "OK: subtitles live -> $videoOut ($len bytes)" -ForegroundColor Green
Write-Host "OK: subtitles live (legacy) -> $videoLegacy" -ForegroundColor DarkGray