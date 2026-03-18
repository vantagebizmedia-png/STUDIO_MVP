param(
  [Parameter(Mandatory=$false)][string]$RepoRoot = "C:\Users\vanta\Documents\STUDIO_MVP",
  [Parameter(Mandatory=$false)][string]$WorkspaceRoot = "C:\Users\vanta\Documents\STUDIO_WORKSPACE",
  [Parameter(Mandatory=$false)][string]$OutputRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null

function Fail([string]$msg) {
  throw "SMOKE FAIL: $msg"
}

if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) {
  Fail "No existe RepoRoot: $RepoRoot"
}

if (-not (Test-Path -LiteralPath $WorkspaceRoot -PathType Container)) {
  Fail "No existe WorkspaceRoot: $WorkspaceRoot"
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $OutputRoot = Join-Path $WorkspaceRoot "runs\smoke_pipeline_single_scene_voice_fallback_duration"
}

if (Test-Path -LiteralPath $OutputRoot) {
  Remove-Item -LiteralPath $OutputRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

$helperPath = Join-Path $OutputRoot "_smoke_pipeline_single_scene_voice_fallback_duration_helper.py"

$helperLines = @(
  "from __future__ import annotations",
  "",
  "import argparse",
  "import base64",
  "import json",
  "import shutil",
  "import sys",
  "import wave",
  "from pathlib import Path",
  "",
  "PNG_1X1 = base64.b64decode(",
  '    b"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+X2dAAAAAASUVORK5CYII="',
  ")" ,
  "",
  "def write_png(path: Path) -> None:",
  "    path.parent.mkdir(parents=True, exist_ok=True)",
  "    path.write_bytes(PNG_1X1)",
  "",
  "def wav_duration_ms(path: Path) -> int:",
  "    with wave.open(str(path), ""rb"") as wf:",
  "        return int((wf.getnframes() / float(wf.getframerate())) * 1000)",
  "",
  "class FakeImageProvider:",
  "    _provider_name = ""fake_image""",
  "",
  "    def generate(self, prompt: str, out_path: str) -> str:",
  "        write_png(Path(out_path))",
  "        return out_path",
  "",
  "class FailingVoiceProvider:",
  "    _provider_name = ""failing_voice""",
  "",
  "    def synthesize(self, text: str, out_path: str) -> str:",
  "        raise RuntimeError(""intentional voice failure for single-scene smoke"")",
  "",
  "def run_case(repo_root: Path, out_dir: Path, prompt_text: str) -> dict:",
  "    if out_dir.exists():",
  "        shutil.rmtree(out_dir)",
  "    out_dir.mkdir(parents=True, exist_ok=True)",
  "",
  "    sys.path.insert(0, str(repo_root))",
  "",
  "    from studio.pipeline import StudioPipeline",
  "",
  "    pipeline = StudioPipeline(",
  "        voice=FailingVoiceProvider(),",
  "        image=FakeImageProvider(),",
  "        text=None,",
  "        work_dir=str(out_dir),",
  "        multiscene=False,",
  "        max_scenes=1,",
  "        scene_split=""auto"",",
  "    )",
  "",
  "    img_path, aud_path = pipeline.run(prompt_text)",
  "",
  "    manifest_path = out_dir / ""manifest_v03.json""",
  "    if not manifest_path.exists():",
  "        raise RuntimeError(f""manifest no generado: {manifest_path}"")",
  "",
  "    manifest = json.loads(manifest_path.read_text(encoding=""utf-8""))",
  "    scenes = list(manifest.get(""scenes_v03"") or [])",
  "    if len(scenes) != 1:",
  "        raise RuntimeError(f""se esperaba scenes_v03=1 y llegó {len(scenes)}"")",
  "",
  "    scene1 = scenes[0]",
  "    scene_builder = manifest.get(""scene_builder_v03"") or {}",
  "    audio_file = Path(aud_path)",
  "    if not audio_file.exists():",
  "        raise RuntimeError(f""no existe audio fallback: {audio_file}"")",
  "",
  "    return {",
  "        ""work_dir"": str(out_dir),",
  "        ""audio_path"": str(audio_file),",
  "        ""audio_ms"": int(wav_duration_ms(audio_file)),",
  "        ""manifest_audio_duration_ms"": int(manifest.get(""audio_duration_ms"") or 0),",
  "        ""manifest_sb_total_audio_ms"": int(scene_builder.get(""total_audio_ms"") or 0),",
  "        ""scene_duration_ms"": int(scene1.get(""duration_ms"") or 0),",
  "        ""scene_start_ms"": int(scene1.get(""start_ms"") or 0),",
  "        ""scene_end_ms"": int(scene1.get(""end_ms"") or 0),",
  "    }",
  "",
  "def main() -> None:",
  "    ap = argparse.ArgumentParser()",
  "    ap.add_argument(""--repo-root"", required=True)",
  "    ap.add_argument(""--output-root"", required=True)",
  "    args = ap.parse_args()",
  "",
  "    repo_root = Path(args.repo_root).resolve()",
  "    output_root = Path(args.output_root).resolve()",
  "",
  "    short_text = ""Hola mundo.""",
  "    long_text = (",
  '        "Este es un texto single scene claramente mas largo para verificar que "',
  '        "el fallback de voz derive su duracion desde el texto real en el camino "',
  '        "normal del pipeline y no dependa de una duracion fija de plantilla."',
  "    )",
  "",
  "    payload = {",
  "        ""short_case"": run_case(repo_root, output_root / ""short_case"", short_text),",
  "        ""long_case"": run_case(repo_root, output_root / ""long_case"", long_text),",
  "    }",
  "",
  "    print(json.dumps(payload, ensure_ascii=False))",
  "",
  "if __name__ == ""__main__"":",
  "    main()"
)

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllLines($helperPath, $helperLines, $utf8NoBom)

Write-Host "== Ejecutando smoke helper ==" -ForegroundColor Cyan
$jsonText = & python -u $helperPath --repo-root $RepoRoot --output-root $OutputRoot
if ($LASTEXITCODE -ne 0) {
  throw "El helper Python devolvió exit code $LASTEXITCODE"
}

if ([string]::IsNullOrWhiteSpace($jsonText)) {
  Fail "El helper Python devolvió salida vacía"
}

$result = $jsonText | ConvertFrom-Json
$short = $result.short_case
$long  = $result.long_case

Write-Host ""
Write-Host "== RESULTADOS ==" -ForegroundColor Cyan
@(
  [pscustomobject]@{
    case                      = "short"
    audio_ms                  = [int]$short.audio_ms
    scene_duration_ms         = [int]$short.scene_duration_ms
    manifest_audio_duration_ms = [int]$short.manifest_audio_duration_ms
    manifest_sb_total_audio_ms = [int]$short.manifest_sb_total_audio_ms
    work_dir                  = [string]$short.work_dir
  }
  [pscustomobject]@{
    case                      = "long"
    audio_ms                  = [int]$long.audio_ms
    scene_duration_ms         = [int]$long.scene_duration_ms
    manifest_audio_duration_ms = [int]$long.manifest_audio_duration_ms
    manifest_sb_total_audio_ms = [int]$long.manifest_sb_total_audio_ms
    work_dir                  = [string]$long.work_dir
  }
) | Format-Table -AutoSize

$shortAudioMs   = [int]$short.audio_ms
$longAudioMs    = [int]$long.audio_ms
$shortSceneMs   = [int]$short.scene_duration_ms
$longSceneMs    = [int]$long.scene_duration_ms
$shortAudioMeta = [int]$short.manifest_audio_duration_ms
$longAudioMeta  = [int]$long.manifest_audio_duration_ms
$shortSbTotalMs = [int]$short.manifest_sb_total_audio_ms
$longSbTotalMs  = [int]$long.manifest_sb_total_audio_ms
$shortStartMs   = [int]$short.scene_start_ms
$longStartMs    = [int]$long.scene_start_ms
$shortEndMs     = [int]$short.scene_end_ms
$longEndMs      = [int]$long.scene_end_ms

if ($shortAudioMs -lt 1000) {
  Fail "short_case audio_ms demasiado bajo: $shortAudioMs"
}
if ($longAudioMs -le $shortAudioMs) {
  Fail "long_case audio_ms=$longAudioMs no supera short_case=$shortAudioMs"
}
if (($longAudioMs - $shortAudioMs) -lt 1200) {
  Fail "delta insuficiente en single-scene fallback: short=$shortAudioMs long=$longAudioMs"
}
if ($shortSceneMs -ne $shortAudioMs) {
  Fail "short_case scene_duration_ms=$shortSceneMs != audio_ms=$shortAudioMs"
}
if ($longSceneMs -ne $longAudioMs) {
  Fail "long_case scene_duration_ms=$longSceneMs != audio_ms=$longAudioMs"
}
if ($shortAudioMeta -ne $shortAudioMs) {
  Fail "short_case manifest_audio_duration_ms=$shortAudioMeta != audio_ms=$shortAudioMs"
}
if ($longAudioMeta -ne $longAudioMs) {
  Fail "long_case manifest_audio_duration_ms=$longAudioMeta != audio_ms=$longAudioMs"
}
if ($shortSbTotalMs -ne $shortAudioMs) {
  Fail "short_case scene_builder_v03.total_audio_ms=$shortSbTotalMs != audio_ms=$shortAudioMs"
}
if ($longSbTotalMs -ne $longAudioMs) {
  Fail "long_case scene_builder_v03.total_audio_ms=$longSbTotalMs != audio_ms=$longAudioMs"
}
if ($shortStartMs -ne 0) {
  Fail "short_case scene_start_ms inválido: $shortStartMs"
}
if ($longStartMs -ne 0) {
  Fail "long_case scene_start_ms inválido: $longStartMs"
}
if ($shortEndMs -ne $shortAudioMs) {
  Fail "short_case scene_end_ms=$shortEndMs != audio_ms=$shortAudioMs"
}
if ($longEndMs -ne $longAudioMs) {
  Fail "long_case scene_end_ms=$longEndMs != audio_ms=$longAudioMs"
}

Write-Host ""
Write-Host "SMOKE OK: pipeline single-scene voice fallback duration v03" -ForegroundColor Green
Write-Host ("SHORT_AUDIO_MS={0}" -f $shortAudioMs) -ForegroundColor DarkGray
Write-Host ("LONG_AUDIO_MS={0}" -f $longAudioMs) -ForegroundColor DarkGray
Write-Host ("DELTA_AUDIO_MS={0}" -f ($longAudioMs - $shortAudioMs)) -ForegroundColor DarkGray
Write-Host ("OUTPUT_ROOT={0}" -f $OutputRoot) -ForegroundColor DarkGray
