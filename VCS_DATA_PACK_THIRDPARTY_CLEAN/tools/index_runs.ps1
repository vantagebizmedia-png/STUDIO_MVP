param([int]$Take = 200)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

$ws = $env:STUDIO_WORKSPACE
if (-not $ws) { throw "STUDIO_WORKSPACE no esta seteado." }
if (-not [IO.Path]::IsPathRooted($ws)) { throw "STUDIO_WORKSPACE debe ser absoluto: $ws" }

$runsDir = Join-Path $ws "runs"
$outDir  = Join-Path $ws "output"
$idxDir  = Join-Path $outDir "_index"
New-Item -ItemType Directory -Force $idxDir | Out-Null

$rows = @()

if (Test-Path -LiteralPath $runsDir) {
  $runs = Get-ChildItem -LiteralPath $runsDir -Directory -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First $Take

  foreach ($r in $runs) {
    $pack = Join-Path $r.FullName "content_pack"
    $man  = Join-Path $pack "manifest.json"
    $topic = ""
    $lang  = ""
    if (Test-Path -LiteralPath $man) {
      try {
        $o = Get-Content -LiteralPath $man -Raw | ConvertFrom-Json
        $lang = "$($o.language)"
        # intenta varios campos
        if ($o.topic_summary -and $o.topic_summary.core_topic) { $topic = "$($o.topic_summary.core_topic)" }
        elseif ($o.prompt) { $topic = "$($o.prompt)" }
      } catch { }
    }

    $rows += [pscustomobject]@{
      RunId     = $r.Name
      LastWrite = $r.LastWriteTime
      Topic     = $topic
      Lang      = $lang
      PackDir   = $pack
    }
  }
}

$csv = Join-Path $idxDir "runs_index.csv"
$rows | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
Write-Host "OK: index -> $csv" -ForegroundColor Green

# quick view
$rows | Select-Object -First 20 | Format-Table RunId,LastWrite,Lang,Topic -AutoSize