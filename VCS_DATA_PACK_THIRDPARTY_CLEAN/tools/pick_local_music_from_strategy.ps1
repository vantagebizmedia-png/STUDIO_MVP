param(
    [Parameter(Mandatory = $true)]
    [string]$PackDir,

    [string]$MusicDir = ".\music",

    [string]$OutputJson = "",

    [switch]$CopyIntoPack
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Normalize-Text {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }

    $t = $Text.ToLowerInvariant()
    $map = @{
        "á"="a"; "é"="e"; "í"="i"; "ó"="o"; "ú"="u"; "ü"="u"; "ñ"="n"
    }

    foreach ($k in $map.Keys) {
        $t = $t.Replace($k, $map[$k])
    }

    $t = [regex]::Replace($t, "[^a-z0-9]+", " ")
    $t = [regex]::Replace($t, "\s+", " ").Trim()
    return $t
}

function Get-Tokens {
    param([string]$Text)

    $n = Normalize-Text $Text
    if ([string]::IsNullOrWhiteSpace($n)) { return @() }
    return @($n.Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries))
}

function Get-EnergyHints {
    param([string]$Energy)

    switch ((Normalize-Text $Energy)) {
        "low"         { return @("calm","soft","ambient","relax","meditation","slow","peaceful","piano") }
        "medium"      { return @("background","corporate","clean","light","minimal","soft") }
        "medium high" { return @("motivational","upbeat","positive","inspire","drive","corporate") }
        "mediumhigh"  { return @("motivational","upbeat","positive","inspire","drive","corporate") }
        "high"        { return @("epic","trailer","cinematic","intense","power","action","energetic") }
        default       { return @("background","ambient","corporate") }
    }
}

function Read-Strategy {
    param([string]$PackDir)

    $jsonPath = Join-Path $PackDir "music_strategy.json"
    if (Test-Path -LiteralPath $jsonPath) {
        $obj = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
        return [pscustomobject]@{
            music_query            = [string]$obj.music_query
            music_energy           = [string]$obj.music_energy
            music_source_mode      = [string]$obj.music_source_mode
            music_provider_override= [string]$obj.music_provider_override
            music_strategy_reason  = [string]$obj.music_strategy_reason
            source_file            = $jsonPath
        }
    }

    $promptPath = Join-Path $PackDir "music_prompt.txt"
    if (-not (Test-Path -LiteralPath $promptPath)) {
        throw "No existe music_strategy.json ni music_prompt.txt en: $PackDir"
    }

    $lines = Get-Content -LiteralPath $promptPath
    $idx = -1

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq "[AUTO_MUSIC_STRATEGY]") {
            $idx = $i
            break
        }
    }

    if ($idx -lt 0) {
        throw "No encontré [AUTO_MUSIC_STRATEGY] en music_prompt.txt"
    }

    $kv = @{}
    for ($j = $idx + 1; $j -lt $lines.Count; $j++) {
        $line = $lines[$j].Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -notmatch "=") { continue }

        $parts = $line.Split("=", 2)
        $kv[$parts[0].Trim()] = $parts[1].Trim()
    }

    return [pscustomobject]@{
        music_query             = [string]$kv["music_query"]
        music_energy            = [string]$kv["energy"]
        music_source_mode       = [string]$kv["source_mode"]
        music_provider_override = [string]$kv["provider_override"]
        music_strategy_reason   = [string]$kv["reason"]
        source_file             = $promptPath
    }
}

$PackDir = (Resolve-Path -LiteralPath $PackDir).Path
$MusicDir = (Resolve-Path -LiteralPath $MusicDir).Path

if ([string]::IsNullOrWhiteSpace($OutputJson)) {
    $OutputJson = Join-Path $PackDir "music_selection.json"
}

$strategy = Read-Strategy -PackDir $PackDir

$files = @(
    Get-ChildItem -LiteralPath $MusicDir -File |
        Where-Object {
            $_.Extension.ToLowerInvariant() -in @(".mp3", ".wav", ".m4a", ".aac") -and
            -not $_.Name.StartsWith("_")
        } |
        Sort-Object Name
)

if ($files.Count -eq 0) {
    throw "No encontré música local en: $MusicDir"
}

$queryTokens = @(Get-Tokens $strategy.music_query | Where-Object { $_.Length -ge 3 })
$energyHints = @(Get-EnergyHints $strategy.music_energy)

$scored = foreach ($f in $files) {
    $base = Normalize-Text $f.BaseName
    $score = 0
    $matched = New-Object System.Collections.Generic.List[string]

    foreach ($t in $queryTokens) {
        if ($base -like "*$t*") {
            $score += 4
            $matched.Add("q:$t")
        }
    }

    foreach ($e in $energyHints) {
        if ($base -like "*$e*") {
            $score += 6
            $matched.Add("e:$e")
        }
    }

    if ($base -like "*music*")      { $score += 1; $matched.Add("generic:music") }
    if ($base -like "*background*") { $score += 2; $matched.Add("generic:background") }
    if ($base -like "*bg*")         { $score += 1; $matched.Add("generic:bg") }

    [pscustomobject]@{
        Path    = $f.FullName
        Name    = $f.Name
        Score   = $score
        Matched = @($matched)
    }
}

$best = $scored |
    Sort-Object @{Expression="Score";Descending=$true}, @{Expression="Name";Descending=$false} |
    Select-Object -First 1

if (-not $best) {
    throw "No se pudo seleccionar música"
}

$copiedPath = ""
if ($CopyIntoPack) {
    $artifactsDir = Join-Path $PackDir "artifacts"
    New-Item -ItemType Directory -Force -Path $artifactsDir | Out-Null

    $ext = [IO.Path]::GetExtension($best.Path)
    $copiedPath = Join-Path $artifactsDir ("music_auto" + $ext)
    Copy-Item -LiteralPath $best.Path -Destination $copiedPath -Force
}

$result = [ordered]@{
    schema = "STUDIO_MUSIC_SELECTION_V1"
    strategy = [ordered]@{
        music_query             = $strategy.music_query
        music_energy            = $strategy.music_energy
        music_source_mode       = $strategy.music_source_mode
        music_provider_override = $strategy.music_provider_override
        music_strategy_reason   = $strategy.music_strategy_reason
        source_file             = $strategy.source_file
    }
    selected = [ordered]@{
        original_path    = $best.Path
        copied_into_pack = $copiedPath
        score            = $best.Score
        matched          = @($best.Matched)
    }
}

$result | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 $OutputJson

Write-Host ""
Write-Host "=== AUTO MUSIC SELECTION ==="
Write-Host "PACK             :" $PackDir
Write-Host "MUSIC_DIR        :" $MusicDir
Write-Host "QUERY            :" $strategy.music_query
Write-Host "ENERGY           :" $strategy.music_energy
Write-Host "SELECTED         :" $best.Path
Write-Host "COPIED_INTO_PACK :" $copiedPath
Write-Host "SCORE            :" $best.Score
Write-Host "OUTPUT_JSON      :" $OutputJson
Write-Host "MATCHED          :" ($best.Matched -join ", ")

