param(
  [Parameter(Mandatory=$true)][string]$InDir,
  [Parameter(Mandatory=$true)][string]$OutZip
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null

function Fail([string]$msg) { throw "HANDOFF_PACK FAIL: $msg" }

$in = (Resolve-Path -LiteralPath $InDir).Path

# OutZip absoluto
if ([System.IO.Path]::IsPathRooted($OutZip)) {
  $zipPath = [System.IO.Path]::GetFullPath($OutZip)
} else {
  $zipPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $OutZip))
}

$zipDir = Split-Path -Parent $zipPath
if (-not $zipDir) { Fail "OutZip inválido: $OutZip" }
if (-not (Test-Path -LiteralPath $zipDir)) { New-Item -ItemType Directory -Force -Path $zipDir | Out-Null }

# outputs esperados
$videoBase  = Join-Path $in "video.mp4"
$videoAuto  = Join-Path $in "video_music_auto.mp4"
$videoFinal = Join-Path $in "video_final.mp4"

if (-not (Test-Path -LiteralPath $videoBase))  { Fail "Falta video.mp4 en: $in" }
if (-not (Test-Path -LiteralPath $videoAuto))  { Fail "Falta video_music_auto.mp4 en: $in" }
if (-not (Test-Path -LiteralPath $videoFinal)) { Fail "Falta video_final.mp4 en: $in" }

# ZIP temporal en mismo dir (pero con escritura permisiva)
$zipLeaf = Split-Path -Leaf $zipPath
$tmpZip  = Join-Path $zipDir (".tmp_{0}.{1}" -f $zipLeaf, [Guid]::NewGuid().ToString("N"))

# Limpia tmp si existiera
if (Test-Path -LiteralPath $tmpZip) { Remove-Item -LiteralPath $tmpZip -Force }

# ---- Crear ZIP de forma robusta (FileShare.ReadWrite) + determinista ----
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function New-DeterministicZip([string]$srcDir, [string]$destZip) {
  $srcDir = (Resolve-Path -LiteralPath $srcDir).Path

  # Enumera archivos (recursivo) y ordena por ruta relativa (estable)
  $files = Get-ChildItem -LiteralPath $srcDir -Recurse -File | ForEach-Object {
    $full = $_.FullName
    $rel  = $full.Substring($srcDir.Length).TrimStart('\','/')
    # Excluye zips existentes y temporales para evitar self-include
    if ($rel -match '(^|[\\/])\.tmp_' ) { return }
    if ($rel.ToLowerInvariant().EndsWith('.zip')) { return }
    [pscustomobject]@{ Full=$full; Rel=$rel -replace '\\','/' }
  } | Where-Object { $_ -ne $null } | Sort-Object Rel

  if ($files.Count -lt 1) { Fail "No hay archivos para zippear en: $srcDir" }

  # FileShare.ReadWrite permite que AV/Indexer lea sin romper
  $fs = [System.IO.FileStream]::new(
    $destZip,
    [System.IO.FileMode]::CreateNew,
    [System.IO.FileAccess]::ReadWrite,
    [System.IO.FileShare]::ReadWrite
  )

  try {
    $zip = [System.IO.Compression.ZipArchive]::new($fs, [System.IO.Compression.ZipArchiveMode]::Create, $true)
    try {
      $fixedTime = [DateTimeOffset]::new([DateTime]::SpecifyKind([DateTime]'1980-01-01T00:00:00', 'Utc'))

      foreach ($f in $files) {
        $entry = $zip.CreateEntry($f.Rel, [System.IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = $fixedTime

        $inStream  = [System.IO.File]::Open($f.Full, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
          $outStream = $entry.Open()
          try {
            $inStream.CopyTo($outStream)
          } finally {
            $outStream.Dispose()
          }
        } finally {
          $inStream.Dispose()
        }
      }
    } finally {
      $zip.Dispose()
    }
  } finally {
    $fs.Dispose()
  }
}

try {
  New-DeterministicZip -srcDir $in -destZip $tmpZip
} catch {
  Fail ("ZipArchive falló (tmp): {0}" -f $_.Exception.Message)
}

if (-not (Test-Path -LiteralPath $tmpZip)) { Fail "No se creó ZIP temporal: $tmpZip" }
if ((Get-Item -LiteralPath $tmpZip).Length -lt 200) { Fail "ZIP temporal demasiado pequeño: $tmpZip" }

# ---- Replace final (retry por locks) ----
$maxTry = 8
for ($t=1; $t -le $maxTry; $t++) {
  try {
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force -ErrorAction Stop }
    Move-Item -LiteralPath $tmpZip -Destination $zipPath -Force -ErrorAction Stop
    break
  } catch {
    if ($t -eq $maxTry) {
      Fail ("ZIP final bloqueado: {0}. Dejé el ZIP temporal en: {1}. Error: {2}" -f $zipPath, $tmpZip, $_.Exception.Message)
    }
    Start-Sleep -Milliseconds 350
  }
}

if (-not (Test-Path -LiteralPath $zipPath)) { Fail "No se materializó ZIP final: $zipPath" }

# hashes + ready (en carpeta handoff)
$hashFile  = Join-Path $in "HASHES_SHA256.txt"
$readyFile = Join-Path $in "HANDOFF_READY.txt"

function Sha([string]$p) { (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLowerInvariant() }
function Sz([string]$p) { (Get-Item -LiteralPath $p).Length }

$items = @(
  [pscustomobject]@{ name="video.mp4";            path=$videoBase  }
  [pscustomobject]@{ name="video_music_auto.mp4"; path=$videoAuto  }
  [pscustomobject]@{ name="video_final.mp4";      path=$videoFinal }
  [pscustomobject]@{ name=(Split-Path -Leaf $zipPath); path=$zipPath }
) | Sort-Object name

$lines = foreach ($it in $items) {
  "{0}  {1}  {2}" -f (Sha $it.path), (Sz $it.path), $it.name
}
Set-Content -LiteralPath $hashFile -Encoding UTF8 -Value $lines

$ready = @()
$ready += "HANDOFF_READY v0.3"
$ready += "FILES:"
foreach ($it in $items) { $ready += ("- {0}" -f $it.name) }
$ready += "HASHES_SHA256:"
$ready += $lines
Set-Content -LiteralPath $readyFile -Encoding UTF8 -Value $ready

Write-Host "OK handoff_pack_v03" -ForegroundColor Green
Write-Host ("IN : {0}" -f $in)
Write-Host ("ZIP: {0}" -f $zipPath)
Write-Host ("HASH: {0}" -f $hashFile)
Write-Host ("READY:{0}" -f $readyFile)

Get-Item -LiteralPath $zipPath | Select-Object Name, Length, FullName
exit 0
