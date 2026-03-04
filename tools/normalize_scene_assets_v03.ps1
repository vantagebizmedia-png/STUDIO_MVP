param(
  [Parameter(Mandatory=$true)][string]$ManifestPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null

if (-not (Test-Path -LiteralPath $ManifestPath)) { throw "No existe ManifestPath: $ManifestPath" }

$m = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $m.scenes_v03) { throw "manifest no tiene scenes_v03[]" }

$changed = 0
$scenes  = @($m.scenes_v03)

for ($i=0; $i -lt $scenes.Count; $i++) {
  $s = $scenes[$i]

  $assetsProp = $s.PSObject.Properties["assets"]
  if (-not $assetsProp -or -not $assetsProp.Value) { continue }

  $a = $assetsProp.Value

  # --------- image ----------
  $imgProp = $a.PSObject.Properties["image"]
  if ($imgProp -and $imgProp.Value) {
    $v = $imgProp.Value

    if ($v -is [string]) {
      $a.image = @([pscustomobject]@{ path = $v })
      $changed++
    }
    elseif ($v -is [pscustomobject]) {
      $p = $v.PSObject.Properties["path"]
      if ($p -and $p.Value) {
        $a.image = @([pscustomobject]@{ path = [string]$p.Value })
        $changed++
      }
    }
    elseif ($v -is [object[]]) {
      # si es array pero el primer item no tiene .path y es string, conviértelo
      $arr = @($v)
      if ($arr.Count -ge 1 -and $arr[0] -is [string]) {
        $a.image = @([pscustomobject]@{ path = [string]$arr[0] })
        $changed++
      }
      elseif ($arr.Count -ge 1 -and $arr[0] -is [pscustomobject]) {
        $p0 = $arr[0].PSObject.Properties["path"]
        if (-not $p0 -or -not $p0.Value) {
          # no sabemos de dónde sacar path -> no tocamos
        }
      }
    }
  }

  # --------- video ----------
  $vidProp = $a.PSObject.Properties["video"]
  if ($vidProp -and $vidProp.Value) {
    $v = $vidProp.Value

    if ($v -is [string]) {
      $a.video = @([pscustomobject]@{ path = $v })
      $changed++
    }
    elseif ($v -is [pscustomobject]) {
      $p = $v.PSObject.Properties["path"]
      if ($p -and $p.Value) {
        $a.video = @([pscustomobject]@{ path = [string]$p.Value })
        $changed++
      }
    }
    elseif ($v -is [object[]]) {
      $arr = @($v)
      if ($arr.Count -ge 1 -and $arr[0] -is [string]) {
        $a.video = @([pscustomobject]@{ path = [string]$arr[0] })
        $changed++
      }
    }
  }

  $s.assets   = $a
  $scenes[$i] = $s
}

$m.scenes_v03 = $scenes

$json = $m | ConvertTo-Json -Depth 80
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($ManifestPath, $json, $utf8NoBom)

Write-Host ("OK: normalize_scene_assets_v03 -> changed=" + $changed) -ForegroundColor Green
