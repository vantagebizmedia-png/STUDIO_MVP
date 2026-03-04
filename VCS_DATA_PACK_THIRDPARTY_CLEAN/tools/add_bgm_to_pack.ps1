param(
    [Parameter(Mandatory = $true)]
    [string]$VideoPath,

    [Parameter(Mandatory = $true)]
    [string]$MusicPath,

    [string]$OutputPath = "",

    [double]$BgmVolume = 0.12,
    [double]$FadeInSec = 1.5,
    [double]$FadeOutSec = 2.5,

    [switch]$ReplaceOriginal
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Require-Command {
    param([Parameter(Mandatory = $true)][string]$Name)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $cmd) {
        throw "No se encontró '$Name' en PATH. Instala FFmpeg y vuelve a intentar."
    }
}

function Get-InvariantDouble {
    param([Parameter(Mandatory = $true)][string]$Text)
    return [double]::Parse($Text.Trim(), [System.Globalization.CultureInfo]::InvariantCulture)
}

function Remove-IfExists {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if (Test-Path -LiteralPath $PathValue) {
        Remove-Item -LiteralPath $PathValue -Force -ErrorAction SilentlyContinue
    }
}

Require-Command -Name "ffmpeg"
Require-Command -Name "ffprobe"

if (-not (Test-Path -LiteralPath $VideoPath)) {
    throw "No existe VideoPath: $VideoPath"
}
if (-not (Test-Path -LiteralPath $MusicPath)) {
    throw "No existe MusicPath: $MusicPath"
}

$VideoPath = (Resolve-Path -LiteralPath $VideoPath).Path
$MusicPath = (Resolve-Path -LiteralPath $MusicPath).Path

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $videoDir  = Split-Path $VideoPath -Parent
    $videoBase = [System.IO.Path]::GetFileNameWithoutExtension($VideoPath)
    $OutputPath = Join-Path $videoDir ($videoBase + "_music.mp4")
}

$OutputDir = Split-Path $OutputPath -Parent
if (-not [string]::IsNullOrWhiteSpace($OutputDir)) {
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
}

Write-Host ""
Write-Host "=== add_bgm_to_pack ==="
Write-Host "VideoPath   : $VideoPath"
Write-Host "MusicPath   : $MusicPath"
Write-Host "OutputPath  : $OutputPath"
Write-Host "BgmVolume   : $BgmVolume"
Write-Host "FadeInSec   : $FadeInSec"
Write-Host "FadeOutSec  : $FadeOutSec"
Write-Host ""

$audioProbe = & ffprobe -v error `
    -select_streams a:0 `
    -show_entries stream=index `
    -of csv=p=0 `
    "$VideoPath"

if ([string]::IsNullOrWhiteSpace(($audioProbe | Out-String).Trim())) {
    throw "El video no tiene pista de audio. Este script espera que la narración ya esté dentro del MP4."
}

$durationText = & ffprobe -v error `
    -show_entries format=duration `
    -of default=noprint_wrappers=1:nokey=1 `
    "$VideoPath"

$durationSec = Get-InvariantDouble -Text ($durationText | Out-String)
if ($durationSec -le 0) {
    throw "No se pudo leer la duración del video."
}

$fadeOutStart = $durationSec - $FadeOutSec
if ($fadeOutStart -lt 0) {
    $fadeOutStart = 0
}

$culture = [System.Globalization.CultureInfo]::InvariantCulture
$durationStr     = $durationSec.ToString("0.###", $culture)
$bgmVolumeStr    = $BgmVolume.ToString("0.###", $culture)
$fadeInStr       = $FadeInSec.ToString("0.###", $culture)
$fadeOutStr      = $FadeOutSec.ToString("0.###", $culture)
$fadeOutStartStr = $fadeOutStart.ToString("0.###", $culture)

$tempOutput = [System.IO.Path]::Combine(
    [System.IO.Path]::GetDirectoryName($OutputPath),
    ([System.IO.Path]::GetFileNameWithoutExtension($OutputPath) + ".tmp" + [System.IO.Path]::GetExtension($OutputPath))
)

$tempVoice = [System.IO.Path]::Combine(
    [System.IO.Path]::GetDirectoryName($OutputPath),
    ([System.IO.Path]::GetFileNameWithoutExtension($OutputPath) + ".voice_exact.wav")
)

$tempBgm = [System.IO.Path]::Combine(
    [System.IO.Path]::GetDirectoryName($OutputPath),
    ([System.IO.Path]::GetFileNameWithoutExtension($OutputPath) + ".bgm_exact.wav")
)

$tempMix = [System.IO.Path]::Combine(
    [System.IO.Path]::GetDirectoryName($OutputPath),
    ([System.IO.Path]::GetFileNameWithoutExtension($OutputPath) + ".mix_exact.wav")
)

Remove-IfExists $tempOutput
Remove-IfExists $tempVoice
Remove-IfExists $tempBgm
Remove-IfExists $tempMix

try {
    Write-Host "Extrayendo voz exacta con padding..."
    $voiceFilter = "aresample=48000,apad=whole_dur=${durationStr},atrim=0:${durationStr},asetpts=N/SR/TB"
    Write-Host "VOICE FILTER: $voiceFilter"
    $voiceArgs = @(
        "-y",
        "-i", $VideoPath,
        "-map", "0:a:0",
        "-vn",
        "-af", $voiceFilter,
        "-ac", "2",
        "-ar", "48000",
        "-c:a", "pcm_s16le",
        $tempVoice
    )
    & ffmpeg @voiceArgs
    if ($LASTEXITCODE -ne 0) {
        throw "FFmpeg falló extrayendo voz exacta. Código $LASTEXITCODE"
    }

    Write-Host "Preparando BGM exacta..."
    $bgmFilter = "aresample=48000,asetpts=N/SR/TB,volume=${bgmVolumeStr},afade=t=in:st=0:d=${fadeInStr},afade=t=out:st=${fadeOutStartStr}:d=${fadeOutStr},atrim=0:${durationStr}"
    Write-Host "BGM FILTER  : $bgmFilter"
    $bgmArgs = @(
        "-y",
        "-stream_loop", "-1",
        "-i", $MusicPath,
        "-vn",
        "-af", $bgmFilter,
        "-ac", "2",
        "-ar", "48000",
        "-c:a", "pcm_s16le",
        $tempBgm
    )
    & ffmpeg @bgmArgs
    if ($LASTEXITCODE -ne 0) {
        throw "FFmpeg falló preparando BGM exacta. Código $LASTEXITCODE"
    }

    Write-Host "Mezclando voz + BGM..."
    $mixFilter = "[0:a][1:a]amix=inputs=2:duration=longest:dropout_transition=0,atrim=0:${durationStr},asetpts=N/SR/TB[mix]"
    Write-Host "MIX FILTER  : $mixFilter"
    $mixArgs = @(
        "-y",
        "-i", $tempVoice,
        "-i", $tempBgm,
        "-filter_complex", $mixFilter,
        "-map", "[mix]",
        "-ac", "2",
        "-ar", "48000",
        "-c:a", "pcm_s16le",
        $tempMix
    )
    & ffmpeg @mixArgs
    if ($LASTEXITCODE -ne 0) {
        throw "FFmpeg falló mezclando voz y BGM. Código $LASTEXITCODE"
    }

    Write-Host "Mux final con video original..."
    $muxArgs = @(
        "-y",
        "-i", $VideoPath,
        "-i", $tempMix,
        "-map", "0:v:0",
        "-map", "1:a:0",
        "-c:v", "copy",
        "-c:a", "aac",
        "-b:a", "192k",
        "-movflags", "+faststart",
        $tempOutput
    )
    & ffmpeg @muxArgs
    if ($LASTEXITCODE -ne 0) {
        throw "FFmpeg falló en el mux final. Código $LASTEXITCODE"
    }

    Move-Item -LiteralPath $tempOutput -Destination $OutputPath -Force

    if ($ReplaceOriginal) {
        $backupPath = $VideoPath + ".backup_before_music"
        if (-not (Test-Path -LiteralPath $backupPath)) {
            Copy-Item -LiteralPath $VideoPath -Destination $backupPath
        }
        Move-Item -LiteralPath $OutputPath -Destination $VideoPath -Force
        Write-Host ""
        Write-Host "OK: musica agregada y archivo original reemplazado."
        Write-Host "Backup original: $backupPath"
        Write-Host "Video final     : $VideoPath"
    }
    else {
        Write-Host ""
        Write-Host "OK: musica agregada."
        Write-Host "Video final: $OutputPath"
    }
}
finally {
    Remove-IfExists $tempVoice
    Remove-IfExists $tempBgm
    Remove-IfExists $tempMix
}
