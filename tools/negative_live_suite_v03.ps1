param(
  [Parameter(Mandatory=$false)][string]$RepoRoot = "C:\Users\vanta\Documents\STUDIO_MVP",
  [Parameter(Mandatory=$false)][string]$WorkspaceRoot = "C:\Users\vanta\Documents\STUDIO_WORKSPACE",
  [Parameter(Mandatory=$false)][string]$SourceLiveDir = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null

if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) {
  throw "No existe RepoRoot: $RepoRoot"
}

if (-not (Test-Path -LiteralPath $WorkspaceRoot -PathType Container)) {
  throw "No existe WorkspaceRoot: $WorkspaceRoot"
}

if ([string]::IsNullOrWhiteSpace($SourceLiveDir)) {
  $SourceLiveDir = Join-Path $WorkspaceRoot "runs\smoke_live_latest"
}

if (-not (Test-Path -LiteralPath $SourceLiveDir -PathType Container)) {
  throw "No existe SourceLiveDir: $SourceLiveDir"
}

$writePackTool = Join-Path $RepoRoot "tools\write_pack_compat_v03.ps1"
$smokeTool     = Join-Path $RepoRoot "tools\smoke_live_manifest_v03.ps1"
$videoCaseTool = Join-Path $RepoRoot "tools\smoke_live_video_case_v03.ps1"

foreach ($p in @($writePackTool, $smokeTool, $videoCaseTool)) {
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
    throw "No existe tool requerido: $p"
  }
}

function Write-JsonUtf8NoBom {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)]$Object
  )

  $enc = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($Path, ($Object | ConvertTo-Json -Depth 50), $enc)
}

function Read-JsonFile {
  param(
    [Parameter(Mandatory=$true)][string]$Path
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "No existe JSON: $Path"
  }

  return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Reset-LiveClone {
  param(
    [Parameter(Mandatory=$true)][string]$Source,
    [Parameter(Mandatory=$true)][string]$Destination
  )

  if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
    throw "No existe Source para clonar: $Source"
  }

  if (Test-Path -LiteralPath $Destination) {
    Remove-Item -LiteralPath $Destination -Recurse -Force
  }

  Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force

  if (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
    throw "No se pudo clonar LIVE a: $Destination"
  }
}

function Invoke-SmokeExpectFailure {
  param(
    [Parameter(Mandatory=$true)][string]$SmokeToolPath,
    [Parameter(Mandatory=$true)][string]$LiveDir,
    [Parameter(Mandatory=$true)][string]$CaseName,
    [Parameter(Mandatory=$true)][string]$ExpectedSubstring
  )

  function Repair-LikelyMojibake {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
      return ""
    }

    try {
      $bytes = [System.Text.Encoding]::GetEncoding(1252).GetBytes($Text)
      return [System.Text.Encoding]::UTF8.GetString($bytes)
    }
    catch {
      return $Text
    }
  }

  function Remove-Diacritics {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
      return ""
    }

    $normalized = $Text.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder

    foreach ($ch in $normalized.ToCharArray()) {
      $cat = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
      if ($cat -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
        [void]$sb.Append($ch)
      }
    }

    return $sb.ToString().Normalize([System.Text.NormalizationForm]::FormC)
  }

  $stdoutLog = Join-Path $LiveDir ("{0}.stdout.log" -f $CaseName)
  $stderrLog = Join-Path $LiveDir ("{0}.stderr.log" -f $CaseName)

  foreach ($log in @($stdoutLog, $stderrLog)) {
    if (Test-Path -LiteralPath $log) {
      Remove-Item -LiteralPath $log -Force
    }
  }

  $shellPath = "powershell.exe"
  try {
    $pwshCmd = Get-Command pwsh -ErrorAction Stop
    if ($pwshCmd -and -not [string]::IsNullOrWhiteSpace($pwshCmd.Source)) {
      $shellPath = $pwshCmd.Source
    }
  }
  catch { }

  $proc = Start-Process `
    -FilePath $shellPath `
    -ArgumentList @(
      "-NoLogo",
      "-NoProfile",
      "-ExecutionPolicy", "Bypass",
      "-File", $SmokeToolPath,
      "-LiveDir", $LiveDir
    ) `
    -NoNewWindow `
    -Wait `
    -PassThru `
    -RedirectStandardOutput $stdoutLog `
    -RedirectStandardError $stderrLog

  $stdoutText = ""
  $stderrText = ""

  if (Test-Path -LiteralPath $stdoutLog -PathType Leaf) {
    $stdoutText = [System.IO.File]::ReadAllText($stdoutLog)
  }

  if (Test-Path -LiteralPath $stderrLog -PathType Leaf) {
    $stderrText = [System.IO.File]::ReadAllText($stderrLog)
  }

  Write-Host ""
  Write-Host ("== NEG CASE {0} :: stdout ==" -f $CaseName) -ForegroundColor DarkCyan
  if ([string]::IsNullOrWhiteSpace($stdoutText)) {
    Write-Host "(stdout vacío)" -ForegroundColor DarkGray
  }
  else {
    Write-Host $stdoutText
  }

  Write-Host ("== NEG CASE {0} :: stderr ==" -f $CaseName) -ForegroundColor DarkCyan
  if ([string]::IsNullOrWhiteSpace($stderrText)) {
    Write-Host "(stderr vacío)" -ForegroundColor DarkGray
  }
  else {
    Write-Host $stderrText
  }

  if ([int]$proc.ExitCode -eq 0) {
    throw ("{0}: smoke debía fallar y devolvió exit code 0" -f $CaseName)
  }

  $combinedRaw = ($stdoutText + "`r`n" + $stderrText)

  if ([string]::IsNullOrWhiteSpace($combinedRaw)) {
    throw ("{0}: smoke falló pero no produjo salida útil" -f $CaseName)
  }

  $combinedCandidates = @(
    $combinedRaw,
    (Repair-LikelyMojibake -Text $combinedRaw),
    (Remove-Diacritics -Text $combinedRaw),
    (Remove-Diacritics -Text (Repair-LikelyMojibake -Text $combinedRaw))
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

  $expectedCandidates = @(
    $ExpectedSubstring,
    (Remove-Diacritics -Text $ExpectedSubstring)
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

  $matched = $false

  foreach ($candidateText in $combinedCandidates) {
    foreach ($expectedText in $expectedCandidates) {
      if ($candidateText.IndexOf($expectedText, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
        $matched = $true
        break
      }
    }

    if ($matched) { break }
  }

  if (-not $matched) {
    throw ("{0}: salida no contiene texto esperado: {1}" -f $CaseName, $ExpectedSubstring)
  }

  Write-Host ("OK: {0} detectó el fallo esperado" -f $CaseName) -ForegroundColor Green
}$caseA = Join-Path $WorkspaceRoot "runs\smoke_live_neg_video_missing"
$caseB = Join-Path $WorkspaceRoot "runs\smoke_live_neg_image_with_video_leak"
$caseC = Join-Path $WorkspaceRoot "runs\smoke_live_neg_pack_audio_mismatch"
$caseD = Join-Path $WorkspaceRoot "runs\smoke_live_neg_intent_conflict"

Write-Host "== NEGATIVE LIVE SUITE V03 ==" -ForegroundColor Magenta
Write-Host ("RepoRoot      : {0}" -f $RepoRoot) -ForegroundColor DarkGray
Write-Host ("WorkspaceRoot : {0}" -f $WorkspaceRoot) -ForegroundColor DarkGray
Write-Host ("SourceLiveDir : {0}" -f $SourceLiveDir) -ForegroundColor DarkGray

Write-Host ""
Write-Host "== NEG-A: visual_kind=video con video activo faltante ==" -ForegroundColor Cyan
& $videoCaseTool `
  -RepoRoot $RepoRoot `
  -SourceLiveDir $SourceLiveDir `
  -OutputLiveDir $caseA

$caseAVideo = Join-Path $caseA "artifacts\scenes\scene_01\video.mp4"
if (-not (Test-Path -LiteralPath $caseAVideo -PathType Leaf)) {
  throw "NEG-A no generó video base válido: $caseAVideo"
}

Remove-Item -LiteralPath $caseAVideo -Force

Invoke-SmokeExpectFailure `
  -SmokeToolPath $smokeTool `
  -LiveDir $caseA `
  -CaseName "neg_a_video_missing" `
  -ExpectedSubstring "scene_01 no existe video activo:"

Write-Host ""
Write-Host "== NEG-B: visual_kind=image con assets.video filtrado/no vacío ==" -ForegroundColor Cyan
Reset-LiveClone -Source $SourceLiveDir -Destination $caseB

$caseBManifestPath = Join-Path $caseB "manifest_v03.json"
$caseBPackPath     = Join-Path $caseB "pack.json"

$caseBManifest = Read-JsonFile -Path $caseBManifestPath
$caseBPack     = Read-JsonFile -Path $caseBPackPath

if (-not $caseBManifest.scenes_v03 -or @($caseBManifest.scenes_v03).Count -lt 1) {
  throw "NEG-B manifest no contiene scenes_v03 válidas"
}

if (-not $caseBPack.scenes -or @($caseBPack.scenes).Count -lt 1) {
  throw "NEG-B pack no contiene scenes válidas"
}

$caseBScene1Manifest = @($caseBManifest.scenes_v03)[0]
$caseBScene1Pack     = @($caseBPack.scenes)[0]

if (-not $caseBScene1Manifest.assets) {
  throw "NEG-B scene_001 manifest no tiene assets"
}

$caseBLeakVideoRel = "artifacts/scenes/scene_01/video.mp4"
$caseBImageRel = [string]$caseBScene1Manifest.assets.image
$caseBAudioRel = [string]$caseBScene1Manifest.assets.audio_clip

if ([string]::IsNullOrWhiteSpace($caseBImageRel)) {
  throw "NEG-B scene_001 no tiene image base válido"
}

$caseBScene1Manifest.visual_kind = "image"
$caseBScene1Manifest.visual_source_kind = "stock_image"
$caseBScene1Manifest.visual_capability = "stock_image"
$caseBScene1Manifest.assets.image = $caseBImageRel
$caseBScene1Manifest.assets.video = $caseBLeakVideoRel

$caseBScene1Pack.visual_kind = "image"
$caseBScene1Pack.image = $caseBImageRel
$caseBScene1Pack.video = $caseBLeakVideoRel
$caseBScene1Pack.audio = $caseBAudioRel

Write-JsonUtf8NoBom -Path $caseBManifestPath -Object $caseBManifest
Write-JsonUtf8NoBom -Path $caseBPackPath -Object $caseBPack

Invoke-SmokeExpectFailure `
  -SmokeToolPath $smokeTool `
  -LiveDir $caseB `
  -CaseName "neg_b_image_with_video_leak" `
  -ExpectedSubstring "scene_01 visual_kind=image pero assets.video no vacío:"

Write-Host ""
Write-Host "== NEG-C: pack.json desalineado contra manifest_v03.json ==" -ForegroundColor Cyan
Reset-LiveClone -Source $SourceLiveDir -Destination $caseC

$caseCManifestPath = Join-Path $caseC "manifest_v03.json"
$caseCPackPath     = Join-Path $caseC "pack.json"

$caseCManifest = Read-JsonFile -Path $caseCManifestPath
$caseCPack     = Read-JsonFile -Path $caseCPackPath

if (-not $caseCManifest.scenes_v03 -or @($caseCManifest.scenes_v03).Count -lt 1) {
  throw "NEG-C manifest no contiene scenes_v03 válidas"
}

if (-not $caseCPack.scenes -or @($caseCPack.scenes).Count -lt 1) {
  throw "NEG-C pack no contiene scenes válidas"
}

$caseCScene1Manifest = @($caseCManifest.scenes_v03)[0]
$caseCScene1Pack     = @($caseCPack.scenes)[0]

$manifestAudio = [string]$caseCScene1Manifest.assets.audio_clip
if ([string]::IsNullOrWhiteSpace($manifestAudio)) {
  throw "NEG-C scene_001 manifest no tiene audio_clip"
}

$caseCScene1Pack.audio = "assets/audio_clips/s99.wav"
Write-JsonUtf8NoBom -Path $caseCPackPath -Object $caseCPack

Invoke-SmokeExpectFailure `
  -SmokeToolPath $smokeTool `
  -LiveDir $caseC `
  -CaseName "neg_c_pack_audio_mismatch" `
  -ExpectedSubstring "scene_01 pack audio mismatch:"

Write-Host ""
Write-Host "== NEG-D: requested_media_type y visual_request_kind conflictivos ==" -ForegroundColor Cyan
Reset-LiveClone -Source $SourceLiveDir -Destination $caseD

$caseDManifestPath = Join-Path $caseD "manifest_v03.json"
$caseDManifest = Read-JsonFile -Path $caseDManifestPath

if (-not $caseDManifest.scenes_v03 -or @($caseDManifest.scenes_v03).Count -lt 1) {
  throw "NEG-D manifest no contiene scenes_v03 válidas"
}

$caseDScene1Manifest = @($caseDManifest.scenes_v03)[0]

if (-not $caseDScene1Manifest.assets) {
  throw "NEG-D scene_001 manifest no tiene assets"
}

$caseDImageRel = [string]$caseDScene1Manifest.assets.image
if ([string]::IsNullOrWhiteSpace($caseDImageRel)) {
  throw "NEG-D scene_001 no tiene image base válido"
}

$caseDScene1Manifest.requested_media_type = "video"
$caseDScene1Manifest.visual_request_kind = "image"
$caseDScene1Manifest.visual_kind = "image"
$caseDScene1Manifest.visual_source_kind = "stock_image"
$caseDScene1Manifest.visual_capability = "stock_image"
$caseDScene1Manifest.assets.image = $caseDImageRel
$caseDScene1Manifest.assets.video = ""

Write-JsonUtf8NoBom -Path $caseDManifestPath -Object $caseDManifest

Invoke-SmokeExpectFailure `
  -SmokeToolPath $smokeTool `
  -LiveDir $caseD `
  -CaseName "neg_d_intent_conflict" `
  -ExpectedSubstring "scene_01 intent fields conflictivos:"

Write-Host ""
Write-Host "OK: negative_live_suite_v03 completado" -ForegroundColor Green
Write-Host ("NEG_A={0}" -f $caseA) -ForegroundColor DarkGray
Write-Host ("NEG_B={0}" -f $caseB) -ForegroundColor DarkGray
Write-Host ("NEG_C={0}" -f $caseC) -ForegroundColor DarkGray
Write-Host ("NEG_D={0}" -f $caseD) -ForegroundColor DarkGray