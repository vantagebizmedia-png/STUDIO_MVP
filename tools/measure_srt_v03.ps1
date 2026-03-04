param(
  [Parameter(Mandatory=$true)][string]$SrtPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

if (-not (Test-Path -LiteralPath $SrtPath)) { throw "No existe SRT: $SrtPath" }

$lines = Get-Content -LiteralPath $SrtPath -Encoding UTF8

$maxCharsLine = 0
$maxLinesBlock = 0
$curLines = @()

function Flush-Block {
  if ($script:curLines.Count -gt 0) {
    $script:maxLinesBlock = [Math]::Max($script:maxLinesBlock, $script:curLines.Count)
    foreach ($l in $script:curLines) {
      $script:maxCharsLine = [Math]::Max($script:maxCharsLine, ($l.Length))
    }
  }
  $script:curLines = @()
}

foreach ($line in $lines) {
  if ($line -eq "") { Flush-Block; continue }
  if ($line -match "^\d+$") { continue }
  if ($line -match "^\d\d:\d\d:\d\d,\d\d\d\s+-->\s+\d\d:\d\d:\d\d,\d\d\d$") { continue }

  $curLines += $line
}
Flush-Block

[pscustomobject]@{
  srt_path = $SrtPath
  max_chars_line = $maxCharsLine
  max_lines_block = $maxLinesBlock
} | ConvertTo-Json -Depth 5
