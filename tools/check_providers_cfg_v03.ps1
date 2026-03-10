param(
  [string]$ProvidersPath = ".\config\providers.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

if (-not (Test-Path -LiteralPath $ProvidersPath)) { throw "Falta ProvidersPath: $ProvidersPath" }

$cfg = Get-Content -LiteralPath $ProvidersPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $cfg.providers) { throw "providers.json no tiene sección .providers" }

$names = @($cfg.providers.PSObject.Properties.Name | Sort-Object)

# Dónde buscamos wiring/uso real
$paths = @(
  ".\tools\*.ps1",
  ".\app\*.py", ".\app\**\*.py",
  ".\studio\*.py", ".\studio\**\*.py",
  ".\cli\*.py", ".\cli\**\*.py",
  ".\run.py",
  ".\studio.py"
)

Write-Host "== CHECK PROVIDERS CFG v0.3 ==" -ForegroundColor Green
Write-Host ("ProvidersPath: {0}" -f $ProvidersPath)
Write-Host ("Providers     : {0}" -f $names.Count)
Write-Host ""

$bad = @()

foreach ($name in $names) {
  $prov = $cfg.providers.$name

  # enabled default = true si falta
  $enabled = $true
  if ($prov -and ($prov.PSObject.Properties.Name -contains "enabled")) {
    $enabled = [bool]$prov.enabled
  }

  $patterns = @($name)

  switch ($name) {
    "openai_tts" {
      $patterns = @(
        "openai_tts",
        "ProviderVoice(",
        "tts.speak(",
        "audio/speech",
        "gpt-4o-mini-tts",
        "voice.active_provider",
        "voice.mode"
      )
    }
    "openai_responses" {
      $patterns = @(
        "openai_responses",
        "/v1/responses",
        "gpt-4o-mini"
      )
    }
    "pixabay_image" {
      $patterns = @(
        "pixabay_image",
        "pixabay",
        "stock_query_pixabay_v03.ps1",
        "PIXABAY_API_KEY"
      )
    }
    "openai_images" {
      $patterns = @(
        "openai_images",
        "/v1/images/generations",
        "gpt-image-1"
      )
    }
  }

  $hitList = New-Object System.Collections.Generic.List[object]
  foreach ($pat in $patterns) {
    $hh = Select-String -Path $paths -Pattern $pat -SimpleMatch -ErrorAction SilentlyContinue
    if ($hh) {
      foreach ($one in @($hh)) {
        $null = $hitList.Add($one)
      }
    }
  }

  $cnt = $hitList.Count

  if (-not $enabled) {
    Write-Host ("SKIP (disabled) : {0}  hits={1}" -f $name, $cnt) -ForegroundColor DarkGray
    continue
  }

  if ($cnt -le 0) {
    Write-Host ("FAIL (enabled)  : {0}  hits={1}" -f $name, $cnt) -ForegroundColor Red
    $bad += $name
  } else {
    Write-Host ("OK   (enabled)  : {0}  hits={1}" -f $name, $cnt) -ForegroundColor Cyan
  }
}

Write-Host ""
if ($bad.Count -gt 0) {
  throw ("Providers enabled sin wiring/uso (0 hits): " + ($bad -join ", "))
}

Write-Host "CHECK OK: providers.json consistente con wiring del repo." -ForegroundColor Green