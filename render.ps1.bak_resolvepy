param(
  [Parameter(Mandatory=$true, Position=0)][string]$Prompt,
  [int]$Seed = 123,
  [int]$MaxScenes = 3,
  [ValidateSet('crop','letterbox')][string]$Fit = 'crop',
  [switch]$Subs,

  [ValidateSet('fixed','random','topic','menu','off')][string]$MusicMode = 'menu',
  [ValidateSet('fixed','dynamic')][string]$DuckingMode = 'dynamic',
  [double]$MusicVolume = 0.20,
  [double]$Ducking = 0.55,
  [string]$MusicDir = 'music',
  [string]$MusicTag = '',
  [string]$Music = ''  # solo útil si MusicMode=fixed
)

function Read-Default([string]$Label, [string]$Default) {
  $raw = Read-Host "$Label [$Default]"
  if ([string]::IsNullOrWhiteSpace($raw)) { return $Default }
  return $raw
}

Write-Host ""
Write-Host "=== STUDIO_MVP Launcher ==="
Write-Host "Prompt: $Prompt"
Write-Host ""

# Preguntas rápidas (enter = deja igual)
$MusicMode   = Read-Default "MusicMode (fixed/random/topic/menu/off)" $MusicMode
$DuckingMode = Read-Default "DuckingMode (fixed/dynamic)" $DuckingMode
$MusicVolume = [double](Read-Default "MusicVolume (puede ser > 1.0 si la música es bajita)" "$MusicVolume")
$Ducking     = [double](Read-Default "Ducking (0.25..0.80)" "$Ducking")
$MaxScenes   = [int](Read-Default "MaxScenes" "$MaxScenes")

if (-not (Test-Path .\run.py)) {
  throw "No encuentro run.py (ejecuta este script en la raíz del proyecto)."
}

$pyArgs = @("run.py", $Prompt,
  "--seed", "$Seed",
  "--max_scenes", "$MaxScenes",
  "--fit", "$Fit",
  "--music_mode", "$MusicMode",
  "--ducking_mode", "$DuckingMode",
  "--music_volume", "$MusicVolume",
  "--ducking", "$Ducking",
  "--music_dir", "$MusicDir"
)

if ($Subs) { $pyArgs += "--subs" }
if (-not [string]::IsNullOrWhiteSpace($MusicTag)) { $pyArgs += @("--music_tag", "$MusicTag") }
if (-not [string]::IsNullOrWhiteSpace($Music) -and $MusicMode -eq "fixed") { $pyArgs += @("--music", "$Music") }

Write-Host ""
Write-Host "Ejecutando: python $($pyArgs -join ' ')"
Write-Host ""

python @pyArgs
