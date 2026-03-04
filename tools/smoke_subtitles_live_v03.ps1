param(
  [Parameter(Mandatory=$true)][string]$LiveDir,
  [int]$MaxScenes = 6
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null

function Fail([string]$msg) { throw "SMOKE FAIL: $msg" }

$live = (Resolve-Path -LiteralPath $LiveDir).Path
$mf   = Join-Path $live "manifest_v03.json"
if (-not (Test-Path -LiteralPath $mf)) { Fail "Falta manifest_v03.json en LIVE: $live" }

# Video base + subtitles
$videoBase = Join-Path $live "video.mp4"
$videoSubs = Join-Path $live "video_subtitles.mp4"
$srt       = Join-Path $live "captions_v03.srt"

if (-not (Test-Path -LiteralPath $videoBase)) { Fail "Falta video base: $videoBase" }
if (-not (Test-Path -LiteralPath $videoSubs)) { Fail "Falta video_subtitles: $videoSubs" }
if (-not (Test-Path -LiteralPath $srt))       { Fail "Falta SRT: $srt" }

$vb = (Get-Item -LiteralPath $videoBase).Length
$vs = (Get-Item -LiteralPath $videoSubs).Length
$sb = (Get-Item -LiteralPath $srt).Length
if ($vb -lt 1000) { Fail "video.mp4 muy pequeño: $vb bytes" }
if ($vs -lt 1000) { Fail "video_subtitles.mp4 muy pequeño: $vs bytes" }
if ($sb -lt 10)   { Fail "captions_v03.srt muy pequeño: $sb bytes" }

$js = Get-Content -LiteralPath $mf -Raw -Encoding UTF8 | ConvertFrom-Json
$sc = @($js.scenes_v03)
if ($sc.Count -lt 1) { Fail "manifest sin scenes_v03" }

$take = [Math]::Min($MaxScenes, $sc.Count)

for ($i=0; $i -lt $take; $i++) {
  $s = $sc[$i]
  if ($null -eq $s.assets) { Fail "Escena $i sin assets (LIVE)" }

  $assets = $s.assets

  # Acepta image o video
  $imgOk = $false
  $vidOk = $false

  # image
  $ip = $assets.PSObject.Properties["image"]
  if ($null -ne $ip -and $null -ne $ip.Value) {
    $arr = @($ip.Value)
    if ($arr.Count -gt 0) {
      $p = $arr[0].PSObject.Properties["path"]
      if ($null -ne $p -and [string]$arr[0].path) {
        $imgPath = [string]$arr[0].path
        if (Test-Path -LiteralPath $imgPath) { $imgOk = $true }
      }
    }
  }

  # video
  $vp = $assets.PSObject.Properties["video"]
  if ($null -ne $vp -and $null -ne $vp.Value) {
    $arr = @($vp.Value)
    if ($arr.Count -gt 0) {
      $p = $arr[0].PSObject.Properties["path"]
      if ($null -ne $p -and [string]$arr[0].path) {
        $vidPath = [string]$arr[0].path
        if (Test-Path -LiteralPath $vidPath) { $vidOk = $true }
      }
    }
  }

  if (-not ($imgOk -or $vidOk)) {
    Fail "Escena $i sin asset visual válido (esperaba assets.image[0].path o assets.video[0].path existente)"
  }
}

# total_ms determinista (desde escenas)
$totalMs = "n/a"
try {
  $ends = @()
  foreach ($s in $sc) {
    if ($s.PSObject.Properties["end_ms"] -and ($s.end_ms -as [int]) -ge 0) {
      $ends += [int]$s.end_ms
    }
  }
  if ($ends.Count -gt 0) {
    $totalMs = [string](($ends | Measure-Object -Maximum).Maximum)
  }
} catch { }

Write-Host ("SMOKE OK: LIVE subtitles v03 + assets (image|video). live={0} scenes={1} total_ms={2} video_bytes={3} subs_bytes={4} srt_bytes={5}" -f $live, $take, $totalMs, $vb, $vs, $sb) -ForegroundColor Green
exit 0
