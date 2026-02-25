param()

$ErrorActionPreference="Stop"

# --- Config ---
$repo = (Get-Location).Path
$f = ".\app\video_pipeline.py"
if (!(Test-Path $f)) { throw "Falta $f (corre esto en la raíz del repo)" }

# Backup
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
Copy-Item $f "$f.bak_reuse_patch_$ts" -Force
Write-Host "Backup: $f.bak_reuse_patch_$ts"

# Leer líneas
$lines = Get-Content $f

function Find-All([string[]]$arr, [string]$pattern) {
  $idxs = @()
  for ($i=0; $i -lt $arr.Count; $i++) { if ($arr[$i] -match $pattern) { $idxs += $i } }
  return $idxs
}
function Find-First([string[]]$arr, [string]$pattern, [int]$start=0) {
  for ($i=$start; $i -lt $arr.Count; $i++) { if ($arr[$i] -match $pattern) { return $i } }
  return -1
}

# =========================
# A) PATCH AUDIO: REUSE + guard text
# =========================
# Encuentra la línea exacta de text = str(s.get("voiceover")...) dentro del loop de audio
$patText = '^\s*text\s*=\s*str\(s\.get\("voiceover"\)\s*or\s*""\)\.strip\(\)\s*or\s*" "\s*$'
$matches = Find-All $lines $patText
if ($matches.Count -ne 1) {
  throw "Esperaba 1 match de la línea text=voiceover. Encontré: $($matches.Count). (No parcheo por seguridad)"
}
$idxText = $matches[0]
$indent = ($lines[$idxText] -replace '(^\s*).*$','$1')

# Evita duplicar si ya existe REUSE en audio
$hasReuseAudio = ($lines | Select-String -Pattern 'reused existing render/audio' -Quiet)

if (-not $hasReuseAudio) {
  $reuseBlock = @(
    $indent + '# REUSE audio: si ya existe, no llamar TTS'
    $indent + 'existing = None'
    $indent + 'for ext in (".wav",".mp3",".m4a",".aac",".flac",".ogg"):'
    $indent + '    cand = os.path.join(dirs["audio_dir"], f"{s[""scene_id""]}{ext}")'
    $indent + '    if os.path.exists(cand):'
    $indent + '        existing = cand'
    $indent + '        break'
    $indent + 'if existing:'
    $indent + '    audio_paths.append(existing)'
    $indent + '    audio_meta.append({"provider":"REUSE_RENDER","model":"","mode":"REUSE","cache_hit":True,"cache_key":"","note":"reused existing render/audio"})'
    $indent + '    continue'
    ''
  )

  # Inserta el bloque antes de la línea text=...
  $lines = @(
    $lines[0..($idxText-1)] +
    $reuseBlock +
    $lines[$idxText..($lines.Count-1)]
  )

  # Recalcula idxText (creció el archivo)
  $idxText = $idxText + $reuseBlock.Count
  Write-Host "OK: insertado REUSE audio antes de text="
} else {
  Write-Host "OK: REUSE audio ya existe (skip insert)"
}

# Reemplaza la línea text=... por una versión robusta + guard
$lines[$idxText] = $indent + 'text = str(s.get("voiceover") or s.get("text") or s.get("narration") or "").strip()'
# Inserta guard justo después
$guard = @(
  $indent + 'if not text:'
  $indent + '    raise ValueError("voiceover vacío en scene_id=%s clip_id=%s" % (s.get("scene_id"), s.get("clip_id")))'
)
$lines = @(
  $lines[0..$idxText] +
  $guard +
  $lines[($idxText+1)..($lines.Count-1)]
)
Write-Host "OK: text robusto + guard (no más 'text vacío')"

# =========================
# B) PATCH IMAGES: REUSE (si existe out_path)
# =========================
# Solo si encontramos img.generate( y NO existe reused existing render/image
$hasReuseImg = ($lines | Select-String -Pattern 'reused existing render/image' -Quiet)
$idxImgGen = Find-First $lines 'img\.generate\(' 0

if ($idxImgGen -ge 0 -and (-not $hasReuseImg)) {
  # intentamos encontrar out_path = os.path.join(... f"{s['scene_id']}.png") antes del img.generate
  $idxOut = -1
  for ($k=$idxImgGen; $k -ge 0; $k--) {
    if ($lines[$k] -match '^\s*out_path\s*=\s*os\.path\.join\(dirs\["images_dir"\],\s*f"\{s\[''scene_id''\]\}\.png"\)') { $idxOut = $k; break }
    if ($lines[$k] -match '^\s*out_path\s*=\s*os\.path\.join\(dirs\["images_dir"\],\s*f"\{s\[""scene_id""\]\}\.png"\)') { $idxOut = $k; break }
  }

  if ($idxOut -ge 0) {
    $ind2 = ($lines[$idxOut] -replace '(^\s*).*$','$1')
    # Si ya hay if os.path.exists(out_path) justo después, no metemos nada
    $alreadyExistsCheck = $false
    for ($z=$idxOut+1; $z -le [Math]::Min($idxOut+6, $lines.Count-1); $z++) {
      if ($lines[$z] -match '^\s*if\s+os\.path\.exists\(out_path\):') { $alreadyExistsCheck = $true; break }
    }
    if (-not $alreadyExistsCheck) {
      $imgReuse = @(
        $ind2 + 'if os.path.exists(out_path):'
        $ind2 + '    img_paths.append(out_path)'
        $ind2 + '    img_meta.append({"provider":"REUSE_RENDER","model":"","mode":"REUSE","cache_hit":True,"cache_key":"","note":"reused existing render/image"})'
        $ind2 + '    continue'
      )
      $lines = @(
        $lines[0..$idxOut] +
        $imgReuse +
        $lines[($idxOut+1)..($lines.Count-1)]
      )
      Write-Host "OK: insertado REUSE imágenes después de out_path="
    } else {
      Write-Host "OK: imágenes ya tenían exists(out_path) (skip)"
    }
  } else {
    Write-Host "WARN: no encontré out_path antes de img.generate; no parcheo imágenes por seguridad"
  }
} else {
  if ($idxImgGen -lt 0) { Write-Host "OK: no encontré img.generate( (skip imágenes)" }
  else { Write-Host "OK: REUSE imágenes ya existe (skip)" }
}

# =========================
# C) Escribir UTF-8 sin BOM + compilar
# =========================
$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Resolve-Path $f).Path, ($lines -join "`n"), $enc)
Write-Host "OK: escrito $f (UTF-8 sin BOM)"

python -c "import py_compile; py_compile.compile(r'app/video_pipeline.py', doraise=True); print('PASS: video_pipeline.py compila')"
if ($LASTEXITCODE -ne 0) { throw "py_compile falló" }

python -m compileall .\app -q
if ($LASTEXITCODE -ne 0) { throw "compileall falló" }

Write-Host "DONE: patch reuse + guard aplicado"
