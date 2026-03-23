param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$psUtf8Compat = Join-Path $PSScriptRoot "ps_utf8_compat_v03.ps1"
if (-not (Test-Path -LiteralPath $psUtf8Compat -PathType Leaf)) {
  throw ("No existe helper utf8 compat: {0}" -f $psUtf8Compat)
}

. $psUtf8Compat

# Repo root robusto SIN $PSScriptRoot (porque a veces lo pegan en consola)
$repo = (Resolve-Path ".").Path

function Write-TextFileExact {
  param(
    [Parameter(Mandatory=$true)][string]$RelPath,
    [Parameter(Mandatory=$true)][string]$Content
  )
  $full = Join-Path $repo $RelPath
  $dir = Split-Path $full -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  Set-Content -LiteralPath $full -Value $Content -Encoding UTF8
  Write-Host "WROTE: $RelPath" -ForegroundColor Green
}

# REPLACE: tools/patch_manifest_scene_builder_v03.py  (NO import studio)
Write-TextFileExact -RelPath "tools/patch_manifest_scene_builder_v03.py" -Content @"
# tools/patch_manifest_scene_builder_v03.py
# Runner: carga manifest_v03.json, aplica Scene Builder, guarda.
# IMPORTANTE: no depende de PYTHONPATH ni de que "studio" sea paquete.

from __future__ import annotations

import json
import argparse
from pathlib import Path
import importlib.util
import sys


def _load_module_from_path(mod_name: str, path: Path):
    if not path.exists():
        raise SystemExit(f""Falta archivo requerido: {path}"")
    spec = importlib.util.spec_from_file_location(mod_name, str(path))
    if spec is None or spec.loader is None:
        raise SystemExit(f""No pude cargar spec para: {path}"")
    mod = importlib.util.module_from_spec(spec)
    sys.modules[mod_name] = mod
    spec.loader.exec_module(mod)  # type: ignore[attr-defined]
    return mod


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(""--pack-dir"", required=True)
    ap.add_argument(""--max-scenes"", type=int, default=6)
    args = ap.parse_args()

    pack = Path(args.pack_dir)
    manifest_path = pack / ""manifest_v03.json""
    if not manifest_path.exists():
        raise SystemExit(f""manifest_v03.json no existe en: {pack}"")

    repo = Path(__file__).resolve().parent.parent

    patcher_path = repo / ""studio"" / ""live_manifest_patch_v03.py""
    patcher = _load_module_from_path(""_live_manifest_patch_v03"", patcher_path)

    if not hasattr(patcher, ""apply_scene_builder_to_manifest""):
        raise SystemExit(f""{patcher_path} no define apply_scene_builder_to_manifest(...)"")
    manifest = json.loads(manifest_path.read_text(encoding=""utf-8""))
    manifest = patcher.apply_scene_builder_to_manifest(  # type: ignore[attr-defined]
        manifest,
        pack_dir=str(pack),
        max_scenes=int(args.max_scenes),
    )

    scenes = manifest.get(""scenes"")
    if not isinstance(scenes, list) or len(scenes) < 1:
        raise SystemExit(""Patch no produjo scenes[] válido."")
    first = scenes[0]
    if not isinstance(first, dict) or ""start_ms"" not in first or ""end_ms"" not in first:
        raise SystemExit(""Patch produjo scenes[] pero sin start_ms/end_ms."")

    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding=""utf-8"")
    return 0


if __name__ == ""__main__"":
    raise SystemExit(main())
"@

# REPLACE: tools/apply_scene_builder_v03.ps1  (falla si python falla)
Write-TextFileExact -RelPath "tools/apply_scene_builder_v03.ps1" -Content @"
param(
  [Parameter(Mandatory=$true)][string]`$PackDir,
  [int]`$MaxScenes = 6
)

Set-StrictMode -Version Latest
`$ErrorActionPreference = ""Stop""

`$psUtf8Compat = Join-Path `$PSScriptRoot ""ps_utf8_compat_v03.ps1""
if (-not (Test-Path -LiteralPath `$psUtf8Compat -PathType Leaf)) {
  throw (""No existe helper utf8 compat: {0}"" -f `$psUtf8Compat)
}
. `$psUtf8Compat

`$repo = (Resolve-Path ""."").Path
`$pack = (Resolve-Path `$PackDir).Path

`$manifest = Join-Path `$pack ""manifest_v03.json""
if (-not (Test-Path `$manifest)) { throw ""Falta manifest_v03.json en: `$pack"" }

`$py = Join-Path `$repo ""tools\patch_manifest_scene_builder_v03.py""
if (-not (Test-Path `$py)) { throw ""Falta patcher: `$py"" }

python -u `$py --pack-dir `$pack --max-scenes `$MaxScenes

`$m = Get-Content -LiteralPath `$manifest -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not `$m.scenes) { throw ""Patch no produjo scenes[] en manifest."" }

`$scenes = @(`$m.scenes)
if (`$scenes.Count -lt 1) { throw ""Patch produjo scenes[] vacío."" }

`$first = `$scenes[0]
if (-not (`$first.PSObject.Properties.Name -contains ""start_ms"")) { throw ""Patch no aplicó esquema v03: scenes[0] sin start_ms."" }
if (-not (`$first.PSObject.Properties.Name -contains ""end_ms"")) { throw ""Patch no aplicó esquema v03: scenes[0] sin end_ms."" }

Write-Host ""OK: Scene Builder aplicado al manifest. Pack=`$pack scenes=`$(`$scenes.Count)"" -ForegroundColor Green
"@

Write-Host "INSTALL OK: Fix v03 aplicado (patcher + apply)." -ForegroundColor Green
