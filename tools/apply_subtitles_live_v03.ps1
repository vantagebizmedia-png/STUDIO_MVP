param(
  [Parameter(Mandatory=$false)][string]$LiveDir,
  [Parameter(Mandatory=$false)][string]$WorkspaceRoot,

  [string]$SrtName = "captions_v03.srt",
  [string]$OutVideoName = "video_subtitles.mp4",
  [string]$OutVideoLegacyName = "video_subs.mp4",

  [switch]$PopulateFromScriptFiles,
  [switch]$AllowPlaceholderText,
  [switch]$UseAutofit,

  # fallback burn-in
  [int]$FontSize = 18,
  [int]$Outline = 2,
  [int]$Shadow = 1,
  [int]$MarginV = 80,
  [int]$Alignment = 2,

  # autofit bounds (si aplica)
  [int]$MinFontSize = 14,
  [int]$MaxFontSize = 28
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null

$repo = (Resolve-Path ".").Path

# Defaults deterministas para smoke
if (-not $PSBoundParameters.ContainsKey("PopulateFromScriptFiles")) { $PopulateFromScriptFiles = $true }
if (-not $PSBoundParameters.ContainsKey("AllowPlaceholderText"))    { $AllowPlaceholderText    = $true }
if (-not $PSBoundParameters.ContainsKey("UseAutofit"))              { $UseAutofit              = $true }

# Resolver LIVE dir
if (-not $LiveDir -or $LiveDir.Trim().Length -eq 0) {
  if (-not $WorkspaceRoot -or $WorkspaceRoot.Trim().Length -eq 0) { throw "Falta -LiveDir o -WorkspaceRoot" }
  $LiveDir = Join-Path $WorkspaceRoot "runs\smoke_live_latest"
}
$live = (Resolve-Path $LiveDir).Path
if (-not (Test-Path -LiteralPath $live)) { throw "No existe LIVE: $live" }

$man = Join-Path $live "manifest_v03.json"
if (-not (Test-Path -LiteralPath $man)) { throw "Falta manifest: $man" }

$videoIn = Join-Path $live "video.mp4"
if (-not (Test-Path -LiteralPath $videoIn)) { throw "Falta video.mp4 en LIVE: $videoIn" }

$makeSrt  = Join-Path $repo "tools\make_srt_from_scenes_v03.ps1"
$burnIn   = Join-Path $repo "tools\burn_in_srt_v03.ps1"
$autofit  = Join-Path $repo "tools\autofit_burnin_srt_v03.ps1"
$popScene = Join-Path $repo "tools\populate_scene_text_from_scriptfiles_v03.ps1"

if (-not (Test-Path -LiteralPath $makeSrt)) { throw "Falta tool: $makeSrt" }
if (-not (Test-Path -LiteralPath $burnIn))  { throw "Falta tool: $burnIn" }

$srtOut      = Join-Path $live $SrtName
$videoOut    = Join-Path $live $OutVideoName
$videoLegacy = Join-Path $live $OutVideoLegacyName

function Get-AutofitParamNames([string]$scriptPath) {
  if (-not (Test-Path -LiteralPath $scriptPath)) { return @() }

  $tokens = $null
  $errors = $null
  $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)

  if ($null -ne $errors -and $errors.Count -gt 0) { return @() }
  if ($null -eq $ast -or $null -eq $ast.ParamBlock) { return @() }

  $names = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($p in $ast.ParamBlock.Parameters) {
    if ($null -ne $p -and $null -ne $p.Name) {
      $n = $p.Name.VariablePath.UserPath
      if ($n) { $null = $names.Add($n) }
    }
  }
  return @($names)
}

# 0) Poblar texto por escena (determinista)
if ($PopulateFromScriptFiles) {
  if (Test-Path -LiteralPath $popScene) {
    try {
      pwsh -NoProfile -ExecutionPolicy Bypass -File $popScene -LiveDir $live | Out-Null
      Write-Host "OK: populate_scene_text_from_scriptfiles_v03 aplicado" -ForegroundColor DarkGray
    } catch {
      Write-Host ("WARN: populate_scene_text_from_scriptfiles_v03 falló (se continúa): {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
    }
  } else {
    Write-Host "WARN: tool no existe, se omite populate_scene_text_from_scriptfiles_v03.ps1" -ForegroundColor DarkYellow
  }
}

# 1) Genera SRT desde scenes_v03
if ($AllowPlaceholderText) {
  pwsh -NoProfile -ExecutionPolicy Bypass -File $makeSrt `
    -ManifestPath $man `
    -OutSrtPath $srtOut `
    -AllowPlaceholderText | Out-Null
} else {
  pwsh -NoProfile -ExecutionPolicy Bypass -File $makeSrt `
    -ManifestPath $man `
    -OutSrtPath $srtOut | Out-Null
}
if (-not (Test-Path -LiteralPath $srtOut)) { throw "No se generó SRT: $srtOut" }
$lenSrt = (Get-Item -LiteralPath $srtOut).Length
if ($lenSrt -lt 10) { throw "SRT demasiado pequeño (posible fallo): $srtOut (bytes=$lenSrt)" }

# Borra outputs previos para que el chequeo sea real (evita falso positivo)
Remove-Item -LiteralPath $videoOut -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $videoLegacy -Force -ErrorAction SilentlyContinue

# 2) Burn-in: intenta AUTOFIT (si existe) con auto-detección de params; si falla, fallback a burn_in clásico.
$didAutofit = $false
if ($UseAutofit -and (Test-Path -LiteralPath $autofit)) {
  $pnames = Get-AutofitParamNames $autofit

  # posibles alias para SRT en scripts distintos
  $srtParamCandidates = @("SrtPath","InSrt","Srt","CaptionsPath","Captions","SubtitlesPath","SubPath")
  $inVideoCandidates  = @("InVideo","InputVideo","VideoIn","InMp4","Input")
  $outVideoCandidates = @("OutVideo","OutputVideo","VideoOut","OutMp4","Output")

  function Pick-FirstPresent([string[]]$cands, [string[]]$present) {
    foreach ($c in $cands) { if ($present -contains $c) { return $c } }
    return $null
  }

  $pSrt = Pick-FirstPresent $srtParamCandidates $pnames
  $pIn  = Pick-FirstPresent $inVideoCandidates  $pnames
  $pOut = Pick-FirstPresent $outVideoCandidates $pnames

  if (-not $pSrt -or -not $pIn -or -not $pOut) {
    $det = if ($pnames.Count -gt 0) { ($pnames -join ", ") } else { "<none>" }
    Write-Host ("WARN: autofit existe pero no pude inferir params (SRT/In/Out). Detectados: {0}" -f $det) -ForegroundColor DarkYellow
  } else {
    $args = @("-NoProfile","-ExecutionPolicy","Bypass","-File",$autofit)

    # agrega pares param-valor detectados
    $args += @("-$pIn",  $videoIn)
    $args += @("-$pSrt", $srtOut)
    $args += @("-$pOut", $videoOut)

    # opcionales si el script los tiene
    if ($pnames -contains "MinFontSize") { $args += @("-MinFontSize", "$MinFontSize") }
    if ($pnames -contains "MaxFontSize") { $args += @("-MaxFontSize", "$MaxFontSize") }
    if ($pnames -contains "Outline")     { $args += @("-Outline", "$Outline") }
    if ($pnames -contains "Shadow")      { $args += @("-Shadow", "$Shadow") }
    if ($pnames -contains "MarginV")     { $args += @("-MarginV", "$MarginV") }
    if ($pnames -contains "Alignment")   { $args += @("-Alignment", "$Alignment") }

    & pwsh @args | Out-Null
    $code = $LASTEXITCODE

    if (($code -eq 0) -and (Test-Path -LiteralPath $videoOut)) {
      $didAutofit = $true
      Write-Host ("OK: autofit aplicado (exit={0}) (params: In={1} Srt={2} Out={3})" -f $code,$pIn,$pSrt,$pOut) -ForegroundColor DarkGray
    } else {
      Write-Host ("WARN: autofit falló (exit={0}). Se usa burn_in clásico." -f $code) -ForegroundColor DarkYellow
      $didAutofit = $false
      Remove-Item -LiteralPath $videoOut -Force -ErrorAction SilentlyContinue
    }
  }
}

if (-not $didAutofit) {
  pwsh -NoProfile -ExecutionPolicy Bypass -File $burnIn `
    -InVideo $videoIn `
    -SrtPath $srtOut `
    -OutVideo $videoOut `
    -FontSize $FontSize -Outline $Outline -Shadow $Shadow -MarginV $MarginV -Alignment $Alignment | Out-Null
}

if (-not (Test-Path -LiteralPath $videoOut)) { throw "No se generó video_subtitles: $videoOut" }

# 3) Compat: también escribe legacy
Copy-Item -LiteralPath $videoOut -Destination $videoLegacy -Force

if ($didAutofit) {
  Write-Host "OK: pipeline_subtitles = autofit" -ForegroundColor DarkGray
} else {
  Write-Host "OK: pipeline_subtitles = burn_in" -ForegroundColor DarkGray
}

$len = (Get-Item -LiteralPath $videoOut).Length
Write-Host "OK: subtitles live -> $videoOut ($len bytes)" -ForegroundColor Green
Write-Host "OK: subtitles live (legacy) -> $videoLegacy" -ForegroundColor DarkGray