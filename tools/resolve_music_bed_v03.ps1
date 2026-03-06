param(
  [Parameter(Mandatory=$false)][string]$LiveDir,
  [int]$Seed = 123
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null

$repo = (Resolve-Path ".").Path
$workspace = $env:STUDIO_WORKSPACE

$exts = @("*.mp3","*.wav","*.m4a","*.aac","*.flac","*.ogg")

function Collect([string]$dir,[string]$src) {
  if (-not $dir) { return @() }
  if (-not (Test-Path -LiteralPath $dir)) { return @() }

  $rows = foreach ($ext in $exts) {
    Get-ChildItem -LiteralPath $dir -File -Filter $ext -ErrorAction SilentlyContinue | ForEach-Object {
      [pscustomobject]@{
        FullName = $_.FullName
        Source   = $src
      }
    }
  }

  return @($rows)
}

$candidates = @()

# prioridad absoluta
$candidates += @(Collect (Join-Path $repo "music") "repo_music")

# fallback controlado
if ($workspace) {
  $candidates += @(Collect $workspace "workspace")
}

$candidates = @(
  $candidates | Where-Object {
    $p = $_.FullName.ToLowerInvariant()

    if ($p -match "\\runs\\") { return $false }
    if ($p -match "audio_.*\.wav$") { return $false }
    if ($p -match "\\cache\\voice\\") { return $false }
    if ($p -match "video_music_auto\.mp4$") { return $false }
    if ($p -match "video_final\.mp4$") { return $false }
    if ($p -match "video_subtitles\.mp4$") { return $false }
    if ($p -match "video_subs\.mp4$") { return $false }
    if ($p -match "video\.mp4$") { return $false }

    return $true
  }
)

$candidates = @($candidates | Sort-Object FullName)

if (@($candidates).Count -eq 0) {
  [pscustomobject]@{
    found  = $false
    path   = ""
    source = ""
    note   = "no_music_bed_found"
  } | ConvertTo-Json -Depth 10
  exit 0
}

$idx = [Math]::Abs($Seed) % @($candidates).Count
$pick = @($candidates)[$idx]

[pscustomobject]@{
  found  = $true
  path   = $pick.FullName
  source = $pick.Source
  note   = "deterministic_selection"
} | ConvertTo-Json -Depth 10