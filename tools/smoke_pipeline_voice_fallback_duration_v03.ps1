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

function Get-StringOrEmpty {
  param($Value)

  if ($null -eq $Value) { return "" }

  try { return ([string]$Value).Trim() }
  catch { return "" }
}

if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) {
  Fail "No existe RepoRoot: $RepoRoot"
}

if (-not (Test-Path -LiteralPath $WorkspaceRoot -PathType Container)) {
  Fail "No existe WorkspaceRoot: $WorkspaceRoot"
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $OutputRoot = Join-Path $WorkspaceRoot "runs\smoke_pipeline_voice_fallback_duration"
}

if (Test-Path -LiteralPath $OutputRoot) {
  Remove-Item -LiteralPath $OutputRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

$helperPath = Join-Path $OutputRoot "_smoke_pipeline_voice_fallback_duration_helper.py"

$helperText = @'
from __future__ import annotations

import argparse
import base64
import json
import shutil
import sys
import wave
from pathlib import Path

PNG_1X1 = base64.b64decode(
    b"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+X2dAAAAAASUVORK5CYII="
)


def write_png(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(PNG_1X1)


def wav_duration_ms(path: Path) -> int:
    with wave.open(str(path), "rb") as wf:
        return int((wf.getnframes() / float(wf.getframerate())) * 1000)


class FakeImageProvider:
    _provider_name = "fake_image"

    def generate(self, prompt: str, out_path: str) -> str:
        write_png(Path(out_path))
        return out_path


class FailingVoiceProvider:
    _provider_name = "failing_voice"

    def synthesize(self, text: str, out_path: str) -> str:
        raise RuntimeError("intentional voice failure for smoke")


class FixedScenesTextProvider:
    _provider_name = "fixed_text"

    def __init__(self, scene1_text: str) -> None:
        self.scene1_text = scene1_text
        self._provider_cfg = {"cache": False}

    def generate(self, prompt: str) -> str:
        return (
            "ESCENA 01\n"
            f"NARRACION: {self.scene1_text}\n"
            "ONSCREEN: escena principal de prueba\n"
            "STOCK_QUERY: persona hablando a camara\n"
            "---\n"
            "ESCENA 02\n"
            "NARRACION: cierre breve final\n"
            "ONSCREEN: escena de cierre\n"
            "STOCK_QUERY: persona cerrando laptop\n"
            "---\n"
        )


def run_case(repo_root: Path, out_dir: Path, scene1_text: str) -> dict:
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    sys.path.insert(0, str(repo_root))

    from studio.pipeline import StudioPipeline

    pipeline = StudioPipeline(
        voice=FailingVoiceProvider(),
        image=FakeImageProvider(),
        text=FixedScenesTextProvider(scene1_text),
        work_dir=str(out_dir),
        multiscene=True,
        max_scenes=2,
        scene_split="auto",
    )

    prompt = f"smoke pipeline voice fallback duration :: {len(scene1_text)}"
    first_img, first_aud = pipeline.run(prompt)

    manifest_path = out_dir / "manifest_v03.json"
    if not manifest_path.exists():
        raise RuntimeError(f"manifest no generado: {manifest_path}")

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    scenes = list(manifest.get("scenes_v03") or [])
    if len(scenes) < 1:
        raise RuntimeError("manifest.scenes_v03 vacío")

    scene1 = scenes[0]
    scene1_audio = out_dir / "artifacts" / "scenes" / "scene_01" / "audio.wav"
    if not scene1_audio.exists():
        raise RuntimeError(f"no existe audio fallback scene_01: {scene1_audio}")

    result = {
        "work_dir": str(out_dir),
        "first_img": str(first_img),
        "first_aud": str(first_aud),
        "scene1_audio": str(scene1_audio),
        "scene1_audio_ms": int(wav_duration_ms(scene1_audio)),
        "manifest_scene1_duration_ms": int(scene1.get("duration_ms") or 0),
        "manifest_scene1_start_ms": int(scene1.get("start_ms") or 0),
        "manifest_scene1_end_ms": int(scene1.get("end_ms") or 0),
        "manifest_total_audio_ms": int(manifest.get("total_audio_ms") or 0),
        "manifest_audio_duration_ms": int(manifest.get("audio_duration_ms") or 0),
        "scene_count": len(scenes),
    }
    return result


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo-root", required=True)
    ap.add_argument("--output-root", required=True)
    args = ap.parse_args()

    repo_root = Path(args.repo_root).resolve()
    output_root = Path(args.output_root).resolve()

    short_text = "Hola mundo."
    long_text = (
        "Este es un texto de prueba claramente mas largo para verificar que la duracion "
        "del audio fallback se derive del contenido real, mantenga una relacion razonable "
        "con la cantidad de palabras y no vuelva a quedar fija en un valor plantilla."
    )

    short_dir = output_root / "short_case"
    long_dir = output_root / "long_case"

    payload = {
        "short_case": run_case(repo_root, short_dir, short_text),
        "long_case": run_case(repo_root, long_dir, long_text),
    }

    print(json.dumps(payload, ensure_ascii=False))


if __name__ == "__main__":
    main()
'@

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($helperPath, $helperText, $utf8NoBom)

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
    case                        = "short"
    scene1_audio_ms             = [int]$short.scene1_audio_ms
    manifest_scene1_duration_ms = [int]$short.manifest_scene1_duration_ms
    manifest_total_audio_ms     = [int]$short.manifest_total_audio_ms
    scene_count                 = [int]$short.scene_count
    work_dir                    = [string]$short.work_dir
  }
  [pscustomobject]@{
    case                        = "long"
    scene1_audio_ms             = [int]$long.scene1_audio_ms
    manifest_scene1_duration_ms = [int]$long.manifest_scene1_duration_ms
    manifest_total_audio_ms     = [int]$long.manifest_total_audio_ms
    scene_count                 = [int]$long.scene_count
    work_dir                    = [string]$long.work_dir
  }
) | Format-Table -AutoSize

$shortAudioMs    = [int]$short.scene1_audio_ms
$longAudioMs     = [int]$long.scene1_audio_ms
$shortManifestMs = [int]$short.manifest_scene1_duration_ms
$longManifestMs  = [int]$long.manifest_scene1_duration_ms
$shortTotalMs    = [int]$short.manifest_total_audio_ms
$longTotalMs     = [int]$long.manifest_total_audio_ms

if ($shortAudioMs -lt 1000) {
  Fail "short_case scene1_audio_ms demasiado bajo: $shortAudioMs"
}
if ($longAudioMs -le $shortAudioMs) {
  Fail "long_case scene1_audio_ms=$longAudioMs no supera short_case=$shortAudioMs"
}
if (($longAudioMs - $shortAudioMs) -lt 1500) {
  Fail "delta de audio fallback insuficiente: short=$shortAudioMs long=$longAudioMs"
}

if ($shortManifestMs -lt 1000) {
  Fail "short_case manifest_scene1_duration_ms demasiado bajo: $shortManifestMs"
}
if ($longManifestMs -le $shortManifestMs) {
  Fail "long_case manifest_scene1_duration_ms=$longManifestMs no supera short_case=$shortManifestMs"
}

if ($longTotalMs -le $shortTotalMs) {
  Fail "manifest_total_audio_ms no escala: short=$shortTotalMs long=$longTotalMs"
}

Write-Host ""
Write-Host "SMOKE OK: pipeline voice fallback duration v03" -ForegroundColor Green
Write-Host ("SHORT_AUDIO_MS={0}" -f $shortAudioMs) -ForegroundColor DarkGray
Write-Host ("LONG_AUDIO_MS={0}" -f $longAudioMs) -ForegroundColor DarkGray
Write-Host ("DELTA_AUDIO_MS={0}" -f ($longAudioMs - $shortAudioMs)) -ForegroundColor DarkGray
Write-Host ("OUTPUT_ROOT={0}" -f $OutputRoot) -ForegroundColor DarkGray