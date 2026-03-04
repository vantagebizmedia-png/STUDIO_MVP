param(
  [string]$RepoRoot = "."
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-StagedFiles {
  $out = & git diff --cached --name-only --diff-filter=ACMRT 2>$null
  if ($LASTEXITCODE -ne 0) { return @() }
  return ($out | Where-Object { $_ -and $_.Trim() -ne "" })
}

function Test-IsTextFile([string]$Path) {
  $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
  $bin = @(
    ".png",".jpg",".jpeg",".webp",".gif",".mp4",".mov",".avi",".mkv",
    ".wav",".mp3",".flac",".zip",".7z",".rar",
    ".exe",".dll",".pdb",".rnnn"
  )
  return ($bin -notcontains $ext)
}

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path

$lt  = [char]60
$gt  = [char]62
$bad1 = ([string]$lt) + ([string]$lt) + ([string]$lt)
$bad2 = ([string]$gt) + ([string]$gt) + ([string]$gt)
$bad3 = ("PE" + "GA") + " " + ("AQ" + "U")
$bad4 = ("RE" + "PLACE") + " " + ("M" + "E")
$bad5 = ("TO" + "DO") + ":"
$bad6 = ("contenido" + " del" + " script")

$patterns = @(
  [regex]::Escape($bad1),
  [regex]::Escape($bad2),
  $bad3,
  $bad4,
  [regex]::Escape($bad5),
  $bad6
)

$staged = Get-StagedFiles
if (-not $staged -or $staged.Count -eq 0) { exit 0 }

$hits = New-Object System.Collections.Generic.List[object]

foreach ($rel in $staged) {
  $relNorm = ($rel -replace "\\","/")

  if ($relNorm -ieq "VCS_DATA_PACK_THIRDPARTY_CLEAN/tools/guard_no_placeholders.ps1") { continue }

  $full = Join-Path $repo $rel
  if (-not (Test-Path -LiteralPath $full)) { continue }

  if (-not (Test-IsTextFile $full)) { continue }

  $txt = $null
  try {
    $txt = Get-Content -LiteralPath $full -Raw -Encoding UTF8
  } catch {
    try { $txt = Get-Content -LiteralPath $full -Raw } catch { $txt = $null }
  }

  if ($null -eq $txt) { continue }

  foreach ($p in $patterns) {
    if ([regex]::IsMatch($txt, $p)) {
      $hits.Add([pscustomobject]@{
        File    = $relNorm
        Pattern = $p
      }) | Out-Null
    }
  }
}

if ($hits.Count -gt 0) {
  Write-Host "PRE-COMMIT BLOCKED: placeholders detectados" -ForegroundColor Red
  $hits | Sort-Object File,Pattern | Format-Table -AutoSize
  exit 1
}

exit 0
