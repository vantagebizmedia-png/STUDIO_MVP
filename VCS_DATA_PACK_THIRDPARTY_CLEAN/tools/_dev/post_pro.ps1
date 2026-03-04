param(
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string] $PackDir,
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string] $InVideo,

  [string] $OutVideo = "",

  # Toggles
  [switch] $Subs,
  [switch] $Img,
  [switch] $Audio,

  # Voice denoise (FFmpeg). Si Denoise=ON, fuerza Audio=ON
  [switch] $Denoise,
  [string] $DenoiseFilter = "afftdn",
  [ValidateSet("light","medium","strong")] [string] $DenoiseLevel = "medium",
  [int]    $AudioRate = 48000,
  # Subs style
  [string] $Font = "Arial",
  [int]    $FontSize = 46,
  [int]    $MarginV  = 90,
  [int]    $Outline  = 2,
  [int]    $Shadow   = 0,

  # Encoding (si hay reencode)
  [int]    $Crf = 20,
  [ValidateSet("ultrafast","superfast","veryfast","faster","fast","medium","slow","slower","veryslow")]
  [string] $Preset = "medium"
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
chcp 65001 | Out-Null
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)

function Must-File([string]$p) { if (!(Test-Path $p -PathType Leaf)) { throw "FALTA archivo: $p" } }
function Must-Dir([string]$p)  { if (!(Test-Path $p -PathType Container)) { throw "FALTA directorio: $p" } }

# FFmpeg tools
if (-not (Get-Command ffmpeg  -ErrorAction SilentlyContinue))  { throw "No encuentro ffmpeg en PATH" }
if (-not (Get-Command ffprobe -ErrorAction SilentlyContinue))  { throw "No encuentro ffprobe en PATH" }

$Repo = Split-Path $PSScriptRoot -Parent

Must-Dir $PackDir
$PackDir = (Resolve-Path $PackDir).Path

Must-File $InVideo
$InVideo = (Resolve-Path $InVideo).Path

if (-not $OutVideo) {
  $dir = Split-Path $InVideo -Parent
  $base = [IO.Path]::GetFileNameWithoutExtension($InVideo)
  $OutVideo = Join-Path $dir ($base + "_PRO.mp4")
}
$OutVideo = (Resolve-Path (Split-Path $OutVideo -Parent) -ErrorAction SilentlyContinue).Path + "\" + (Split-Path $OutVideo -Leaf)
# OUTDIR_INIT_V1
$outDir = Split-Path $OutVideo -Parent
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

# Derivar RunDir y render_manifest
$runDir = Split-Path $PackDir -Parent
$renderManifest = Join-Path $runDir "render\render_manifest.json"

# Storyboard
$storyboardPath = Join-Path $PackDir "storyboard.json"
Must-File $storyboardPath

# Helper: duration via ffprobe
function Get-AudioDurSec([string]$p) {
  $out = & ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$p"
  if (-not $out) { return 0.0 }
  try { return [double]::Parse(($out | Select-Object -First 1), [Globalization.CultureInfo]::InvariantCulture) } catch { return 0.0 }
}

function Format-SrtTime([double]$sec) {
  if ($sec -lt 0) { $sec = 0 }
  $ts = [TimeSpan]::FromMilliseconds([Math]::Round($sec*1000.0))
  return "{0:00}:{1:00}:{2:00},{3:000}" -f $ts.Hours, $ts.Minutes, $ts.Seconds, $ts.Milliseconds
}

function Wrap-Text([string]$t, [int]$w=42) {
  $t = ($t -as [string]).Trim()
  if (-not $t) { return "" }
  $words = $t -split "\s+"
  $lines = New-Object System.Collections.Generic.List[string]
  $cur = ""
  foreach ($wd in $words) {
    if (($cur.Length + $wd.Length + 1) -le $w) {
      $cur = if ($cur) { "$cur $wd" } else { $wd }
    } else {
      if ($cur) { $lines.Add($cur) }
      $cur = $wd
    }
  }
  if ($cur) { $lines.Add($cur) }
  return ($lines -join "`n")
}

function Scene-Text($scene) {
  if ($null -eq $scene) { return "" }
  $keys = @("subtitle","sub","text","line","voiceover","narration","dialog","caption","on_screen_text","screen_text","vo","script")
  foreach ($k in $keys) {
    try {
      $v = $scene.$k
      if ($v -and ($v -as [string]).Trim()) { return ($v -as [string]).Trim() }
    } catch {}
  }
  return ""
}

# Obtener escenas
$sb = Get-Content $storyboardPath -Raw -Encoding utf8 | ConvertFrom-Json
$scenes = $null
if ($sb.PSObject.Properties.Name -contains "scenes") { $scenes = $sb.scenes }
elseif ($sb.PSObject.Properties.Name -contains "storyboard") { $scenes = $sb.storyboard }
elseif ($sb -is [System.Collections.IEnumerable]) { $scenes = $sb }
if (-not $scenes) { throw "No pude encontrar escenas en storyboard.json (busqué: scenes / storyboard / root list)" }
# CAPTION_FALLBACK_V2
# Lee captions.txt / caption.txt (1 línea = 1 escena) o script.txt (bloques) como fallback.
$captionLines = @()

$capCandidates = @("captions.txt","caption.txt")
foreach ($fn in $capCandidates) {
  $p = Join-Path $PackDir $fn
  if (Test-Path $p) {
    $lines = Get-Content $p -Encoding utf8 |
      ForEach-Object { ($_ -as [string]).Trim() } |
      Where-Object { $_ -and $_.Length -gt 0 }

    if ($lines.Count -gt 0) {
      $captionLines = @($lines)
      Write-Host ("INFO: usando {0} ({1} líneas)" -f $fn, $captionLines.Count) -ForegroundColor DarkGray
      break
    }
  }
}

if ($captionLines.Count -eq 0) {
  $sp = Join-Path $PackDir "script.txt"
  if (Test-Path $sp) {
    $raw = Get-Content $sp -Raw -Encoding utf8
    $parts = $raw -split "(\r?\n){2,}" |
      ForEach-Object { ($_ -as [string]).Trim() } |
      Where-Object { $_ -and $_.Length -gt 0 }

    if ($parts.Count -gt 0) {
      # Limpia headers tipo "clip_01 [hook]"
      $clean = @()
      foreach ($b in $parts) {
        $bb = ($b -replace '(?m)^\s*clip_\d+\s*\[[^\]]+\]\s*$', '').Trim()
        if ($bb) { $clean += $bb }
      }
      if ($clean.Count -gt 0) {
        $captionLines = @($clean)
        Write-Host ("INFO: usando script.txt ({0} bloques)" -f $captionLines.Count) -ForegroundColor DarkGray
      }
    }
  }
}

if ($captionLines.Count -gt 0) {
  $p0 = $captionLines[0]
  if ($p0.Length -gt 120) { $p0 = $p0.Substring(0,120) + "..." }
  Write-Host ("INFO: ejemplo caption[0] => " + $p0) -ForegroundColor DarkGray
}

# Obtener audios (manifest si existe, si no: buscar wav/mp3 en runDir\render)
$audioPaths = @()
if (Test-Path $renderManifest) {
  try {
    $rm = Get-Content $renderManifest -Raw -Encoding utf8 | ConvertFrom-Json
    foreach ($cand in @("audio_paths","audios","audioFiles")) {
      if ($rm.PSObject.Properties.Name -contains $cand) { $audioPaths = @($rm.$cand); break }
    }
    if (-not $audioPaths -and $rm.PSObject.Properties.Name -contains "outputs") {
      foreach ($cand in @("audio_paths","audios")) {
        if ($rm.outputs.PSObject.Properties.Name -contains $cand) { $audioPaths = @($rm.outputs.$cand); break }
      }
    }
  } catch {}
}

if (-not $audioPaths -or $audioPaths.Count -eq 0) {
  $renderDir = Join-Path $runDir "render"
  Must-Dir $renderDir
  $audioPaths = Get-ChildItem $renderDir -Recurse -File -Include *.wav,*.mp3,*.m4a -ErrorAction SilentlyContinue |
    Sort-Object Name | Select-Object -ExpandProperty FullName
}

if (-not $audioPaths -or $audioPaths.Count -eq 0) {
  throw "No encontré audios para calcular timings (ni en render_manifest ni en runDir\render)"
}

# Generar SRT solo si piden Subs
$srtLocal = $null
if ($Subs) {
  $outDir = Split-Path $OutVideo -Parent
  $srtLocal = Join-Path $outDir "subtitles_auto.srt"

  $n = [Math]::Min($audioPaths.Count, $scenes.Count)
  if ($n -le 0) { throw "No hay escenas/audios suficientes para SRT" }

  $t = 0.0
  $idx = 1
  $blocks = New-Object System.Collections.Generic.List[string]

  for ($i=0; $i -lt $n; $i++) {
    $ap = $audioPaths[$i]
    if (!(Test-Path $ap)) { continue }
    $dur = Get-AudioDurSec $ap
    if ($dur -le 0.02) { $dur = 0.5 }

    $txt = Scene-Text $scenes[$i]
    # CAPTION_PICK_V2
    if (-not $txt -and $captionLines -and $captionLines.Count -gt $i) {
      $txt = $captionLines[$i]
    }
    if (-not $txt) { $txt = " " } # evita bloque vacío

    $start = $t
    $end = $t + $dur
    $t = $end

    $block = @()
    $block += "$idx"
    $block += ("{0} --> {1}" -f (Format-SrtTime $start), (Format-SrtTime $end))
    $block += (Wrap-Text $txt 42)
    $block += ""
    $blocks.Add(($block -join "`r`n"))
    $idx++
  }

  [System.IO.File]::WriteAllText($srtLocal, ($blocks -join "`r`n"), [Text.UTF8Encoding]::new($false))
  Write-Host "OK: SRT generado -> $srtLocal" -ForegroundColor Green
}

# Construir filtros
$vfParts = @()
if ($Img) {
  # "Pro" sutil (no exagerado): contraste/sat + unsharp + denoise suave
  $vfParts += "eq=contrast=1.06:saturation=1.08:brightness=0.01"
  $vfParts += "unsharp=5:5:0.60:3:3:0.30"
  $vfParts += "hqdn3d=1.2:1.2:6:6"
}

if ($Subs) {
  # Trabajamos en el folder de salida para evitar escapes raros de Windows paths
  $force = "Fontname=$Font,Fontsize=$FontSize,Outline=$Outline,Shadow=$Shadow,MarginV=$MarginV"
  $vfParts += ("subtitles=subtitles_auto.srt:force_style='{0}'" -f $force)
}

$vf = ($vfParts -join ",")

$af = ""

# Si Denoise ON, fuerza Audio ON
if ($Denoise) { $Audio = $true }

if ($Audio) {
  # Master simple y seguro (determinista). Afecta al mix final (voz + música).
  $base = "highpass=f=80,lowpass=f=12000,acompressor=threshold=-18dB:ratio=3:attack=10:release=150,alimiter=limit=-1.0dB,loudnorm=I=-16:TP=-1.5:LRA=11"

  if ($Denoise) {
    $df = ($DenoiseFilter -as [string]).Trim()
    # DENOISE_LEVEL_V1
    # Si no pasaste -DenoiseFilter, usamos presets por nivel
    if (-not $PSBoundParameters.ContainsKey("DenoiseFilter")) {
      switch (($DenoiseLevel -as [string]).ToLowerInvariant()) {
        "light"  { $df = "afftdn=nr=8:nf=-55:tn=1:ad=0.45" }
        "strong" { $df = "afftdn=nr=18:nf=-58:tn=1:ad=0.55" }
        default  { $df = "afftdn=nr=12:nf=-55:tn=1:ad=0.50" } # medium
      }
    }
    if (-not $df) { $df = "afftdn" }
  # ARNNDN_MODEL_LOCAL_V1
  # Si usas arnndn con model=..., copiamos el modelo al outDir y reescribimos a path relativo (sin C:)
  if ($df -match '(?i)\barnndn\b' -and $df -match '(?i)\b(model|m)=') {
    $rx = [regex]::new("(?i)\b(model|m)=('([^']+)'|""([^""]+)""|([^,]+))")
    $mm = $rx.Match($df)
    if ($mm.Success) {
      $p = $mm.Groups[3].Value
      if (-not $p) { $p = $mm.Groups[4].Value }
      if (-not $p) { $p = $mm.Groups[5].Value }

      if ($p) {
        $p2 = $p

        # Si no existe tal cual, intenta relativo al repo
        if (!(Test-Path $p2 -PathType Leaf)) {
          $try = Join-Path $Repo $p
          if (Test-Path $try -PathType Leaf) { $p2 = $try }
        }

        if (Test-Path $p2 -PathType Leaf) {
          $local = Join-Path $outDir "rnnoise_model.rnnn"
          Copy-Item $p2 $local -Force
          $leaf = Split-Path $local -Leaf

          # Reemplaza SOLO el model=... por model='rnnoise_model.rnnn'
          $df = $rx.Replace($df, ("model='{0}'" -f $leaf), 1)
          Write-Host ("INFO: arnndn model copiado -> {0}" -f $local) -ForegroundColor DarkGray
        } else {
                    Write-Host ("WARN: arnndn model no existe: {0}" -f $p2) -ForegroundColor Yellow
          Write-Host "WARN: fallback a afftdn (para no fallar)" -ForegroundColor Yellow
          $df = "afftdn=nr=12:nf=-55:tn=1:ad=0.50"
        }
      }
    }
  }

    $af = ($df + "," + $base)
  } else {
    $af = $base
  }
}# Ejecutar FFmpeg (1 sola pasada)
Write-Host "" 
Write-Host "POST_PRO -> Subs=$Subs Img=$Img Audio=$Audio" -ForegroundColor Cyan
Write-Host "IN : $InVideo" -ForegroundColor DarkGray
Write-Host "OUT: $OutVideo" -ForegroundColor DarkGray

$outDir = Split-Path $OutVideo -Parent
Push-Location $outDir
try {
  $args = @("-nostdin","-y","-i",$InVideo)

  if ($vf) { $args += @("-vf",$vf) }

  # video codec
  if ($vf) {
    $args += @("-c:v","libx264","-crf",[string]$Crf,"-preset",$Preset,"-pix_fmt","yuv420p","-movflags","+faststart")
  } else {
    $args += @("-c:v","copy")
  }

  # audio codec
  if ($af) {
    if ($AudioRate -gt 0) { $args += @("-af",$af,"-c:a","aac","-b:a","192k","-ac","2","-ar",[string]$AudioRate) } else { $args += @("-af",$af,"-c:a","aac","-b:a","192k","-ac","2") }
  } else {
    $args += @("-c:a","copy")
  }

  $args += @($OutVideo)

  Write-Host ("RUN: ffmpeg " + ($args -join " ")) -ForegroundColor DarkGray
  & ffmpeg @args
  if ($LASTEXITCODE -ne 0) { throw "ffmpeg falló (exit=$LASTEXITCODE)" }

  Write-Host "OK: generado -> $OutVideo" -ForegroundColor Green
}
finally {
  Pop-Location
}