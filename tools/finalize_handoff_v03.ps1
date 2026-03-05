param(
  [Parameter(Mandatory=$false)][string]$LiveDir,
  [Parameter(Mandatory=$false)][string]$WorkspaceRoot,

  # salida estándar en LIVE:
  [string]$HandoffDirName = "handoff_v03",

  # si quieres forzar regeneración del handoff
  [switch]$Force,

  # nombre ZIP resultante
  [string]$ZipName = "handoff_v03.zip"
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null

$repo = (Resolve-Path ".").Path

function Ensure-Dir([string]$p) {
  if (-not (Test-Path -LiteralPath $p)) {
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}
function Write-Hashes([string]$dir, [string]$outFile) {
  $files = Get-ChildItem -LiteralPath $dir -File -Recurse | Sort-Object FullName
  $lines = New-Object System.Collections.Generic.List[string]
  foreach ($f in $files) {
    # hash determinista
    $h = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLower()
    # path relativo con separador /
    $rel = $f.FullName.Substring($dir.Length).TrimStart("\","/") -replace "\\","/"
    $lines.Add(("{0}  {1}" -f $h, $rel))
  }
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($outFile, (($lines -join "`n") + "`n"), $utf8NoBom)
}
function Safe-Remove([string]$p) {
  if (Test-Path -LiteralPath $p) {
    Remove-Item -LiteralPath $p -Force -Recurse
  }
}

# Resolver LIVE dir
if (-not $LiveDir -or $LiveDir.Trim().Length -eq 0) {
  if (-not $WorkspaceRoot -or $WorkspaceRoot.Trim().Length -eq 0) { throw "Falta -LiveDir o -WorkspaceRoot" }
  $LiveDir = Join-Path $WorkspaceRoot "runs\smoke_live_latest"
}
$live = (Resolve-Path $LiveDir).Path
if (-not (Test-Path -LiteralPath $live)) { throw "No existe LIVE: $live" }

# Tool requerido
$ensure = Join-Path $repo "tools\ensure_outputs_live_v03.ps1"
if (-not (Test-Path -LiteralPath $ensure)) { throw "Falta tool: $ensure" }

# 1) Asegura outputs (video / music_auto / final)
pwsh -NoProfile -ExecutionPolicy Bypass -File $ensure -LiveDir $live | Out-Null

$video     = Join-Path $live "video.mp4"
$musicAuto = Join-Path $live "video_music_auto.mp4"
$final     = Join-Path $live "video_final.mp4"

if (-not (Test-Path -LiteralPath $video))     { throw "Falta output: $video" }
if (-not (Test-Path -LiteralPath $musicAuto)) { throw "Falta output: $musicAuto" }
if (-not (Test-Path -LiteralPath $final))     { throw "Falta output: $final" }

# 2) Handoff dir
$handoffDir = Join-Path $live $HandoffDirName
if ($Force) { Safe-Remove $handoffDir }
Ensure-Dir $handoffDir

# 3) Copiar outputs al handoff (nombres canon)
Copy-Item -LiteralPath $video     -Destination (Join-Path $handoffDir "video.mp4")             -Force
Copy-Item -LiteralPath $musicAuto -Destination (Join-Path $handoffDir "video_music_auto.mp4")  -Force
Copy-Item -LiteralPath $final     -Destination (Join-Path $handoffDir "video_final.mp4")       -Force

# 4) HASHES + READY
$hashes = Join-Path $handoffDir "HASHES_SHA256.txt"
$ready  = Join-Path $handoffDir "HANDOFF_READY.txt"

Write-Hashes -dir $handoffDir -outFile $hashes

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($ready, "HANDOFF_READY v03`n", $utf8NoBom)

if (-not (Test-Path -LiteralPath $hashes)) { throw "No se generó HASHES: $hashes" }
if (-not (Test-Path -LiteralPath $ready))  { throw "No se generó READY: $ready" }

# 5) ZIP determinista (recrea siempre si Force)
$zipPath = Join-Path $handoffDir $ZipName
if ($Force -and (Test-Path -LiteralPath $zipPath)) { Remove-Item -LiteralPath $zipPath -Force }

if (-not (Test-Path -LiteralPath $zipPath)) {
  # OJO: -LiteralPath NO expande comodines (*). Usamos -Path con lista real de items.
  $items = Get-ChildItem -LiteralPath $handoffDir -Force | Select-Object -ExpandProperty FullName
  if (-not $items -or $items.Count -le 0) { throw "handoffDir vacío, no se puede zippear: $handoffDir" }

  Compress-Archive -Path $items -DestinationPath $zipPath -Force
}

if (-not (Test-Path -LiteralPath $zipPath)) { throw "No se generó ZIP: $zipPath" }

$lenZip = (Get-Item -LiteralPath $zipPath).Length
Write-Host "OK: finalize_handoff_v03 -> $handoffDir" -ForegroundColor Green
Write-Host "OK: handoff_zip -> $zipPath ($lenZip bytes)" -ForegroundColor DarkGray