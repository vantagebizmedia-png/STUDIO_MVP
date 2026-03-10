param(
  [Parameter(Mandatory=$true)][string]$LiveDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Fail([string]$msg) {
  throw $msg
}

if (-not (Test-Path -LiteralPath $LiveDir)) {
  Fail "No existe LiveDir: $LiveDir"
}

$manifestPath = Join-Path $LiveDir "manifest_v03.json"
if (-not (Test-Path -LiteralPath $manifestPath)) {
  Fail "No existe manifest_v03.json: $manifestPath"
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

$m = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$scenes = @($m.scenes_v03)
if ($scenes.Count -le 0) {
  Fail "manifest_v03.json no tiene scenes_v03"
}

$audioClipsDir = Join-Path $LiveDir "assets\audio_clips"
if (Test-Path -LiteralPath $audioClipsDir) {
  Remove-Item -LiteralPath $audioClipsDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $audioClipsDir | Out-Null

for ($i = 1; $i -le $scenes.Count; $i++) {
  $scene = $scenes[$i - 1]

  $srcCandidates = New-Object System.Collections.Generic.List[string]

  $artifactClip = Join-Path $LiveDir ("artifacts/audio_s{0:d2}.wav" -f $i)
  if (Test-Path -LiteralPath $artifactClip) {
    $null = $srcCandidates.Add($artifactClip)
  }

  try {
    if ($scene.assets -and $scene.assets.audio_clip) {
      $existingRel = [string]$scene.assets.audio_clip
      if (-not [string]::IsNullOrWhiteSpace($existingRel)) {
        $existingAbs = Join-Path $LiveDir $existingRel
        if (Test-Path -LiteralPath $existingAbs) {
          $null = $srcCandidates.Add($existingAbs)
        }
      }
    }
  } catch {}

  $src = $srcCandidates | Select-Object -First 1
  if (-not $src) {
    Fail ("No encontré audio fuente para escena {0:d2}" -f $i)
  }

  $dstName = ("s{0:d2}.wav" -f $i)
  $dstAbs  = Join-Path $audioClipsDir $dstName
  $dstRel  = ("assets/audio_clips/{0}" -f $dstName)

  Copy-Item -LiteralPath $src -Destination $dstAbs -Force

  if (-not $scene.assets) {
    $scene | Add-Member -Force -NotePropertyName assets -NotePropertyValue ([pscustomobject]@{})
  }
  if (-not ($scene.assets.PSObject.Properties.Name -contains "audio_clip")) {
    $scene.assets | Add-Member -Force -NotePropertyName audio_clip -NotePropertyValue $dstRel
  } else {
    $scene.assets.audio_clip = $dstRel
  }

  Write-Host ("OK: escena {0:d2} audio -> {1}" -f $i, $dstRel) -ForegroundColor Green
}

$m.scenes_v03 = @($scenes)
[System.IO.File]::WriteAllText($manifestPath, ($m | ConvertTo-Json -Depth 100), $utf8NoBom)

$packJsonPath = Join-Path $LiveDir "pack.json"
if (Test-Path -LiteralPath $packJsonPath) {
  $p = Get-Content -LiteralPath $packJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json

  if ($p.PSObject.Properties.Name -contains "scenes_v03") {
    $p.scenes_v03 = @($m.scenes_v03)
  }

  if ($p.PSObject.Properties.Name -contains "scenes") {
    $compat = @($p.scenes)
    for ($i = 1; $i -le $compat.Count; $i++) {
      $dstRel = ("assets/audio_clips/s{0:d2}.wav" -f $i)
      if ($compat[$i - 1].PSObject.Properties.Name -contains "audio") {
        $compat[$i - 1].audio = $dstRel
      } else {
        $compat[$i - 1] | Add-Member -Force -NotePropertyName audio -NotePropertyValue $dstRel
      }
    }
    $p.scenes = @($compat)
  }

  [System.IO.File]::WriteAllText($packJsonPath, ($p | ConvertTo-Json -Depth 100), $utf8NoBom)
  Write-Host "OK: pack.json resincronizado" -ForegroundColor Green
}

Write-Host ("OK: refresh_live_audio_clips_v03 scenes={0}" -f $scenes.Count) -ForegroundColor Cyan
