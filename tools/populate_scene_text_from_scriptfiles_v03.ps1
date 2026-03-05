param(
  [Parameter(Mandatory=$true)][string]$LiveDir,
  [int]$Seed = 123
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null

function Write-Utf8NoBom([string]$Path, [string]$Text) {
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Text, $utf8NoBom)
}

function Is-PlaceholderText([string]$t) {
  $t = ($t ?? "").ToString().Trim()
  if (-not $t) { return $true }
  return ($t -match '(?i)^(escena)\s*\d+\s*$')
}

function Set-Note([object]$obj, [string]$name, $value) {
  if ($null -eq $obj) { return }
  if ($obj.PSObject.Properties.Match($name).Count -gt 0) { $obj.$name = $value }
  else { $obj | Add-Member -Force -NotePropertyName $name -NotePropertyValue $value }
}

$live = (Resolve-Path -LiteralPath $LiveDir).Path
$mf = Join-Path $live "manifest_v03.json"
if (-not (Test-Path -LiteralPath $mf)) { throw "No existe manifest_v03.json en: $live" }

$j = Get-Content -LiteralPath $mf -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $j.scenes_v03) { throw "manifest no tiene scenes_v03" }

# normaliza a array
$scenes = @()
if ($j.scenes_v03 -is [System.Array]) { $scenes = $j.scenes_v03 }
elseif ($j.scenes_v03 -is [System.Collections.IDictionary]) { $scenes = @($j.scenes_v03.Values) }
else { $scenes = @($j.scenes_v03) }

if ($scenes.Count -lt 1) { throw "scenes_v03 vacío" }

# busca script_*.txt en live y live\artifacts
$files = @()
$files += Get-ChildItem -LiteralPath $live -File -Filter "script_*.txt" -ErrorAction SilentlyContinue
$art = Join-Path $live "artifacts"
if (Test-Path -LiteralPath $art) {
  $files += Get-ChildItem -LiteralPath $art -File -Filter "script_*.txt" -ErrorAction SilentlyContinue
}

# filtra mínimo razonable
$files = @($files | Where-Object { $_.Length -ge 40 } | Sort-Object LastWriteTime -Descending)

if ($files.Count -lt 1) {
  Write-Host "WARN: No encontré script_*.txt >= 40 bytes. No se cambió nada." -ForegroundColor DarkYellow
  exit 0
}

$best = $files[0]
$scriptText = (Get-Content -LiteralPath $best.FullName -Raw -Encoding UTF8).Trim()
$scriptText = ($scriptText -replace "\s+", " ").Trim()

if (-not $scriptText -or $scriptText.Length -lt 40) {
  Write-Host "WARN: script encontrado pero muy corto. No se cambió nada. file=$($best.FullName)" -ForegroundColor DarkYellow
  exit 0
}

Write-Host ("OK: usando script -> {0} (len={1})" -f $best.FullName, $scriptText.Length) -ForegroundColor DarkGray

# split por frases
$parts = @()
try {
  $parts = @(
    ($scriptText -split '(?<=[\.\!\?])\s+') |
    Where-Object { $_ -and $_.Trim().Length -gt 0 } |
    ForEach-Object { $_.Trim() }
  )
} catch { $parts = @() }

if ($parts.Count -lt 1) {
  $parts = @(
    ($scriptText -split '(?<=[\,\;])\s+') |
    Where-Object { $_ -and $_.Trim().Length -gt 0 } |
    ForEach-Object { $_.Trim() }
  )
}

if ($parts.Count -lt 1) {
  # último fallback: partes de tamaño fijo
  $parts = @()
  $chunkSize = 120
  for ($i=0; $i -lt $scriptText.Length; $i += $chunkSize) {
    $len = [Math]::Min($chunkSize, $scriptText.Length - $i)
    $parts += $scriptText.Substring($i, $len).Trim()
  }
  $parts = @($parts | Where-Object { $_ })
}

$N = $scenes.Count
$P = $parts.Count
Write-Host ("INFO: scenes={0} parts={1}" -f $N, $P) -ForegroundColor DarkGray

# asignación “spread”
$changed = 0
for ($i=0; $i -lt $N; $i++) {
  $a = [int][Math]::Floor(($i    * $P) / $N)
  $b = [int][Math]::Floor((($i+1)* $P) / $N) - 1
  if ($a -lt 0) { $a = 0 }
  if ($b -lt $a) { $b = $a }
  if ($b -ge $P) { $b = $P - 1 }

  $chunk = ($parts[$a..$b] -join " ").Trim()
  if (-not $chunk) { $chunk = $parts[[Math]::Min($P-1,$i)].Trim() }

  $cur = ""
  try { $cur = [string]$scenes[$i].text } catch { $cur = "" }

  if (Is-PlaceholderText $cur) {
    $scenes[$i].text = $chunk
    $changed++
  }
  Set-Note -obj $scenes[$i] -name "script_text" -value $chunk
}

$j.scenes_v03 = $scenes

$out = $j | ConvertTo-Json -Depth 99
$out = $out -replace "`r`n", "`n"
Write-Utf8NoBom -Path $mf -Text $out

Write-Host ("OK: scenes text populated. changed_text={0} wrote={1}" -f $changed, $mf) -ForegroundColor Green
