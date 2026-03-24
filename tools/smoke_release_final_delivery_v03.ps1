param(
    [string]$RepoRoot = "",
    [string]$WorkspaceRoot = "",
    [string]$PythonExe = "python"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-RequiredPath {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $resolved = Resolve-Path -LiteralPath $PathValue -ErrorAction Stop
    return $resolved.Path
}

function Get-MarkerValueFromText {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Marker
    )

    $pattern = '(?m)^{0}:\s*(.+?)\s*$' -f [regex]::Escape($Marker)
    $matches = [regex]::Matches($Text, $pattern)

    if ($matches.Count -le 0) {
        throw "No se encontro marcador requerido: $Marker"
    }

    return $matches[$matches.Count - 1].Groups[1].Value.Trim()
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}

$RepoRoot = Resolve-RequiredPath -PathValue $RepoRoot -Label "RepoRoot"

if (-not [string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = Resolve-RequiredPath -PathValue $WorkspaceRoot -Label "WorkspaceRoot"
}

Push-Location $RepoRoot
try {
    $releaseFinal = Resolve-RequiredPath -PathValue (Join-Path $RepoRoot "tools\release_final_delivery_v03.py") -Label "release_final_delivery_v03.py"
    $configPath   = Resolve-RequiredPath -PathValue (Join-Path $RepoRoot "config\studio_v03_text_smoke.json") -Label "studio_v03_text_smoke.json"
    $musicDir     = Resolve-RequiredPath -PathValue (Join-Path $RepoRoot "music") -Label "music"

    Write-Host "== PY_COMPILE ==" -ForegroundColor Cyan
    & $PythonExe -m py_compile $releaseFinal
    if ($LASTEXITCODE -ne 0) {
        throw "py_compile fallo para $releaseFinal con exit code $LASTEXITCODE"
    }

    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $scriptText = "Smoke release final delivery v03 $stamp"
    $logPath = Join-Path $env:TEMP ("smoke_release_final_delivery_v03_{0}.log" -f $stamp)

    Write-Host ""
    Write-Host "== RUN RELEASE FINAL DELIVERY ==" -ForegroundColor Cyan

    $rawOutput = & $PythonExe $releaseFinal `
        --v03-config $configPath `
        --script $scriptText `
        --overwrite `
        --auto-music `
        --music-dir $musicDir 2>&1

    $exitCode = $LASTEXITCODE

    $rawOutput | Out-File -LiteralPath $logPath -Encoding utf8

    $text = Get-Content -LiteralPath $logPath -Raw
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw "La salida capturada del smoke quedo vacia: $logPath"
    }

    $lines = @($text -split "\r?\n")
    if ($lines.Count -gt 0) {
        $lines | ForEach-Object {
            if ($_ -ne "") {
                Write-Host $_
            }
        }
    }

    if ($exitCode -ne 0) {
        throw "release_final_delivery_v03.py fallo con exit code $exitCode"
    }

    $manifest     = Get-MarkerValueFromText -Text $text -Marker "MANIFEST"
    $packDir      = Get-MarkerValueFromText -Text $text -Marker "PACK_DIR"
    $deliveryZip  = Get-MarkerValueFromText -Text $text -Marker "DELIVERY_ZIP"
    $deliverySha  = Get-MarkerValueFromText -Text $text -Marker "DELIVERY_ZIP_SHA256"
    $handoffReady = Get-MarkerValueFromText -Text $text -Marker "HANDOFF_READY"

    $manifest     = Resolve-RequiredPath -PathValue $manifest -Label "MANIFEST"
    $packDir      = Resolve-RequiredPath -PathValue $packDir -Label "PACK_DIR"
    $deliveryZip  = Resolve-RequiredPath -PathValue $deliveryZip -Label "DELIVERY_ZIP"
    $deliverySha  = Resolve-RequiredPath -PathValue $deliverySha -Label "DELIVERY_ZIP_SHA256"
    $handoffReady = Resolve-RequiredPath -PathValue $handoffReady -Label "HANDOFF_READY"

    $videoPath       = Join-Path $packDir "video.mp4"
    $videoMusicPath  = Join-Path $packDir "video_music_auto.mp4"
    $videoFinalPath  = Join-Path $packDir "video_final.mp4"
    $packJsonPath    = Join-Path $packDir "pack.json"

    $videoPath      = Resolve-RequiredPath -PathValue $videoPath -Label "video.mp4"
    $videoMusicPath = Resolve-RequiredPath -PathValue $videoMusicPath -Label "video_music_auto.mp4"
    $videoFinalPath = Resolve-RequiredPath -PathValue $videoFinalPath -Label "video_final.mp4"
    $packJsonPath   = Resolve-RequiredPath -PathValue $packJsonPath -Label "pack.json"

    foreach ($f in @($deliveryZip, $deliverySha, $handoffReady, $videoPath, $videoMusicPath, $videoFinalPath, $packJsonPath, $manifest)) {
        $item = Get-Item -LiteralPath $f -ErrorAction Stop
        if ($item.PSIsContainer) {
            continue
        }
        if ($item.Length -le 0) {
            throw "Archivo vacio no permitido: $f"
        }
    }

    if (-not [regex]::IsMatch($text, '(?m)^OK: final delivery completo\s*$')) {
        throw "No aparecio la confirmacion final esperada: OK: final delivery completo"
    }

    Write-Host ""
    Write-Host "=== SMOKE RELEASE FINAL DELIVERY V03 ===" -ForegroundColor Green
    Write-Host "RESULT              : PASS"
    Write-Host "MANIFEST            :" $manifest
    Write-Host "PACK_DIR            :" $packDir
    Write-Host "PACK_JSON           :" $packJsonPath
    Write-Host "VIDEO               :" $videoPath
    Write-Host "VIDEO_MUSIC_AUTO    :" $videoMusicPath
    Write-Host "VIDEO_FINAL         :" $videoFinalPath
    Write-Host "DELIVERY_ZIP        :" $deliveryZip
    Write-Host "DELIVERY_ZIP_SHA256 :" $deliverySha
    Write-Host "HANDOFF_READY       :" $handoffReady
    Write-Host "OUTPUT_LOG          :" $logPath
}
finally {
    Pop-Location
}