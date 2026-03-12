Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Build-SceneTimelineShared {
  param(
    [Parameter(Mandatory=$true)][int[]]$Durations,
    [Parameter(Mandatory=$true)][int]$TotalMs
  )

  $count = @($Durations).Count
  if ($count -lt 1) { return @() }
  if ($TotalMs -lt $count) {
    throw ("TotalMs insuficiente para timeline: TotalMs={0} count={1}" -f $TotalMs, $count)
  }

  $clean = @()
  foreach ($d in @($Durations)) {
    $n = 0
    try { $n = [int]$d } catch { $n = 0 }
    if ($n -lt 1) { $n = 1 }
    $clean += $n
  }

  $sum = (@($clean) | Measure-Object -Sum).Sum
  if ([int]$sum -ne [int]$TotalMs) {
    throw ("Durations no suman TotalMs exactamente. sum={0} total={1}" -f [int]$sum, [int]$TotalMs)
  }

  $timeline = @()
  $cur = 0

  for ($i = 0; $i -lt $count; $i++) {
    $st = [int]$cur
    $en = [int]($cur + $clean[$i])

    if ($i -eq ($count - 1)) {
      $en = [int]$TotalMs
    }

    if ($en -lt $st) {
      throw ("Timeline inválido en índice {0}: start={1} end={2}" -f $i, $st, $en)
    }

    $timeline += [pscustomobject]@{
      index       = [int]$i
      start_ms    = [int]$st
      end_ms      = [int]$en
      duration_ms = [int]($en - $st)
    }

    $cur = $en
  }

  if (@($timeline).Count -ne $count) {
    throw ("Timeline count inválido. expected={0} actual={1}" -f $count, @($timeline).Count)
  }

  $lastEnd = [int]$timeline[@($timeline).Count - 1].end_ms
  if ($lastEnd -ne [int]$TotalMs) {
    throw ("Timeline final inválido. last_end={0} total={1}" -f $lastEnd, [int]$TotalMs)
  }

  return @($timeline)
}