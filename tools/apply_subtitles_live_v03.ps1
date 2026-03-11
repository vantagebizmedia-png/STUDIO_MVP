param(
  [Parameter(Mandatory=$false)][string]$LiveDir,
  [Parameter(Mandatory=$false)][string]$WorkspaceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null

function Fail([string]$m) {
  throw "APPLY_SUBTITLES_LIVE_V03 FAIL: $m"
}

function Get-VideoDimensions {
  param(
    [Parameter(Mandatory=$true)][string]$VideoPath
  )

  $ffprobeOutput = & ffprobe `
    -v error `
    -select_streams v:0 `
    -show_entries stream=width,height `
    -of json `
    $VideoPath 2>&1

  if ($LASTEXITCODE -ne 0) {
    $msg = ($ffprobeOutput | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($msg)) {
      $msg = "ffprobe falló leyendo dimensiones de video"
    }
    Fail $msg
  }

  $ffprobeJson = ($ffprobeOutput | Out-String).Trim()
  if ([string]::IsNullOrWhiteSpace($ffprobeJson)) {
    Fail "ffprobe no devolvió dimensiones"
  }

  $obj = $ffprobeJson | ConvertFrom-Json
  $streams = @($obj.streams)
  if ($streams.Count -lt 1) {
    Fail "ffprobe no encontró stream de video"
  }

  $stream0 = $streams[0]
  $wProp = $stream0.PSObject.Properties["width"]
  $hProp = $stream0.PSObject.Properties["height"]

  if ($null -eq $wProp -or $null -eq $wProp.Value) {
    Fail "ffprobe no devolvió width"
  }
  if ($null -eq $hProp -or $null -eq $hProp.Value) {
    Fail "ffprobe no devolvió height"
  }

  return [pscustomobject]@{
    Width  = [int]$wProp.Value
    Height = [int]$hProp.Value
  }
}

function Get-SubtitleStyle {
  param(
    [Parameter(Mandatory=$true)][int]$VideoWidth,
    [Parameter(Mandatory=$true)][int]$VideoHeight
  )

  if ($VideoWidth -eq 1080 -and $VideoHeight -eq 1920) {
    return [pscustomobject]@{
      FontSize      = 11
      MarginV       = 86
      MarginL       = 84
      MarginR       = 84
      Outline       = 1
      Shadow        = 0
      Alignment     = 1
      Bold          = 0
      Spacing       = 0
      BorderStyle   = 1
      PrimaryColour = "&H00FFFFFF"
      OutlineColour = "&H00202020"
      BackColour    = "&H00000000"
    }
  }

  return [pscustomobject]@{
    FontSize      = 10
    MarginV       = 72
    MarginL       = 72
    MarginR       = 72
    Outline       = 1
    Shadow        = 0
    Alignment     = 1
    Bold          = 0
    Spacing       = 0
    BorderStyle   = 1
    PrimaryColour = "&H00FFFFFF"
    OutlineColour = "&H00202020"
    BackColour    = "&H00000000"
  }
}

function Normalize-SubtitleText {
  param(
    [Parameter(Mandatory=$true)][string]$Text
  )

  $t = $Text -replace "`r`n", "`n"
  $t = $t -replace "`r", "`n"
  $t = $t -replace '\\N', ' '
  $t = [regex]::Replace($t, '\s+', ' ').Trim()
  return $t
}

function Add-Ellipsis {
  param(
    [Parameter(Mandatory=$true)][string]$Text,
    [Parameter(Mandatory=$true)][int]$MaxChars
  )

  $ellipsis = "…"
  $clean = [string]$Text
  $clean = $clean.Trim()

  if ([string]::IsNullOrWhiteSpace($clean)) {
    return $ellipsis
  }

  if ($clean.Length -ge $MaxChars) {
    if ($MaxChars -le 1) {
      return $ellipsis
    }
    return ($clean.Substring(0, $MaxChars - 1).TrimEnd() + $ellipsis)
  }

  return ($clean + $ellipsis)
}

function Wrap-SubtitleText {
  param(
    [Parameter(Mandatory=$true)][string]$Text,
    [int]$MaxLines = 2,
    [int]$MaxCharsPerLine = 34
  )

  $text = Normalize-SubtitleText -Text $Text
  if ([string]::IsNullOrWhiteSpace($text)) {
    return ""
  }

  $words = @($text -split '\s+' | Where-Object { $_ -and $_.Trim().Length -gt 0 })
  if ($words.Count -eq 0) {
    return ""
  }

  $lines = New-Object System.Collections.Generic.List[string]
  $current = ""
  $i = 0
  $overflow = $false

  while ($i -lt $words.Count) {
    $w = $words[$i]

    if ([string]::IsNullOrWhiteSpace($current)) {
      $candidate = $w
    }
    else {
      $candidate = "$current $w"
    }

    if ($candidate.Length -le $MaxCharsPerLine) {
      $current = $candidate
      $i++
      continue
    }

    if (-not [string]::IsNullOrWhiteSpace($current)) {
      $lines.Add($current)
      $current = ""

      if ($lines.Count -ge $MaxLines) {
        $overflow = $true
        break
      }

      continue
    }

    $lines.Add((Add-Ellipsis -Text $w -MaxChars $MaxCharsPerLine))
    $i++

    if ($lines.Count -ge $MaxLines -and $i -lt $words.Count) {
      $overflow = $true
      break
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($current) -and $lines.Count -lt $MaxLines) {
    $lines.Add($current)
  }
  elseif (-not [string]::IsNullOrWhiteSpace($current) -and $lines.Count -ge $MaxLines) {
    $overflow = $true
  }

  if ($lines.Count -eq 0) {
    $lines.Add((Add-Ellipsis -Text $text -MaxChars $MaxCharsPerLine))
  }

  if ($overflow) {
    $lastIndex = $lines.Count - 1
    $lines[$lastIndex] = Add-Ellipsis -Text $lines[$lastIndex] -MaxChars $MaxCharsPerLine
  }

  return ($lines -join "`n")
}

function Convert-SrtToTwoLineSafe {
  param(
    [Parameter(Mandatory=$true)][string]$InputPath,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [int]$MaxLines = 2,
    [int]$MaxCharsPerLine = 34
  )

  $raw = Get-Content -LiteralPath $InputPath -Raw -Encoding UTF8
  $raw = $raw -replace "`r`n", "`n"
  $raw = $raw -replace "`r", "`n"

  $blocks = [regex]::Split($raw.Trim(), "\n\s*\n+")
  $outBlocks = New-Object System.Collections.Generic.List[string]

  foreach ($block in $blocks) {
    $b = [string]$block
    $b = $b.Trim()
    if ([string]::IsNullOrWhiteSpace($b)) {
      continue
    }

    $lines = @($b -split "`n")
    if ($lines.Count -lt 2) {
      continue
    }

    $idx = $lines[0].Trim()
    $timing = $lines[1].Trim()
    $textLines = @()

    if ($lines.Count -gt 2) {
      $textLines = $lines[2..($lines.Count - 1)]
    }

    $text = ($textLines -join " ")
    $text = Normalize-SubtitleText -Text $text
    $wrapped = Wrap-SubtitleText -Text $text -MaxLines $MaxLines -MaxCharsPerLine $MaxCharsPerLine

    if ([string]::IsNullOrWhiteSpace($wrapped)) {
      continue
    }

    $outBlocks.Add(($idx + "`n" + $timing + "`n" + $wrapped))
  }

  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  $parent = Split-Path $OutputPath -Parent
  if (-not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
  }

  [System.IO.File]::WriteAllText(
    $OutputPath,
    (($outBlocks -join "`n`n") + "`n"),
    $utf8NoBom
  )
}

if (-not $LiveDir -or $LiveDir.Trim().Length -eq 0) {
  if (-not $WorkspaceRoot -or $WorkspaceRoot.Trim().Length -eq 0) {
    Fail "Falta -LiveDir o -WorkspaceRoot"
  }
  $LiveDir = Join-Path $WorkspaceRoot "runs\smoke_live_latest"
}

$live = (Resolve-Path $LiveDir).Path

$videoBase = Join-Path $live "video.mp4"
$srtFile   = Join-Path $live "captions_v03.srt"
$burnSrt   = Join-Path $live "_captions_burn_v03.srt"
$outVideo  = Join-Path $live "video_subs.mp4"

if (-not (Test-Path -LiteralPath $videoBase)) {
  Fail "Falta video base: $videoBase"
}

if (-not (Test-Path -LiteralPath $srtFile)) {
  Fail "Falta SRT: $srtFile"
}

$dims = Get-VideoDimensions -VideoPath $videoBase
$style = Get-SubtitleStyle -VideoWidth $dims.Width -VideoHeight $dims.Height

Convert-SrtToTwoLineSafe -InputPath $srtFile -OutputPath $burnSrt -MaxLines 2 -MaxCharsPerLine 34

if (-not (Test-Path -LiteralPath $burnSrt)) {
  Fail "No se generó SRT de burn-in: $burnSrt"
}

$burnSrtFF = ($burnSrt -replace '\\','/') -replace ':','\:'

$subtitleStyle = @(
  "Fontsize=$($style.FontSize)"
  "Outline=$($style.Outline)"
  "Shadow=$($style.Shadow)"
  "MarginV=$($style.MarginV)"
  "MarginL=$($style.MarginL)"
  "MarginR=$($style.MarginR)"
  "Alignment=$($style.Alignment)"
  "Bold=$($style.Bold)"
  "Spacing=$($style.Spacing)"
  "BorderStyle=$($style.BorderStyle)"
  "PrimaryColour=$($style.PrimaryColour)"
  "OutlineColour=$($style.OutlineColour)"
  "BackColour=$($style.BackColour)"
) -join ','

$subtitleFilter = "subtitles='$burnSrtFF':force_style='$subtitleStyle'"

Write-Host "Aplicando burn-in de subtítulos..." -ForegroundColor Cyan
Write-Host "LIVE         : $live"
Write-Host "Base         : $videoBase"
Write-Host "SRT source   : $srtFile"
Write-Host "SRT burn     : $burnSrt"
Write-Host "Out          : $outVideo"
Write-Host "VideoW       : $($dims.Width)"
Write-Host "VideoH       : $($dims.Height)"
Write-Host "Fontsize     : $($style.FontSize)"
Write-Host "MarginV      : $($style.MarginV)"
Write-Host "MarginL      : $($style.MarginL)"
Write-Host "MarginR      : $($style.MarginR)"
Write-Host "Outline      : $($style.Outline)"
Write-Host "Shadow       : $($style.Shadow)"
Write-Host "Alignment    : $($style.Alignment)"
Write-Host "Bold         : $($style.Bold)"
Write-Host "Spacing      : $($style.Spacing)"
Write-Host "BorderStyle  : $($style.BorderStyle)"
Write-Host "PrimaryColor : $($style.PrimaryColour)"
Write-Host "OutlineColor : $($style.OutlineColour)"
Write-Host "BackColor    : $($style.BackColour)"

Write-Host ""
Write-Host "== PREVIEW SRT BURN (primeros 20 renglones) ==" -ForegroundColor DarkCyan
Get-Content -LiteralPath $burnSrt -Encoding UTF8 | Select-Object -First 20 | ForEach-Object { $_ }

if (Test-Path -LiteralPath $outVideo) {
  Remove-Item -LiteralPath $outVideo -Force -ErrorAction SilentlyContinue
}

$ffmpegOutput = & ffmpeg `
  -hide_banner `
  -loglevel error `
  -y `
  -i $videoBase `
  -vf $subtitleFilter `
  -c:v libx264 `
  -pix_fmt yuv420p `
  -preset veryfast `
  -crf 18 `
  -c:a copy `
  $outVideo 2>&1

if ($LASTEXITCODE -ne 0) {
  Write-Host ""
  Write-Host "== FFMPEG STDERR ==" -ForegroundColor Yellow
  $ffmpegOutput | ForEach-Object { $_ }
  Fail "ffmpeg falló aplicando subtítulos"
}

if (-not (Test-Path -LiteralPath $outVideo)) {
  Fail "No se generó el archivo esperado: $outVideo"
}

$len = (Get-Item -LiteralPath $outVideo).Length
Write-Host ("OK: subtítulos aplicados -> {0} bytes" -f $len) -ForegroundColor Green
