param(
  [Parameter(Mandatory=$true)][string]$InDir,
  [Parameter(Mandatory=$true)][string]$OutZip
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Fail([string]$msg) { throw "HANDOFF FAIL: $msg" }

$in = (Resolve-Path -LiteralPath $InDir).Path
if (-not (Test-Path -LiteralPath $in)) { Fail "No existe InDir: $in" }

$req = @("video.mp4","video_final.mp4","video_music_auto.mp4")
foreach ($f in $req) {
  $p = Join-Path $in $f
  if (-not (Test-Path -LiteralPath $p)) { Fail "Falta requerido: $p" }
  $len = (Get-Item -LiteralPath $p).Length
  if ($len -lt 1000) { Fail "Muy pequeño ($len bytes): $p" }
}

# Limpia outputs anteriores si existían
foreach ($f in @("SHA256SUMS.txt","HANDOFF_READY.txt")) {
  $p = Join-Path $in $f
  if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
}
if (Test-Path -LiteralPath $OutZip) { Remove-Item -LiteralPath $OutZip -Force }

# 1) SHA256SUMS
$hashPath = Join-Path $in "SHA256SUMS.txt"
$lines = @()
foreach ($f in $req) {
  $p = Join-Path $in $f
  $h = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()
  $lines += ("{0}  {1}" -f $h, $f)
}
Set-Content -LiteralPath $hashPath -Value ($lines -join "`n") -Encoding UTF8

# 2) HANDOFF_READY marker
$readyPath = Join-Path $in "HANDOFF_READY.txt"
$stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Set-Content -LiteralPath $readyPath -Value ("HANDOFF_READY v03`ncreated_at=$stamp`n") -Encoding UTF8

# 3) ZIP
$zipDir = Split-Path -Parent $OutZip
if (-not (Test-Path -LiteralPath $zipDir)) { New-Item -ItemType Directory -Force -Path $zipDir | Out-Null }

$items = @(
  (Join-Path $in "video.mp4"),
  (Join-Path $in "video_final.mp4"),
  (Join-Path $in "video_music_auto.mp4"),
  $hashPath,
  $readyPath
)
Compress-Archive -LiteralPath $items -DestinationPath $OutZip -Force

Write-Host "OK handoff_pack_v03"
Write-Host "IN : $in"
Write-Host "ZIP: $OutZip"
Get-Item -LiteralPath $OutZip | Select-Object Name,Length,FullName | Format-Table -AutoSize
