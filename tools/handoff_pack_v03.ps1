param(
  [Parameter(Mandatory=$true)][string]$InDir,
  [Parameter(Mandatory=$true)][string]$OutZip
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null

function Fail([string]$msg) { throw "HANDOFF_PACK FAIL: $msg" }

$in = (Resolve-Path -LiteralPath $InDir).Path

# valida que finalize ya dejó READY/HASHES (pack NO los toca)
$hashFile  = Join-Path $in "HASHES_SHA256.txt"
$readyFile = Join-Path $in "HANDOFF_READY.txt"
if (-not (Test-Path -LiteralPath $hashFile))  { Fail "Falta HASHES_SHA256.txt (lo crea finalize): $hashFile" }
if (-not (Test-Path -LiteralPath $readyFile)) { Fail "Falta HANDOFF_READY.txt (lo crea finalize): $readyFile" }

# OutZip absoluto
if ([System.IO.Path]::IsPathRooted($OutZip)) {
  $zipPath = [System.IO.Path]::GetFullPath($OutZip)
} else {
  $zipPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $OutZip))
}

$zipDir = Split-Path -Parent $zipPath
if (-not $zipDir) { Fail "OutZip inválido: $OutZip" }
if (-not (Test-Path -LiteralPath $zipDir)) { New-Item -ItemType Directory -Force -Path $zipDir | Out-Null }

# ZIP temporal
$zipLeaf = Split-Path -Leaf $zipPath
$tmpZip  = Join-Path $zipDir (".tmp_{0}.{1}" -f $zipLeaf, [Guid]::NewGuid().ToString("N"))
if (Test-Path -LiteralPath $tmpZip) { Remove-Item -LiteralPath $tmpZip -Force }

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function New-DeterministicZip([string]$srcDir, [string]$destZip) {
  $srcDir = (Resolve-Path -LiteralPath $srcDir).Path

  $files = Get-ChildItem -LiteralPath $srcDir -Recurse -File | ForEach-Object {
    $full = $_.FullName
    $rel  = $full.Substring($srcDir.Length).TrimStart('\','/')
    if ($rel -match '(^|[\\/])\.tmp_') { return }
    if ($rel.ToLowerInvariant().EndsWith('.zip')) { return }
    [pscustomobject]@{ Full=$full; Rel=$rel -replace '\\','/' }
  } | Where-Object { $_ -ne $null } | Sort-Object Rel

  if ($files.Count -lt 1) { Fail "No hay archivos para zippear en: $srcDir" }

  $fs = [System.IO.FileStream]::new($destZip,[System.IO.FileMode]::CreateNew,[System.IO.FileAccess]::ReadWrite,[System.IO.FileShare]::ReadWrite)
  try {
    $zip = [System.IO.Compression.ZipArchive]::new($fs, [System.IO.Compression.ZipArchiveMode]::Create, $true)
    try {
      $fixedTime = [DateTimeOffset]::new([DateTime]::SpecifyKind([DateTime]'1980-01-01T00:00:00', 'Utc'))
      foreach ($f in $files) {
        $entry = $zip.CreateEntry($f.Rel, [System.IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = $fixedTime

        $inStream = [System.IO.File]::Open($f.Full,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::ReadWrite)
        try {
          $outStream = $entry.Open()
          try { $inStream.CopyTo($outStream) } finally { $outStream.Dispose() }
        } finally { $inStream.Dispose() }
      }
    } finally { $zip.Dispose() }
  } finally { $fs.Dispose() }
}

New-DeterministicZip -srcDir $in -destZip $tmpZip

if (-not (Test-Path -LiteralPath $tmpZip)) { Fail "No se creó ZIP temporal: $tmpZip" }
if ((Get-Item -LiteralPath $tmpZip).Length -lt 200) { Fail "ZIP temporal demasiado pequeño: $tmpZip" }

$maxTry = 8
for ($t=1; $t -le $maxTry; $t++) {
  try {
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force -ErrorAction Stop }
    Move-Item -LiteralPath $tmpZip -Destination $zipPath -Force -ErrorAction Stop
    break
  } catch {
    if ($t -eq $maxTry) { Fail ("ZIP final bloqueado: {0}. tmp={1} err={2}" -f $zipPath,$tmpZip,$_.Exception.Message) }
    Start-Sleep -Milliseconds 350
  }
}

Write-Host "OK handoff_pack_v03 (solo ZIP; no toca READY/HASHES)" -ForegroundColor Green
Write-Host ("ZIP: {0}" -f $zipPath)