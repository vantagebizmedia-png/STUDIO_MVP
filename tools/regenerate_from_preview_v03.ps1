param(
  [Parameter(Mandatory=$false)][string]$LiveDir,
  [Parameter(Mandatory=$false)][string]$WorkspaceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$psUtf8Compat = Join-Path $PSScriptRoot "ps_utf8_compat_v03.ps1"
if (-not (Test-Path -LiteralPath $psUtf8Compat -PathType Leaf)) {
  throw ("No existe helper utf8 compat: {0}" -f $psUtf8Compat)
}

. $psUtf8Compat

function Resolve-LiveDir {
  param(
    [string]$LiveDir,
    [string]$WorkspaceRoot
  )

  if ($LiveDir -and $LiveDir.Trim().Length -gt 0) {
    return (Resolve-Path $LiveDir).Path
  }

  if ($WorkspaceRoot -and $WorkspaceRoot.Trim().Length -gt 0) {
    $candidate = Join-Path $WorkspaceRoot "runs\smoke_live_latest"
    return (Resolve-Path $candidate).Path
  }

  throw "Falta -LiveDir o -WorkspaceRoot"
}

function Read-JsonFile {
  param([Parameter(Mandatory=$true)][string]$Path)
  return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Get-BoolAction {
  param(
    [Parameter(Mandatory=$true)]$Actions,
    [Parameter(Mandatory=$true)][string]$Name
  )

  $p = $Actions.PSObject.Properties[$Name]
  if ($null -eq $p -or $null -eq $p.Value) { return $false }
  return [bool]$p.Value
}

function Invoke-Step {
  param(
    [Parameter(Mandatory=$true)][string]$Label,
    [Parameter(Mandatory=$true)][string]$ScriptPath,
    [Parameter(Mandatory=$true)][string]$LiveDir,
    [Parameter(Mandatory=$true)]$Summary
  )

  if (-not (Test-Path -LiteralPath $ScriptPath)) {
    throw "Falta script requerido: $ScriptPath"
  }

  $Summary.Add(("[STEP] {0}" -f $Label)) | Out-Null
  $Summary.Add(("  SCRIPT: {0}" -f $ScriptPath)) | Out-Null
  $Summary.Add(("  LIVEDIR: {0}" -f $LiveDir)) | Out-Null

  & pwsh -NoProfile -ExecutionPolicy Bypass -File $ScriptPath -LiveDir $LiveDir

  if ($LASTEXITCODE -ne 0) {
    throw "Falló step: $Label"
  }

  $Summary.Add("  RESULT: OK") | Out-Null
  $Summary.Add("") | Out-Null
}

$live = Resolve-LiveDir -LiveDir $LiveDir -WorkspaceRoot $WorkspaceRoot
$previewDir = Join-Path $live "preview"
$ovrPath = Join-Path $previewDir "overrides_v03.json"
$summaryPath = Join-Path $previewDir "regenerate_from_preview_summary.txt"

if (-not (Test-Path -LiteralPath $ovrPath)) {
  throw "Falta overrides_v03.json en: $ovrPath"
}

$overrides = Read-JsonFile -Path $ovrPath

$actionsProp = $overrides.PSObject.Properties["actions"]
if ($null -eq $actionsProp -or $null -eq $actionsProp.Value) {
  throw "overrides_v03.json no contiene actions"
}

$actions = $actionsProp.Value

$doSrt    = Get-BoolAction -Actions $actions -Name "regenerate_srt"
$doRender = Get-BoolAction -Actions $actions -Name "regenerate_render"
$doFinal  = Get-BoolAction -Actions $actions -Name "regenerate_final"

$summary = New-Object System.Collections.Generic.List[string]
$summary.Add("STUDIO_MVP REGENERATE FROM PREVIEW v0.3") | Out-Null
$summary.Add(("LIVE: {0}" -f $live)) | Out-Null
$summary.Add(("OVERRIDES: {0}" -f $ovrPath)) | Out-Null
$summary.Add(("ACTION regenerate_srt    = {0}" -f $doSrt)) | Out-Null
$summary.Add(("ACTION regenerate_render = {0}" -f $doRender)) | Out-Null
$summary.Add(("ACTION regenerate_final  = {0}" -f $doFinal)) | Out-Null
$summary.Add("") | Out-Null

if (-not $doSrt -and -not $doRender -and -not $doFinal) {
  $summary.Add("No hay acciones activas.") | Out-Null
  [System.IO.File]::WriteAllLines($summaryPath, $summary, [System.Text.UTF8Encoding]::new($false))
  Write-Host "Sin acciones activas en preview\overrides_v03.json" -ForegroundColor Yellow
  Write-Host "SUMMARY: $summaryPath"
  exit 0
}

$repo = Split-Path -Parent $PSScriptRoot
$tools = Join-Path $repo "tools"

$applySubsScript = Join-Path $tools "apply_subtitles_live_v03.ps1"
$finalizePackScript = Join-Path $tools "finalize_pack_v03.ps1"
$ensureOutputsScript = Join-Path $tools "ensure_outputs_live_v03.ps1"

if ($doRender) {
  Invoke-Step -Label "RENDER BASE" -ScriptPath $finalizePackScript -LiveDir $live -Summary $summary
}

if ($doSrt) {
  Invoke-Step -Label "APPLY SUBTITLES" -ScriptPath $applySubsScript -LiveDir $live -Summary $summary
}

if ($doFinal) {
  Invoke-Step -Label "ENSURE OUTPUTS" -ScriptPath $ensureOutputsScript -LiveDir $live -Summary $summary
}

[System.IO.File]::WriteAllLines($summaryPath, $summary, [System.Text.UTF8Encoding]::new($false))

Write-Host "OK regeneración desde preview completada" -ForegroundColor Green
Write-Host "SUMMARY: $summaryPath"
