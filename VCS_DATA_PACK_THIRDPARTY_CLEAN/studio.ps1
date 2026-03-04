param(
  [ValidateSet("help","doctor","new","publish","social","prune","index","ws_report","runs_gc","archive_gc","cache_gc","cache_cap","run_slim","tidy")]
  [string]$Cmd = "help",

  # new/publish basics
  [string]$Prompt = "",
  [string]$RunId = "latest",
  [string]$PackDir = "",

  # render knobs
  [int]$Seed = 123,
  [int]$MaxScenes = 6,
  [ValidateSet("crop","letterbox")]
  [string]$Fit = "crop",

  # music
  [ValidateSet("off","fixed","random","topic","menu")]
  [string]$MusicMode = "off",
  [string]$Music = "music/bg.mp3",
  [double]$MusicVolume = 0.20,
  [double]$Ducking = 0.55,
  [ValidateSet("fixed","dynamic")]
  [string]$DuckingMode = "dynamic",

  # motion/fx
  [ValidateSet("none","slow_zoom_in","slow_zoom_out","pan_left","pan_right","pan_up","pan_down")]
  [string]$Motion = "slow_zoom_in",
  [double]$MotionStrength = 0.12,
  [double]$JitterPx = 0.0,
  [double]$JitterHz = 0.9,
  [double]$GrainAmount = 0.02,
  [double]$Vignette = 0.10,

  # master encoding (run.py)
  [int]$MasterCrf = 20,
  [ValidateSet("ultrafast","superfast","veryfast","faster","fast","medium","slow","slower","veryslow")]
  [string]$MasterPreset = "medium",
  [string]$PixFmt = "yuv420p",
  [switch]$FastStart,

  # PRO post-processing
  [switch]$Pro,
  [string]$ProFont = "Arial",
  [int]$ProFontSize = 64,

  # social encode
  [int]$SocialCrf = 28,
  [ValidateSet("ultrafast","superfast","veryfast","faster","fast","medium","slow","slower","veryslow")]
  [string]$SocialPreset = "veryfast",
  [int]$SocialAudioKbps = 128,

  # hygiene
  [ValidateSet("safe","aggressive")]
  [string]$PruneMode = "aggressive",
  [switch]$ArchiveRunRender,
  [switch]$SlimRun,

  # GC knobs
  [int]$KeepLast = 30,
  [int]$MaxAgeDays = 0,
  [int]$CacheMaxMB = 300,
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

# UTF-8 friendly console
chcp 65001 | Out-Null
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$env:PYTHONUTF8="1"
$env:PYTHONIOENCODING="utf-8"

$Repo  = (Resolve-Path ".").Path
$Tools = Join-Path $Repo "tools"

function Run-Step([string]$label, [scriptblock]$action) {
  Write-Host ("== {0} ==" -f $label) -ForegroundColor Cyan
  $global:LASTEXITCODE = 0
  & $action
  if ($LASTEXITCODE -ne 0) { throw ("Paso '{0}' fallo (exit={1})" -f $label, $LASTEXITCODE) }
}

function Show-Help {
  $msg = @(
    "STUDIO_MVP entrypoint (stable v4)",
    "",
    "Requiere: STUDIO_WORKSPACE (ruta absoluta, fuera del repo)",
    "",
    "Uso recomendado:",
    "  .\studio.ps1 doctor",
    "  .\studio.ps1 new     -Prompt ""disciplina diaria"" -Seed 123 -MaxScenes 6 -Fit crop -MusicMode off",
    "  .\studio.ps1 publish -RunId latest -Pro -PruneMode aggressive -ArchiveRunRender -SlimRun",
    "",
    "Limpieza (third-party ready):",
    "  .\studio.ps1 tidy -KeepLast 30 -CacheMaxMB 300",
    "",
    "Otros:",
    "  .\studio.ps1 index",
    "  .\studio.ps1 ws_report",
    "  .\studio.ps1 runs_gc    -KeepLast 30 -DryRun",
    "  .\studio.ps1 archive_gc -KeepLast 3  -DryRun",
    "  .\studio.ps1 cache_cap  -CacheMaxMB 300",
    "  .\studio.ps1 run_slim   -RunId latest"
  ) -join "`r`n"
  Write-Host $msg
}

function Ensure-Workspace {
  $ws = $env:STUDIO_WORKSPACE
  if (-not $ws) { throw "STUDIO_WORKSPACE no esta seteado. Corre: .\studio.ps1 doctor" }
  if (-not [IO.Path]::IsPathRooted($ws)) { throw "STUDIO_WORKSPACE debe ser absoluto: $ws" }
  New-Item -ItemType Directory -Force (Join-Path $ws "runs")   | Out-Null
  New-Item -ItemType Directory -Force (Join-Path $ws "output") | Out-Null
  New-Item -ItemType Directory -Force (Join-Path $ws "cache")  | Out-Null
  return $ws
}

function Resolve-PackDir([string]$ws, [string]$runId, [string]$packDirIn) {
  if ($packDirIn) { return (Resolve-Path $packDirIn).Path }

  $runsDir = Join-Path $ws "runs"
  if (!(Test-Path -LiteralPath $runsDir)) { throw "No existe runs/: $runsDir" }

  if ($runId -eq "latest") {
    $dirs = Get-ChildItem -LiteralPath $runsDir -Directory -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending

    foreach ($d in $dirs) {
      $m = Join-Path $d.FullName "content_pack\manifest.json"
      if (Test-Path -LiteralPath $m) {
        return (Resolve-Path (Join-Path $d.FullName "content_pack")).Path
      }
    }
    throw "No hay runs con content_pack en $runsDir"
  } else {
    $p = Join-Path $runsDir $runId
    $cp = Join-Path $p "content_pack"
    if (!(Test-Path -LiteralPath (Join-Path $cp "manifest.json"))) { throw "No existe content_pack valido en: $cp" }
    return (Resolve-Path $cp).Path
  }
}

function Resolve-PromptArg([string]$pack) {
  $promptArg = "tema"
  try {
    $mPath = Join-Path $pack "manifest.json"
    if (Test-Path -LiteralPath $mPath) {
      $m = Get-Content -LiteralPath $mPath -Raw | ConvertFrom-Json
      if ($m.topic_summary -and $m.topic_summary.core_topic) { $promptArg = "$($m.topic_summary.core_topic)" }
      elseif ($m.prompt) { $promptArg = "$($m.prompt)" }
      elseif ($m.title)  { $promptArg = "$($m.title)" }
    }
  } catch { }
  if ([string]::IsNullOrWhiteSpace($promptArg)) { $promptArg = "tema" }
  return $promptArg
}

function Resolve-LatestRunSince([string]$ws, [datetime]$since) {
  $runsDir = Join-Path $ws "runs"
  if (!(Test-Path -LiteralPath $runsDir)) { return $null }

  $dirs = Get-ChildItem -LiteralPath $runsDir -Directory -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending

  foreach ($d in $dirs) {
    $rv = Join-Path $d.FullName "render\video_final.mp4"
    if (Test-Path -LiteralPath $rv) {
      if ($d.LastWriteTime -ge $since.AddSeconds(-5)) { return $d }
      return $d
    }
  }
  return $null
}

function Archive-RunRender([string]$ws, [System.IO.DirectoryInfo]$runDir) {
  $renderVid = Join-Path $runDir.FullName "render\video_final.mp4"
  if (!(Test-Path -LiteralPath $renderVid)) {
    Write-Host ("WARN: no existe render para archivar: {0}" -f $renderVid) -ForegroundColor Yellow
    return
  }

  $outDir = Join-Path $ws "output"
  $archRoot = Join-Path $outDir ("_archive\" + (Get-Date -Format "yyyyMMdd_HHmmss"))
  New-Item -ItemType Directory -Force $archRoot | Out-Null

  $dst = Join-Path $archRoot ("render_" + $runDir.Name + ".mp4")
  Move-Item -LiteralPath $renderVid -Destination $dst -Force
  Write-Host ("OK: archived run render -> {0}" -f $dst) -ForegroundColor Green
}

switch ($Cmd) {
  "help" { Show-Help; break }

  "doctor" {
    Run-Step "doctor" { pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Tools "doctor.ps1") }
    break
  }

  "new" {
    $ws = Ensure-Workspace
    if (-not $Prompt) { throw "Falta -Prompt" }

    $args = @("--seed","$Seed","--max_scenes","$MaxScenes","--fit",$Fit,"--music_mode",$MusicMode,"--ducking_mode",$DuckingMode)

    if ($MusicMode -ne "off") {
      if ($Music) { $args += @("--music",$Music) }
      $args += @("--music_volume","$MusicVolume","--ducking","$Ducking")
    }

    $args += @(
      "--motion",$Motion,
      "--motion_strength","$MotionStrength",
      "--jitter_px","$JitterPx",
      "--jitter_hz","$JitterHz",
      "--grain_amount","$GrainAmount",
      "--vignette","$Vignette",
      "--crf","$MasterCrf",
      "--x264_preset",$MasterPreset,
      "--pix_fmt",$PixFmt
    )

    if ($FastStart) { $args += "--faststart" }

    Run-Step "new" { python (Join-Path $Repo "run.py") $Prompt @args }
    break
  }

  "publish" {
    $ws = Ensure-Workspace
    $packIn = Resolve-PackDir $ws $RunId $PackDir

    # polish BEFORE render (narrativa + image prompts + captions.txt)
    $pol = Join-Path $Tools "polish_pack.py"
    if (Test-Path -LiteralPath $pol) {
      Run-Step "polish_pack(packIn)" { python $pol $packIn }
    }

    $promptArg = Resolve-PromptArg $packIn

    $t0 = Get-Date

    $args = @("--pack_dir",$packIn,"--seed","$Seed","--max_scenes","$MaxScenes","--fit",$Fit,"--music_mode",$MusicMode,"--ducking_mode",$DuckingMode)

    if ($MusicMode -ne "off") {
      if ($Music) { $args += @("--music",$Music) }
      $args += @("--music_volume","$MusicVolume","--ducking","$Ducking")
    }

    $args += @(
      "--motion",$Motion,
      "--motion_strength","$MotionStrength",
      "--jitter_px","$JitterPx",
      "--jitter_hz","$JitterHz",
      "--grain_amount","$GrainAmount",
      "--vignette","$Vignette",
      "--crf","$MasterCrf",
      "--x264_preset",$MasterPreset,
      "--pix_fmt",$PixFmt
    )

    if ($FastStart) { $args += "--faststart" }

    # render (NO "IGNORED")
    Run-Step "render(master)" { python (Join-Path $Repo "run.py") $promptArg @args }

    $outDir = Join-Path $ws "output"
    $master = Join-Path $outDir "video_final_latest.mp4"
    if (!(Test-Path -LiteralPath $master)) { throw "No encontre master: $master" }

    # resolve runDir real
    $runDir = Resolve-LatestRunSince $ws $t0
    if (-not $runDir) { throw "No pude resolver el run mas reciente con render\video_final.mp4" }

    $pack = Join-Path $runDir.FullName "content_pack"
    if (!(Test-Path -LiteralPath (Join-Path $pack "manifest.json"))) { $pack = $packIn }

    # polish on the real pack too (por si run.py copió pack)
    if (Test-Path -LiteralPath $pol) {
      Run-Step "polish_pack(packRun)" { python $pol $pack }
    }

    # captions (extra seguro)
    $cap = Join-Path $Tools "make_captions.py"
    if (Test-Path -LiteralPath $cap) {
      Run-Step "captions" { python $cap $pack }
    }

    # PRO post (burn subs + improve img/audio)
    $socialInput = $master
    if ($Pro) {
      $pp = Join-Path $Tools "post_pro.ps1"
      if (!(Test-Path -LiteralPath $pp)) { throw "No existe tools\post_pro.ps1" }

      $proOut = Join-Path $outDir "video_final_latest_PRO.mp4"
      Run-Step "post_pro(PRO)" {
        pwsh -NoProfile -ExecutionPolicy Bypass -File $pp `
          -PackDir $pack -InVideo $master -OutVideo $proOut `
          -Subs -Img -Audio -Font $ProFont -FontSize $ProFontSize `
          -Crf 20 -Preset medium
      }

      if (!(Test-Path -LiteralPath $proOut)) { throw "PostPro no genero: $proOut" }
      $socialInput = $proOut
    }

    # social encode (siempre desde PRO si existe)
    $social = Join-Path $Tools "social_encode.ps1"
    if (!(Test-Path -LiteralPath $social)) { throw "No existe: $social" }

    Run-Step "social" {
      pwsh -NoProfile -ExecutionPolicy Bypass -File $social `
        -Input $socialInput -Crf $SocialCrf -Preset $SocialPreset -AudioKbps $SocialAudioKbps
    }

    # prune outputs
    $prune = Join-Path $Tools "prune_outputs.ps1"
    if (!(Test-Path -LiteralPath $prune)) { throw "No existe: $prune" }
    Run-Step "prune" { pwsh -NoProfile -ExecutionPolicy Bypass -File $prune -Mode $PruneMode }

    # archive + slim (opcional)
    if ($ArchiveRunRender) { Archive-RunRender $ws $runDir }
    if ($SlimRun) {
      $sl = Join-Path $Tools "run_slim.ps1"
      if (Test-Path -LiteralPath $sl) { Run-Step "run_slim" { pwsh -NoProfile -ExecutionPolicy Bypass -File $sl -RunId $runDir.Name } }
    }

    Write-Host ("PUBLISH DONE -> {0}" -f (Join-Path $outDir "video_final_latest_social.mp4")) -ForegroundColor Green
    break
  }

  "social" {
    $ws = Ensure-Workspace
    $outDir = Join-Path $ws "output"
    $in = Join-Path $outDir "video_final_latest_PRO.mp4"
    if (!(Test-Path -LiteralPath $in)) { $in = Join-Path $outDir "video_final_latest.mp4" }

    $s = Join-Path $Tools "social_encode.ps1"
    if (!(Test-Path -LiteralPath $s)) { throw "No existe: $s" }

    Run-Step "social" { pwsh -NoProfile -ExecutionPolicy Bypass -File $s -Input $in -Crf $SocialCrf -Preset $SocialPreset -AudioKbps $SocialAudioKbps }
    break
  }

  "prune" {
    $ws = Ensure-Workspace
    $p = Join-Path $Tools "prune_outputs.ps1"
    if (!(Test-Path -LiteralPath $p)) { throw "No existe: $p" }
    Run-Step "prune" { pwsh -NoProfile -ExecutionPolicy Bypass -File $p -Mode $PruneMode }
    break
  }

  "index" {
    $ws = Ensure-Workspace
    $i = Join-Path $Tools "index_runs.ps1"
    if (!(Test-Path -LiteralPath $i)) { throw "No existe: $i" }
    Run-Step "index" { pwsh -NoProfile -ExecutionPolicy Bypass -File $i }
    break
  }

  "ws_report" {
    $ws = Ensure-Workspace
    $r = Join-Path $Tools "ws_report.ps1"
    if (!(Test-Path -LiteralPath $r)) { throw "No existe: $r" }
    Run-Step "ws_report" { pwsh -NoProfile -ExecutionPolicy Bypass -File $r }
    break
  }

  "runs_gc" {
    $ws = Ensure-Workspace
    $g = Join-Path $Tools "runs_gc.ps1"
    if (!(Test-Path -LiteralPath $g)) { throw "No existe: $g" }
    if ($DryRun) { Run-Step "runs_gc(dryrun)" { pwsh -NoProfile -ExecutionPolicy Bypass -File $g -KeepLast $KeepLast -MaxAgeDays $MaxAgeDays -DryRun } }
    else { Run-Step "runs_gc" { pwsh -NoProfile -ExecutionPolicy Bypass -File $g -KeepLast $KeepLast -MaxAgeDays $MaxAgeDays } }
    break
  }

  "archive_gc" {
    $ws = Ensure-Workspace
    $a = Join-Path $Tools "archive_gc.ps1"
    if (!(Test-Path -LiteralPath $a)) { throw "No existe: $a" }
    if ($DryRun) { Run-Step "archive_gc(dryrun)" { pwsh -NoProfile -ExecutionPolicy Bypass -File $a -KeepLast $KeepLast -MaxAgeDays $MaxAgeDays -DryRun } }
    else { Run-Step "archive_gc" { pwsh -NoProfile -ExecutionPolicy Bypass -File $a -KeepLast $KeepLast -MaxAgeDays $MaxAgeDays } }
    break
  }

  "cache_gc" {
    $ws = Ensure-Workspace
    $c = Join-Path $Tools "cache_gc.ps1"
    if (!(Test-Path -LiteralPath $c)) { throw "No existe: $c" }
    if ($DryRun) { Run-Step "cache_gc(dryrun)" { pwsh -NoProfile -ExecutionPolicy Bypass -File $c -MaxAgeDays $MaxAgeDays -DryRun } }
    else { Run-Step "cache_gc" { pwsh -NoProfile -ExecutionPolicy Bypass -File $c -MaxAgeDays $MaxAgeDays } }
    break
  }

  "cache_cap" {
    $ws = Ensure-Workspace
    $cc = Join-Path $Tools "cache_cap.ps1"
    if (!(Test-Path -LiteralPath $cc)) { throw "No existe: $cc" }
    if ($DryRun) { Run-Step "cache_cap(dryrun)" { pwsh -NoProfile -ExecutionPolicy Bypass -File $cc -MaxMB $CacheMaxMB -DryRun } }
    else { Run-Step "cache_cap" { pwsh -NoProfile -ExecutionPolicy Bypass -File $cc -MaxMB $CacheMaxMB } }
    break
  }

  "run_slim" {
    $ws = Ensure-Workspace
    $sl = Join-Path $Tools "run_slim.ps1"
    if (!(Test-Path -LiteralPath $sl)) { throw "No existe: $sl" }
    if ($DryRun) { Run-Step "run_slim(dryrun)" { pwsh -NoProfile -ExecutionPolicy Bypass -File $sl -RunId $RunId -DryRun } }
    else { Run-Step "run_slim" { pwsh -NoProfile -ExecutionPolicy Bypass -File $sl -RunId $RunId } }
    break
  }

  "tidy" {
    $ws = Ensure-Workspace
    # Tidy = third-party ready (controlado)
    Run-Step "archive_gc" { pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Tools "archive_gc.ps1") -KeepLast 3 -MaxAgeDays 0 }
    Run-Step "cache_cap"  { pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Tools "cache_cap.ps1") -MaxMB $CacheMaxMB }
    Run-Step "runs_gc"    { pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Tools "runs_gc.ps1") -KeepLast $KeepLast -MaxAgeDays $MaxAgeDays }
    break
  }
}