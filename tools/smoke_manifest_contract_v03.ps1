param(
  [Parameter(Mandatory=$true)][string]$LiveDir,
  [int]$MaxScenes = 6
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$psUtf8Compat = Join-Path $PSScriptRoot "ps_utf8_compat_v03.ps1"
if (-not (Test-Path -LiteralPath $psUtf8Compat -PathType Leaf)) {
  throw ("No existe helper utf8 compat: {0}" -f $psUtf8Compat)
}

. $psUtf8Compat

function Fail([string]$msg) { throw "CONTRACT FAIL: $msg" }

$live = (Resolve-Path -LiteralPath $LiveDir).Path
$mf   = Join-Path $live "manifest_v03.json"
if (-not (Test-Path -LiteralPath $mf)) { Fail "Falta manifest_v03.json en: $live" }

$js = Get-Content -LiteralPath $mf -Raw -Encoding UTF8 | ConvertFrom-Json
$sc = @($js.scenes_v03)
if ($sc.Count -lt 1) { Fail "manifest sin scenes_v03" }

$take = [Math]::Min($MaxScenes, $sc.Count)

for ($i=0; $i -lt $take; $i++) {
  $s = $sc[$i]
  foreach ($k in @("id","index","start_ms","end_ms","assets")) {
    if (-not $s.PSObject.Properties[$k]) { Fail "Escena $i sin '$k'" }
  }

  $start = [int]$s.start_ms
  $end   = [int]$s.end_ms
  if ($start -lt 0) { Fail "Escena $i start_ms < 0" }
  if ($end -le $start) { Fail "Escena $i end_ms <= start_ms" }

  $assets = $s.assets
  if ($null -eq $assets) { Fail "Escena $i assets null" }

  $imgOk = $false
  $vidOk = $false

  $ip = $assets.PSObject.Properties["image"]
  if ($null -ne $ip -and $null -ne $ip.Value) {
    $arr = @($ip.Value)
    if ($arr.Count -gt 0 -and $arr[0].PSObject.Properties["path"]) {
      $p = [string]$arr[0].path
      if ($p -and (Test-Path -LiteralPath $p)) { $imgOk = $true }
    }
  }

  $vp = $assets.PSObject.Properties["video"]
  if ($null -ne $vp -and $null -ne $vp.Value) {
    $arr = @($vp.Value)
    if ($arr.Count -gt 0 -and $arr[0].PSObject.Properties["path"]) {
      $p = [string]$arr[0].path
      if ($p -and (Test-Path -LiteralPath $p)) { $vidOk = $true }
    }
  }

  if (-not ($imgOk -or $vidOk)) {
    Fail "Escena $i sin asset visual válido (image|video)"
  }
}

Write-Host ("CONTRACT OK: manifest_v03 scenes_v03={0} checked={1} live={2}" -f $sc.Count, $take, $live) -ForegroundColor Green
exit 0
