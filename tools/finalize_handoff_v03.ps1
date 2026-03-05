param(
  [Parameter(Mandatory=$false)][string]$LiveDir,
  [Parameter(Mandatory=$false)][string]$WorkspaceRoot,
  [string]$HandoffDirName = "handoff_v03",
  [switch]$Force
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
function Safe-Remove([string]$p) {
  if (Test-Path -LiteralPath $p) {
    Remove-Item -LiteralPath $p -Force -Recurse
  }
}

# HASHES: solo archivos NO zip / NO tmp (determinista)
function Write-Hashes([string]$dir, [string]$outFile) {
  $files = Get-ChildItem -LiteralPath $dir -File -Recurse | ForEach-Object {
    $full = $_.FullName
    $rel  = $full.Substring($dir.Length).TrimStart("\","/") -replace "\\","/"
    if ($rel -match '(^|/)\.tmp_') { return }
    if ($rel.ToLowerInvariant().EndsWith(".zip")) { return }
    [pscustomobject]@{ Full=$full; Rel=$rel }
  } | Where-Object { $_ -ne $null } | Sort-Object Rel

  $lines = New-Object System.Collections.Generic.List[string]
  foreach ($f in $files) {
    $h = (Get-FileHash -LiteralPath $f.Full -Algorithm SHA256).Hash.ToLowerInvariant()
    $lines.Add(("{0}  {1}" -f $h, $f.Rel))
  }

  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($outFile, (($lines -join "`n") + "`n"), $utf8NoBom)
}

# Resolver LIVE dir
if (-not $LiveDir -or $LiveDir.Trim().Length -eq 0) {
  if (-not $WorkspaceRoot -or $WorkspaceRoot.Trim().Length -eq 0) { throw "Falta -LiveDir o -WorkspaceRoot" }
  $LiveDir = Join-Path $WorkspaceRoot "runs\smoke_live_latest"
}
$live = (Resolve-Path $LiveDir).Path
if (-not (Test-Path -LiteralPath $live)) { throw "No existe LIVE: $live" }

# ensure outputs
$ensure = Join-Path $repo "tools\ensure_outputs_live_v03.ps1"
if (-not (Test-Path -LiteralPath $ensure)) { throw "Falta tool: $ensure" }
pwsh -NoProfile -ExecutionPolicy Bypass -File $ensure -LiveDir $live | Out-Null

$video     = Join-Path $live "video.mp4"
$musicAuto = Join-Path $live "video_music_auto.mp4"
$final     = Join-Path $live "video_final.mp4"

if (-not (Test-Path -LiteralPath $video))     { throw "Falta output: $video" }
if (-not (Test-Path -LiteralPath $musicAuto)) { throw "Falta output: $musicAuto" }
if (-not (Test-Path -LiteralPath $final))     { throw "Falta output: $final" }

# handoff dir
$handoffDir = Join-Path $live $HandoffDirName
if ($Force) { Safe-Remove $handoffDir }
Ensure-Dir $handoffDir

# copiar outputs canon
Copy-Item -LiteralPath $video     -Destination (Join-Path $handoffDir "video.mp4")            -Force
Copy-Item -LiteralPath $musicAuto -Destination (Join-Path $handoffDir "video_music_auto.mp4") -Force
Copy-Item -LiteralPath $final     -Destination (Join-Path $handoffDir "video_final.mp4")      -Force

# hashes + ready (sin zip)
$hashes = Join-Path $handoffDir "HASHES_SHA256.txt"
$ready  = Join-Path $handoffDir "HANDOFF_READY.txt"

Write-Hashes -dir $handoffDir -outFile $hashes

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$readyText = @()
$readyText += "HANDOFF_READY v0.3"
$readyText += "FILES:"
$readyText += "- video_final.mp4"
$readyText += "- video_music_auto.mp4"
$readyText += "- video.mp4"
$readyText += "HASHES_SHA256:"
$readyText += (Get-Content -LiteralPath $hashes -Encoding UTF8)
[System.IO.File]::WriteAllText($ready, (($readyText -join "`n") + "`n"), $utf8NoBom)

Write-Host "OK: finalize_handoff_v03 -> $handoffDir (READY/HASHES sin ZIP)" -ForegroundColor Green