param(
  [Parameter(Mandatory=$false)][string]$RepoRoot = "C:\Users\vanta\Documents\STUDIO_MVP",
  [Parameter(Mandatory=$false)][string]$WorkspaceRoot = "C:\Users\vanta\Documents\STUDIO_WORKSPACE",
  [Parameter(Mandatory=$false)][string]$OutputRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$psUtf8Compat = Join-Path $PSScriptRoot "ps_utf8_compat_v03.ps1"
if (-not (Test-Path -LiteralPath $psUtf8Compat -PathType Leaf)) {
  throw ("No existe helper utf8 compat: {0}" -f $psUtf8Compat)
}

. $psUtf8Compat

function Fail {
  param([Parameter(Mandatory=$true)][string]$Message)
  throw "SMOKE FAIL: $Message"
}

$resolvePython = Join-Path $PSScriptRoot "resolve_python.ps1"
if (-not (Test-Path -LiteralPath $resolvePython -PathType Leaf)) {
  Fail "No existe helper resolve_python: $resolvePython"
}

. $resolvePython
$pythonExe = Resolve-PythonExe -RepoRoot $RepoRoot

function Write-Utf8Lf {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][string]$Content
  )

  $dir = Split-Path -Parent $Path
  if (-not [string]::IsNullOrWhiteSpace($dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }

  $normalized = $Content -replace "`r`n", "`n"
  $normalized = $normalized -replace "`r", "`n"
  if (-not $normalized.EndsWith("`n")) {
    $normalized += "`n"
  }

  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($Path, $normalized, $utf8NoBom)
}

function Invoke-PythonLogged {
  param(
    [Parameter(Mandatory=$true)][string]$WorkingDirectory,
    [Parameter(Mandatory=$true)][string[]]$Arguments,
    [Parameter(Mandatory=$true)][string]$Label,
    [Parameter(Mandatory=$true)][string]$LogRoot
  )

  $stdoutPath = Join-Path $LogRoot ($Label + ".stdout.log")
  $stderrPath = Join-Path $LogRoot ($Label + ".stderr.log")

  if (Test-Path -LiteralPath $stdoutPath) {
    Remove-Item -LiteralPath $stdoutPath -Force
  }
  if (Test-Path -LiteralPath $stderrPath) {
    Remove-Item -LiteralPath $stderrPath -Force
  }

  $proc = Start-Process `
    -FilePath $pythonExe `
    -ArgumentList $Arguments `
    -WorkingDirectory $WorkingDirectory `
    -NoNewWindow `
    -Wait `
    -PassThru `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath

  $stdout = @()
  $stderr = @()

  if (Test-Path -LiteralPath $stdoutPath -PathType Leaf) {
    $stdout = @(Get-Content -LiteralPath $stdoutPath -Encoding UTF8)
  }
  if (Test-Path -LiteralPath $stderrPath -PathType Leaf) {
    $stderr = @(Get-Content -LiteralPath $stderrPath -Encoding UTF8)
  }

  foreach ($line in $stdout) {
    Write-Host $line
  }
  foreach ($line in $stderr) {
    Write-Host $line
  }

  return [pscustomobject]@{
    ExitCode = [int]$proc.ExitCode
    Stdout   = @($stdout)
    Stderr   = @($stderr)
    Combined = @($stdout + $stderr)
  }
}

if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) {
  Fail "No existe RepoRoot: $RepoRoot"
}

if (-not (Test-Path -LiteralPath $WorkspaceRoot -PathType Container)) {
  Fail "No existe WorkspaceRoot: $WorkspaceRoot"
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $OutputRoot = Join-Path $WorkspaceRoot "runs\smoke_release_handoff_contract"
}

$sourceConfigPath = Join-Path $RepoRoot "config\studio_v03_multiscene_text_smoke.json"
if (-not (Test-Path -LiteralPath $sourceConfigPath -PathType Leaf)) {
  Fail "No existe config base: $sourceConfigPath"
}

$runRoot = Join-Path $OutputRoot "release_contract_run"
$workDir = Join-Path $runRoot "artifacts"
$workspaceDir = Join-Path $runRoot "workspace"
$negativeRoot = Join-Path $OutputRoot "negative"
$configCopyPath = Join-Path $OutputRoot "studio_v03_multiscene_text_smoke.release_handoff_contract.json"

if (Test-Path -LiteralPath $OutputRoot) {
  Remove-Item -LiteralPath $OutputRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
New-Item -ItemType Directory -Path $negativeRoot -Force | Out-Null

$configObj = Get-Content -LiteralPath $sourceConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$configObj.work_dir = ($workDir -replace "\\", "/")
$configObj.workspace = ($workspaceDir -replace "\\", "/")

$configJson = $configObj | ConvertTo-Json -Depth 100
Write-Utf8Lf -Path $configCopyPath -Content $configJson

Push-Location $RepoRoot
try {
  Write-Host "== SMOKE RELEASE HANDOFF CONTRACT V03 ==" -ForegroundColor Magenta
  Write-Host ("RepoRoot     : {0}" -f $RepoRoot) -ForegroundColor DarkGray
  Write-Host ("WorkspaceRoot: {0}" -f $WorkspaceRoot) -ForegroundColor DarkGray
  Write-Host ("OutputRoot   : {0}" -f $OutputRoot) -ForegroundColor DarkGray
  Write-Host ("ConfigBase   : {0}" -f $sourceConfigPath) -ForegroundColor DarkGray
  Write-Host ("ConfigCopy   : {0}" -f $configCopyPath) -ForegroundColor DarkGray

  Write-Host ""
  Write-Host "== PY COMPILE ==" -ForegroundColor Cyan
  $pyTargets = @(
    (Join-Path $RepoRoot "tools\release_pack_v03.py"),
    (Join-Path $RepoRoot "tools\finalize_handoff_v03.py"),
    (Join-Path $RepoRoot "tools\validate_pack.py"),
    (Join-Path $RepoRoot "tools\validate_handoff.py")
  )

  foreach ($t in $pyTargets) {
    & $pythonExe -m py_compile $t
    if ($LASTEXITCODE -ne 0) {
      Fail "py_compile falló: $t"
    }
    Write-Host ("OK: {0}" -f $t) -ForegroundColor Green
  }

  $releasePackPy = Join-Path $RepoRoot "tools\release_pack_v03.py"
  $finalizeHandoffPy = Join-Path $RepoRoot "tools\finalize_handoff_v03.py"
  $validatePackPy = Join-Path $RepoRoot "tools\validate_pack.py"
  $validateHandoffPy = Join-Path $RepoRoot "tools\validate_handoff.py"

  Write-Host ""
  Write-Host "== RELEASE PACK ==" -ForegroundColor Cyan
  $releaseRun = Invoke-PythonLogged `
    -WorkingDirectory $RepoRoot `
    -Arguments @(
      "-u",
      $releasePackPy,
      "--v03-config",
      $configCopyPath,
      "--script",
      "smoke_release_handoff_contract",
      "--overwrite"
    ) `
    -Label "release_pack" `
    -LogRoot $OutputRoot

  $packDirLine = $releaseRun.Combined |
    Where-Object { $_ -match '^PACK_DIR:\s*(.+)$' } |
    Select-Object -Last 1

  $packDir = ""
  if ($packDirLine) {
    $packDir = ([regex]::Match($packDirLine, '^PACK_DIR:\s*(.+)$')).Groups[1].Value.Trim()
  }

  if ($releaseRun.ExitCode -ne 0) {
    if (-not [string]::IsNullOrWhiteSpace($packDir) -and (Test-Path -LiteralPath $packDir -PathType Container)) {
      Write-Host ""
      Write-Host "== RELEASE DIAGNOSTIC: VALIDATE PACK ==" -ForegroundColor Yellow
      $diagRun = Invoke-PythonLogged `
        -WorkingDirectory $RepoRoot `
        -Arguments @(
          "-u",
          $validatePackPy,
          "--pack-dir",
          $packDir
        ) `
        -Label "release_validate_diag" `
        -LogRoot $OutputRoot
      $null = $diagRun
    }

    Fail "release_pack_v03.py devolvió exit code $($releaseRun.ExitCode)"
  }

  if ([string]::IsNullOrWhiteSpace($packDir)) {
    Fail "No pude extraer PACK_DIR desde release_pack_v03.py"
  }
  if (-not (Test-Path -LiteralPath $packDir -PathType Container)) {
    Fail "PACK_DIR no existe: $packDir"
  }

  $packLeaf = Split-Path -Leaf $packDir
  $packParent = Split-Path -Parent $packDir
  $zipPath = Join-Path $packParent ("{0}.final_delivery.zip" -f $packLeaf)
  $shaPath = Join-Path $packParent ("{0}.final_delivery.zip.sha256.txt" -f $packLeaf)

  Write-Host ""
  Write-Host "== FINALIZE HANDOFF ==" -ForegroundColor Cyan
  $finalizeRun = Invoke-PythonLogged `
    -WorkingDirectory $RepoRoot `
    -Arguments @(
      "-u",
      $finalizeHandoffPy,
      "--pack-dir",
      $packDir
    ) `
    -Label "finalize_handoff" `
    -LogRoot $OutputRoot

  if ($finalizeRun.ExitCode -ne 0) {
    Fail "finalize_handoff_v03.py devolvió exit code $($finalizeRun.ExitCode)"
  }

  Write-Host ""
  Write-Host "== VALIDATE PACK FINAL ==" -ForegroundColor Cyan
  $validatePackRun = Invoke-PythonLogged `
    -WorkingDirectory $RepoRoot `
    -Arguments @(
      "-u",
      $validatePackPy,
      "--pack-dir",
      $packDir
    ) `
    -Label "validate_pack_final" `
    -LogRoot $OutputRoot

  if ($validatePackRun.ExitCode -ne 0) {
    Fail "validate_pack.py devolvió exit code $($validatePackRun.ExitCode) tras finalize_handoff"
  }

  Write-Host ""
  Write-Host "== VALIDATE HANDOFF ==" -ForegroundColor Cyan
  $validateRun = Invoke-PythonLogged `
    -WorkingDirectory $RepoRoot `
    -Arguments @(
      "-u",
      $validateHandoffPy,
      "--pack-dir",
      $packDir
    ) `
    -Label "validate_handoff" `
    -LogRoot $OutputRoot

  if ($validateRun.ExitCode -ne 0) {
    Fail "validate_handoff.py devolvió exit code $($validateRun.ExitCode)"
  }

  foreach ($mustExist in @(
    (Join-Path $packDir "pack.json"),
    (Join-Path $packDir "manifest_v03.json"),
    (Join-Path $packDir "video.mp4"),
    (Join-Path $packDir "video_music_auto.mp4"),
    (Join-Path $packDir "video_final.mp4"),
    (Join-Path $packDir "HANDOFF_READY.txt"),
    $zipPath,
    $shaPath
  )) {
    if (-not (Test-Path -LiteralPath $mustExist -PathType Leaf)) {
      Fail "Artefacto faltante tras handoff: $mustExist"
    }
  }

  $finalPackObj = Get-Content -LiteralPath (Join-Path $packDir "pack.json") -Raw -Encoding UTF8 | ConvertFrom-Json
  $finalManifestObj = Get-Content -LiteralPath (Join-Path $packDir "manifest_v03.json") -Raw -Encoding UTF8 | ConvertFrom-Json
  $finalPackScenes = @($finalPackObj.scenes)
  $finalManifestScenes = @($finalManifestObj.scenes_v03)

  if ($finalPackScenes.Count -ne $finalManifestScenes.Count) {
    Fail "handoff final no preservó mismo número de escenas entre pack.json y manifest_v03.json"
  }

  Write-Host ""
  Write-Host "== INSPECCION VISUAL FINAL ==" -ForegroundColor Cyan
  $finalPackScenes |
    Select-Object -First 6 id,index,visual_kind,visual_source_kind,visual_capability,image,video,audio,start_ms,end_ms,duration_ms |
    Format-Table -AutoSize

  for ($i = 0; $i -lt $finalPackScenes.Count; $i++) {
    $p = $finalPackScenes[$i]
    $m = $finalManifestScenes[$i]

    $sceneLabel = [string]$p.id
    if ([string]::IsNullOrWhiteSpace($sceneLabel)) {
      $sceneLabel = [string]$m.id
    }
    if ([string]::IsNullOrWhiteSpace($sceneLabel)) {
      $sceneLabel = "scene_$($i + 1)"
    }

    $pkVisualKind = ([string]$p.visual_kind).Trim().ToLowerInvariant()
    $pkVisualSourceKind = ([string]$p.visual_source_kind).Trim().ToLowerInvariant()
    $pkVisualCapability = ([string]$p.visual_capability).Trim().ToLowerInvariant()

    $mfVisualKind = ([string]$m.visual_kind).Trim().ToLowerInvariant()
    $mfVisualSourceKind = ([string]$m.visual_source_kind).Trim().ToLowerInvariant()
    $mfVisualCapability = ([string]$m.visual_capability).Trim().ToLowerInvariant()

    $expectedPackSource = if ($pkVisualKind -eq "video") { "stock_video" } else { "stock_image" }
    $expectedPackCapability = if ($pkVisualKind -eq "video") { "stock_video" } else { "stock_image" }
    $expectedManifestSource = if ($mfVisualKind -eq "video") { "stock_video" } else { "stock_image" }
    $expectedManifestCapability = if ($mfVisualKind -eq "video") { "stock_video" } else { "stock_image" }

    if ([string]::IsNullOrWhiteSpace($pkVisualSourceKind)) {
      Fail "$sceneLabel visual_source_kind vacío en pack final"
    }
    if ([string]::IsNullOrWhiteSpace($pkVisualCapability)) {
      Fail "$sceneLabel visual_capability vacío en pack final"
    }
    if ([string]::IsNullOrWhiteSpace($mfVisualSourceKind)) {
      Fail "$sceneLabel visual_source_kind vacío en manifest final"
    }
    if ([string]::IsNullOrWhiteSpace($mfVisualCapability)) {
      Fail "$sceneLabel visual_capability vacío en manifest final"
    }

    if ($pkVisualSourceKind -ne $expectedPackSource) {
      Fail "$sceneLabel visual_source_kind incompatible con visual_kind en pack final: kind='$pkVisualKind' source='$pkVisualSourceKind'"
    }
    if ($pkVisualCapability -ne $expectedPackCapability) {
      Fail "$sceneLabel visual_capability incompatible con visual_kind en pack final: kind='$pkVisualKind' capability='$pkVisualCapability'"
    }
    if ($mfVisualSourceKind -ne $expectedManifestSource) {
      Fail "$sceneLabel visual_source_kind incompatible con visual_kind en manifest final: kind='$mfVisualKind' source='$mfVisualSourceKind'"
    }
    if ($mfVisualCapability -ne $expectedManifestCapability) {
      Fail "$sceneLabel visual_capability incompatible con visual_kind en manifest final: kind='$mfVisualKind' capability='$mfVisualCapability'"
    }

    if ($pkVisualSourceKind -ne $mfVisualSourceKind) {
      Fail "$sceneLabel visual_source_kind pack/manifest final mismatch: pack='$pkVisualSourceKind' manifest='$mfVisualSourceKind'"
    }
    if ($pkVisualCapability -ne $mfVisualCapability) {
      Fail "$sceneLabel visual_capability pack/manifest final mismatch: pack='$pkVisualCapability' manifest='$mfVisualCapability'"
    }
  }

  Write-Host ""
  Write-Host "== NEGATIVE: FALTA video_final.mp4 ==" -ForegroundColor Cyan
  $brokenParent = Join-Path $negativeRoot "broken_parent"
  New-Item -ItemType Directory -Path $brokenParent -Force | Out-Null

  $brokenPack = Join-Path $brokenParent $packLeaf
  Copy-Item -LiteralPath $packDir -Destination $brokenPack -Recurse -Force
  Copy-Item -LiteralPath $zipPath -Destination (Join-Path $brokenParent (Split-Path -Leaf $zipPath)) -Force
  Copy-Item -LiteralPath $shaPath -Destination (Join-Path $brokenParent (Split-Path -Leaf $shaPath)) -Force

  $brokenVideoFinal = Join-Path $brokenPack "video_final.mp4"
  if (-not (Test-Path -LiteralPath $brokenVideoFinal -PathType Leaf)) {
    Fail "No existe video_final.mp4 en la copia negativa"
  }
  Remove-Item -LiteralPath $brokenVideoFinal -Force

  $negativeRun = Invoke-PythonLogged `
    -WorkingDirectory $RepoRoot `
    -Arguments @(
      "-u",
      $validateHandoffPy,
      "--pack-dir",
      $brokenPack
    ) `
    -Label "negative_validate_handoff" `
    -LogRoot $OutputRoot

  if ($negativeRun.ExitCode -eq 0) {
    Fail "validate_handoff.py NO detectó la copia negativa rota"
  }

  $negativeJoined = ($negativeRun.Combined | ForEach-Object { $_.ToString() }) -join "`n"
  if (
    ($negativeJoined -notmatch "falta archivo requerido: video_final\.mp4") -and
    ($negativeJoined -notmatch "HANDOFF_READY") -and
    ($negativeJoined -notmatch "RESULT:\s*FAIL")
  ) {
    Fail "El negativo falló, pero no mostró la señal contractual esperada"
  }

  $global:LASTEXITCODE = 0

  Write-Host ""
  Write-Host "OK: smoke_release_handoff_contract_v03 completado" -ForegroundColor Green
  Write-Host ("PACK_DIR={0}" -f $packDir) -ForegroundColor DarkGray
  Write-Host ("ZIP_PATH={0}" -f $zipPath) -ForegroundColor DarkGray
  Write-Host ("BROKEN_PACK={0}" -f $brokenPack) -ForegroundColor DarkGray
}
finally {
  Pop-Location
}
