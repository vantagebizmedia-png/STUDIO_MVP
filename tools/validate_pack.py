# -*- coding: utf-8 -*-
"""
Valida un pack exportado (pack_v03_*) y opcionalmente agrega hashes.

Contrato soportado:
- Base compat: pack.json, manifest_v03.json, artifacts/script.txt, artifacts/image.png, artifacts/audio.wav
- Escenas ricas en pack.json.scenes[] con visual_kind=image|video
- Timing explícito por escena: start_ms / end_ms / duration_ms
- Coherencia contractual: id / index / scene path / manifest
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any, Dict, List, Optional

REQ_FILES = [
    ("pack", "pack.json"),
    ("manifest", "manifest_v03.json"),
    ("script", "artifacts/script.txt"),
    ("image", "artifacts/image.png"),
    ("audio", "artifacts/audio.wav"),
]

SCENE_ID_RE = re.compile(r"^scene_(\d+)$", re.IGNORECASE)
SCENE_DIR_RE = re.compile(r"(?:^|/)artifacts/scenes/scene_(\d{2})/", re.IGNORECASE)


def sha256_file(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def read_json(p: Path) -> Dict[str, Any]:
    return json.loads(p.read_text(encoding="utf-8"))


def safe_int(value: Any, default: int = 0) -> int:
    try:
        return int(value or 0)
    except Exception:
        return default


def normalize_rel(value: Any) -> str:
    return str(value or "").strip().replace("\\", "/")


def asset_value(value: Any) -> str:
    if isinstance(value, str):
        return normalize_rel(value)
    if isinstance(value, dict):
        for key in ("path", "file", "value", "relpath"):
            raw = normalize_rel(value.get(key))
            if raw:
                return raw
    return ""


def scene_id_ordinal(value: Any) -> int:
    raw = str(value or "").strip()
    m = SCENE_ID_RE.match(raw)
    if not m:
        return 0
    try:
        parsed = int(m.group(1))
    except Exception:
        return 0
    return parsed if parsed > 0 else 0


def scene_path_ordinal(rel: Any) -> int:
    raw = normalize_rel(rel)
    if not raw:
        return 0
    m = SCENE_DIR_RE.search(raw)
    if not m:
        return 0
    try:
        parsed = int(m.group(1))
    except Exception:
        return 0
    return parsed if parsed > 0 else 0


def infer_visual_kind(scene: Dict[str, Any]) -> str:
    raw = str(scene.get("visual_kind") or "").strip().lower()
    if raw in ("image", "video"):
        return raw
    if asset_value(scene.get("video")):
        return "video"
    return "image"


def check_rel_file(pack_dir: Path, rel: str, label: str, problems: List[str]) -> Optional[Path]:
    rel_norm = normalize_rel(rel)
    if not rel_norm:
        problems.append(f"{label} FALTA path")
        return None
    fp = pack_dir / rel_norm
    if not fp.exists():
        problems.append(f"{label} FALTA file: {rel_norm}")
        return None
    if fp.is_file() and fp.stat().st_size <= 0:
        problems.append(f"{label} VACIO: {rel_norm}")
        return None
    return fp


def manifest_scene_asset(scene: Dict[str, Any], key: str) -> str:
    assets = scene.get("assets") if isinstance(scene.get("assets"), dict) else {}
    artifacts = scene.get("artifacts") if isinstance(scene.get("artifacts"), dict) else {}

    if key == "script":
        return (
            asset_value(artifacts.get("script"))
            or normalize_rel(scene.get("script"))
        )

    if key == "image":
        return (
            asset_value(assets.get("image"))
            or asset_value(artifacts.get("image"))
            or normalize_rel(scene.get("image"))
        )

    if key == "video":
        return (
            asset_value(assets.get("video"))
            or asset_value(artifacts.get("video"))
            or normalize_rel(scene.get("video"))
        )

    if key == "audio":
        return (
            asset_value(assets.get("audio_clip"))
            or asset_value(artifacts.get("audio"))
            or normalize_rel(scene.get("audio"))
        )

    return ""


def validate_scene(
    pack_dir: Path,
    scene: Dict[str, Any],
    manifest_scene: Optional[Dict[str, Any]],
    problems: List[str],
) -> int:
    idx = safe_int(scene.get("index"), 0)
    sid = str(scene.get("id") or "").strip()
    sid_ord = scene_id_ordinal(sid)

    label = sid if sid else (f"scene_{idx:03d}" if idx > 0 else "scene_unknown")

    if idx <= 0:
        problems.append(f"{label} index inválido: {idx}")

    if sid_ord > 0 and idx > 0 and sid_ord != idx:
        problems.append(f"{label} id/index desalineados: id->{sid_ord} index={idx}")

    script_rel = asset_value(scene.get("script"))
    image_rel = asset_value(scene.get("image"))
    video_rel = asset_value(scene.get("video"))
    audio_rel = asset_value(scene.get("audio"))
    visual_kind = infer_visual_kind(scene)

    check_rel_file(pack_dir, script_rel, f"{label} script", problems)
    check_rel_file(pack_dir, audio_rel, f"{label} audio", problems)

    if visual_kind == "video":
        check_rel_file(pack_dir, video_rel, f"{label} video", problems)
        if normalize_rel(image_rel):
            problems.append(f"{label} visual_kind=video pero image no vacío: {image_rel}")
    else:
        check_rel_file(pack_dir, image_rel, f"{label} image", problems)
        if normalize_rel(video_rel):
            problems.append(f"{label} visual_kind=image pero video no vacío: {video_rel}")

    for rel_name, rel_value in [
        ("script", script_rel),
        ("image", image_rel),
        ("video", video_rel),
        ("audio", audio_rel),
    ]:
        ord_from_path = scene_path_ordinal(rel_value)
        if ord_from_path > 0 and idx > 0 and ord_from_path != idx:
            problems.append(
                f"{label} {rel_name} path desalineado: scene_{ord_from_path:02d} != index={idx}"
            )

    start_ms = safe_int(scene.get("start_ms"), -1)
    end_ms = safe_int(scene.get("end_ms"), -1)
    duration_ms = safe_int(scene.get("duration_ms"), -1)

    if start_ms < -1:
        problems.append(f"{label} start_ms inválido: {start_ms}")
    if end_ms < -1:
        problems.append(f"{label} end_ms inválido: {end_ms}")
    if duration_ms < -1:
        problems.append(f"{label} duration_ms inválido: {duration_ms}")

    derived_end = 0
    if start_ms >= 0 and end_ms >= 0:
        if end_ms < start_ms:
            problems.append(f"{label} end_ms < start_ms ({end_ms} < {start_ms})")
        derived_end = max(derived_end, end_ms)

    if duration_ms > 0 and start_ms >= 0 and end_ms >= 0:
        if (end_ms - start_ms) != duration_ms:
            problems.append(
                f"{label} timing inconsistente: end-start={end_ms - start_ms} != duration_ms={duration_ms}"
            )

    if duration_ms > 0 and start_ms >= 0 and end_ms < 0:
        derived_end = max(derived_end, start_ms + duration_ms)

    if end_ms >= 0:
        derived_end = max(derived_end, end_ms)

    requested_media_type = str(scene.get("requested_media_type") or "").strip().lower()
    visual_request_kind = str(scene.get("visual_request_kind") or "").strip().lower()
    if requested_media_type and visual_request_kind and requested_media_type != visual_request_kind:
        problems.append(
            f"{label} requested_media_type/visual_request_kind conflictivos: "
            f"{requested_media_type} != {visual_request_kind}"
        )

    if manifest_scene is not None:
        manifest_id = str(manifest_scene.get("id") or "").strip()
        manifest_index = safe_int(manifest_scene.get("index"), 0)
        manifest_visual_kind = infer_visual_kind(manifest_scene)

        if manifest_id and sid and manifest_id != sid:
            problems.append(f"{label} id pack/manifest mismatch: pack={sid} manifest={manifest_id}")

        if manifest_index > 0 and idx > 0 and manifest_index != idx:
            problems.append(f"{label} index pack/manifest mismatch: pack={idx} manifest={manifest_index}")

        if manifest_visual_kind != visual_kind:
            problems.append(
                f"{label} visual_kind pack/manifest mismatch: pack={visual_kind} manifest={manifest_visual_kind}"
            )

        for field_name in ("start_ms", "end_ms", "duration_ms"):
            pack_val = safe_int(scene.get(field_name), -1)
            manifest_val = safe_int(manifest_scene.get(field_name), -1)
            if pack_val >= 0 and manifest_val >= 0 and pack_val != manifest_val:
                problems.append(
                    f"{label} {field_name} pack/manifest mismatch: pack={pack_val} manifest={manifest_val}"
                )

        for logical_key in ("script", "image", "video", "audio"):
            pack_rel = normalize_rel(
                asset_value(scene.get(logical_key))
            )
            manifest_rel = normalize_rel(
                manifest_scene_asset(manifest_scene, logical_key)
            )
            if pack_rel and manifest_rel and pack_rel != manifest_rel:
                problems.append(
                    f"{label} {logical_key} pack/manifest mismatch: pack={pack_rel} manifest={manifest_rel}"
                )

    return derived_end


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack-dir", required=True)
    ap.add_argument("--fix", action="store_true")
    args = ap.parse_args()

    pack_dir = Path(args.pack_dir).expanduser().resolve()
    if not pack_dir.exists() or not pack_dir.is_dir():
        raise SystemExit(f"ERROR: pack-dir invalido: {pack_dir}")

    problems: List[str] = []
    paths: Dict[str, Path] = {}

    for key, rel in REQ_FILES:
        fp = pack_dir / rel
        paths[key] = fp
        if not fp.exists():
            problems.append(f"FALTA: {rel}")
        elif fp.is_file() and fp.stat().st_size <= 0:
            problems.append(f"VACIO: {rel}")

    if not paths["pack"].exists():
        for pr in problems:
            print("ERROR:", pr)
        raise SystemExit("ERROR: pack.json faltante (no puedo continuar).")

    try:
        pack = read_json(paths["pack"])
    except Exception as e:
        raise SystemExit(f"ERROR: pack.json no es JSON valido: {e}")

    try:
        manifest = read_json(paths["manifest"])
    except Exception as e:
        raise SystemExit(f"ERROR: manifest_v03.json no es JSON valido: {e}")

    pj_paths = pack.get("paths") or {}
    expected = {
        "script": "artifacts/script.txt",
        "image": "artifacts/image.png",
        "audio": "artifacts/audio.wav",
        "manifest": "manifest_v03.json",
    }
    for k, rel in expected.items():
        if k in pj_paths and normalize_rel(pj_paths[k]) != rel:
            problems.append(f"paths.{k} en pack.json != {rel} (tiene {pj_paths[k]})")

    if args.fix:
        checksums = pack.get("checksums") or {}
        sha = checksums.get("sha256") or {}
        changed = False

        for k, rel in [
            ("script", "artifacts/script.txt"),
            ("image", "artifacts/image.png"),
            ("audio", "artifacts/audio.wav"),
            ("manifest", "manifest_v03.json"),
        ]:
            fp = pack_dir / rel
            if fp.exists() and k not in sha:
                sha[k] = sha256_file(fp)
                changed = True

        if changed:
            checksums["sha256"] = sha
            pack["checksums"] = checksums
            paths["pack"].write_text(json.dumps(pack, ensure_ascii=False, indent=2), encoding="utf-8")
            print("OK: checksums agregados a pack.json")
        else:
            print("OK: checksums ya estaban presentes (no cambios)")

    scenes = pack.get("scenes") or []
    if scenes and not isinstance(scenes, list):
        problems.append("pack.json scenes debe ser list")
        scenes = []

    scenes_v03 = pack.get("scenes_v03") or []
    if scenes_v03 and not isinstance(scenes_v03, list):
        problems.append("pack.json scenes_v03 debe ser list")
        scenes_v03 = []

    manifest_scenes_v03 = manifest.get("scenes_v03") or []
    if manifest_scenes_v03 and not isinstance(manifest_scenes_v03, list):
        problems.append("manifest_v03.json scenes_v03 debe ser list")
        manifest_scenes_v03 = []

    if isinstance(scenes, list) and isinstance(scenes_v03, list) and scenes and scenes_v03:
        if len(scenes) != len(scenes_v03):
            problems.append(
                f"pack.json desalineado: scenes={len(scenes)} != scenes_v03={len(scenes_v03)}"
            )

    if isinstance(scenes, list) and isinstance(manifest_scenes_v03, list) and scenes and manifest_scenes_v03:
        if len(scenes) != len(manifest_scenes_v03):
            problems.append(
                f"pack/manifest desalineados: pack.scenes={len(scenes)} != manifest.scenes_v03={len(manifest_scenes_v03)}"
            )

    manifest_by_index: Dict[int, Dict[str, Any]] = {}
    if isinstance(manifest_scenes_v03, list):
        for raw in manifest_scenes_v03:
            if not isinstance(raw, dict):
                problems.append("manifest_v03.json scenes_v03 contiene entrada no dict")
                continue
            idx = safe_int(raw.get("index"), 0)
            if idx <= 0:
                idx = scene_id_ordinal(raw.get("id"))
            if idx > 0:
                manifest_by_index[idx] = dict(raw or {})

    max_scene_end_ms = 0
    if isinstance(scenes, list) and scenes:
        for raw in scenes:
            if not isinstance(raw, dict):
                problems.append("pack.json scenes contiene entrada no dict")
                continue
            row = dict(raw or {})
            idx = safe_int(row.get("index"), 0)
            if idx <= 0:
                idx = scene_id_ordinal(row.get("id"))
            manifest_scene = manifest_by_index.get(idx)
            max_scene_end_ms = max(
                max_scene_end_ms,
                validate_scene(pack_dir, row, manifest_scene, problems),
            )

    pack_total_audio_ms = safe_int(pack.get("total_audio_ms"), 0)
    if pack_total_audio_ms > 0 and max_scene_end_ms > 0 and pack_total_audio_ms < max_scene_end_ms:
        problems.append(
            f"pack.total_audio_ms={pack_total_audio_ms} < max_scene_end_ms={max_scene_end_ms}"
        )

    scene_builder = pack.get("scene_builder_v03") or {}
    if scene_builder and not isinstance(scene_builder, dict):
        problems.append("pack.scene_builder_v03 debe ser dict")
        scene_builder = {}

    sb_total_audio_ms = safe_int(scene_builder.get("total_audio_ms"), 0)
    if sb_total_audio_ms > 0 and max_scene_end_ms > 0 and sb_total_audio_ms < max_scene_end_ms:
        problems.append(
            f"scene_builder_v03.total_audio_ms={sb_total_audio_ms} < max_scene_end_ms={max_scene_end_ms}"
        )

    if problems:
        for pr in problems:
            print("WARN:", pr)
        print("\nRESULT: FAIL")
        return 2

    print("\nRESULT: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
