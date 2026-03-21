# -*- coding: utf-8 -*-
"""Valida el handoff final de un pack exportado.

Contrato soportado:
- pack.json, manifest_v03.json, video.mp4, video_music_auto.mp4, video_final.mp4, HANDOFF_READY.txt
- <pack>.final_delivery.zip y <pack>.final_delivery.zip.sha256.txt en el parent del pack
- coherencia entre HANDOFF_READY, ZIP y SHA real
- presencia mínima de archivos clave dentro del ZIP final
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import zipfile
from pathlib import Path
from typing import Dict, List, Tuple

REQ_PACK_FILES = [
    "pack.json",
    "manifest_v03.json",
    "video.mp4",
    "video_music_auto.mp4",
    "video_final.mp4",
    "HANDOFF_READY.txt",
]

HANDOFF_FIELDS = [
    "PACK_ID",
    "ZIP_FILE",
    "ZIP_SHA256",
    "VIDEO_BASE",
    "VIDEO_MUSIC_AUTO",
    "VIDEO_FINAL",
    "AUTO_MUSIC_ENABLED",
    "DETERMINISTIC",
]

SHA_LINE_RE = re.compile(r"^([A-Fa-f0-9]{64})\s+\*?(.+?)\s*$")
KV_RE = re.compile(r"^([A-Z0-9_]+):\s*(.*)$")


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8").replace("\r\n", "\n").replace("\r", "\n")


def parse_handoff_ready(path: Path) -> Tuple[str, Dict[str, str]]:
    lines = [line.rstrip("\n") for line in _read_text(path).split("\n")]
    while lines and lines[-1] == "":
        lines.pop()

    if not lines:
        return "", {}

    header = lines[0].strip()
    fields: Dict[str, str] = {}
    for raw in lines[1:]:
        line = raw.strip()
        if not line:
            continue
        m = KV_RE.match(line)
        if not m:
            continue
        fields[m.group(1).strip()] = m.group(2).strip()
    return header, fields


def parse_sha_sidecar(path: Path) -> Tuple[str, str]:
    raw = _read_text(path).strip()
    if not raw:
        return "", ""
    m = SHA_LINE_RE.match(raw)
    if not m:
        return "", ""
    return m.group(1).lower(), m.group(2).strip()


def _load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def _scene_visual_kind(scene: dict) -> str:
    raw = str(scene.get("visual_kind") or "").strip().lower()
    if raw in ("image", "video"):
        return raw

    image_rel = str(scene.get("image") or "").strip()
    video_rel = str(scene.get("video") or "").strip()

    assets = scene.get("assets") or {}
    artifacts = scene.get("artifacts") or {}

    if not image_rel:
        image_rel = str(assets.get("image") or artifacts.get("image") or "").strip()
    if not video_rel:
        video_rel = str(assets.get("video") or artifacts.get("video") or "").strip()

    if video_rel and not image_rel:
        return "video"
    if image_rel and not video_rel:
        return "image"
    if video_rel:
        return "video"
    return "image"


def _expected_visual_contract(visual_kind: str) -> Tuple[str, str]:
    if visual_kind == "video":
        return ("stock_video", "stock_video")
    return ("stock_image", "stock_image")


def _validate_scene_visual_contract(
    pack_scene: dict,
    manifest_scene: dict,
    label: str,
    problems: List[str],
) -> None:
    pack_visual_kind = _scene_visual_kind(pack_scene)
    manifest_visual_kind = _scene_visual_kind(manifest_scene)

    if pack_visual_kind != manifest_visual_kind:
        problems.append(
            f"{label} visual_kind pack/manifest mismatch: "
            f"pack={pack_visual_kind} manifest={manifest_visual_kind}"
        )

    expected_pack_source, expected_pack_capability = _expected_visual_contract(pack_visual_kind)
    expected_manifest_source, expected_manifest_capability = _expected_visual_contract(manifest_visual_kind)

    pack_visual_source_kind = str(pack_scene.get("visual_source_kind") or "").strip().lower()
    pack_visual_capability = str(pack_scene.get("visual_capability") or "").strip().lower()
    manifest_visual_source_kind = str(manifest_scene.get("visual_source_kind") or "").strip().lower()
    manifest_visual_capability = str(manifest_scene.get("visual_capability") or "").strip().lower()

    if not pack_visual_source_kind:
        problems.append(f"{label} visual_source_kind vacío en pack final")
    elif pack_visual_source_kind not in ("stock_image", "stock_video"):
        problems.append(f"{label} visual_source_kind inválido en pack final: {pack_visual_source_kind}")
    elif pack_visual_source_kind != expected_pack_source:
        problems.append(
            f"{label} visual_source_kind incompatible con visual_kind={pack_visual_kind} en pack final: "
            f"{pack_visual_source_kind}"
        )

    if not pack_visual_capability:
        problems.append(f"{label} visual_capability vacío en pack final")
    elif pack_visual_capability not in ("stock_image", "stock_video"):
        problems.append(f"{label} visual_capability inválido en pack final: {pack_visual_capability}")
    elif pack_visual_capability != expected_pack_capability:
        problems.append(
            f"{label} visual_capability incompatible con visual_kind={pack_visual_kind} en pack final: "
            f"{pack_visual_capability}"
        )

    if not manifest_visual_source_kind:
        problems.append(f"{label} visual_source_kind vacío en manifest final")
    elif manifest_visual_source_kind not in ("stock_image", "stock_video"):
        problems.append(f"{label} visual_source_kind inválido en manifest final: {manifest_visual_source_kind}")
    elif manifest_visual_source_kind != expected_manifest_source:
        problems.append(
            f"{label} visual_source_kind incompatible con visual_kind={manifest_visual_kind} en manifest final: "
            f"{manifest_visual_source_kind}"
        )

    if not manifest_visual_capability:
        problems.append(f"{label} visual_capability vacío en manifest final")
    elif manifest_visual_capability not in ("stock_image", "stock_video"):
        problems.append(f"{label} visual_capability inválido en manifest final: {manifest_visual_capability}")
    elif manifest_visual_capability != expected_manifest_capability:
        problems.append(
            f"{label} visual_capability incompatible con visual_kind={manifest_visual_kind} en manifest final: "
            f"{manifest_visual_capability}"
        )

    if pack_visual_source_kind and manifest_visual_source_kind and pack_visual_source_kind != manifest_visual_source_kind:
        problems.append(
            f"{label} visual_source_kind pack/manifest mismatch en handoff final: "
            f"pack={pack_visual_source_kind} manifest={manifest_visual_source_kind}"
        )

    if pack_visual_capability and manifest_visual_capability and pack_visual_capability != manifest_visual_capability:
        problems.append(
            f"{label} visual_capability pack/manifest mismatch en handoff final: "
            f"pack={pack_visual_capability} manifest={manifest_visual_capability}"
        )


def validate(pack_dir: Path) -> List[str]:
    problems: List[str] = []

    if not pack_dir.exists() or not pack_dir.is_dir():
        return [f"pack-dir invalido: {pack_dir}"]

    for rel in REQ_PACK_FILES:
        fp = pack_dir / rel
        if not fp.exists() or not fp.is_file():
            problems.append(f"falta archivo requerido: {rel}")
            continue
        if fp.stat().st_size <= 0:
            problems.append(f"archivo vacio: {rel}")

    zip_path = pack_dir.parent / f"{pack_dir.name}.final_delivery.zip"
    sha_path = pack_dir.parent / f"{pack_dir.name}.final_delivery.zip.sha256.txt"

    if not zip_path.exists() or not zip_path.is_file():
        problems.append(f"falta zip final: {zip_path.name}")
    elif zip_path.stat().st_size <= 0:
        problems.append(f"zip final vacio: {zip_path.name}")

    if not sha_path.exists() or not sha_path.is_file():
        problems.append(f"falta sha final: {sha_path.name}")
    elif sha_path.stat().st_size <= 0:
        problems.append(f"sha final vacio: {sha_path.name}")

    if zip_path.exists() and sha_path.exists() and zip_path.is_file() and sha_path.is_file():
        actual_sha = sha256_file(zip_path)
        sidecar_sha, sidecar_name = parse_sha_sidecar(sha_path)
        if not sidecar_sha:
            problems.append(f"sha sidecar invalido: {sha_path.name}")
        else:
            if sidecar_sha != actual_sha:
                problems.append(f"sha mismatch: sidecar={sidecar_sha} actual={actual_sha}")
            if sidecar_name != zip_path.name:
                problems.append(
                    f"sha sidecar file mismatch: sidecar={sidecar_name} zip={zip_path.name}"
                )

    handoff_path = pack_dir / "HANDOFF_READY.txt"
    if handoff_path.exists() and handoff_path.is_file():
        header, fields = parse_handoff_ready(handoff_path)
        if header != "HANDOFF_READY":
            problems.append(f"HANDOFF_READY invalido: header={header!r}")

        for key in HANDOFF_FIELDS:
            if not fields.get(key, "").strip():
                problems.append(f"HANDOFF_READY falta campo: {key}")

        if fields.get("PACK_ID", "") != pack_dir.name:
            problems.append(
                f"HANDOFF_READY PACK_ID mismatch: {fields.get('PACK_ID', '')} != {pack_dir.name}"
            )

        expected_zip_name = f"{pack_dir.name}.final_delivery.zip"
        if fields.get("ZIP_FILE", "") != expected_zip_name:
            problems.append(
                f"HANDOFF_READY ZIP_FILE mismatch: {fields.get('ZIP_FILE', '')} != {expected_zip_name}"
            )

        if zip_path.exists() and zip_path.is_file():
            expected_sha = sha256_file(zip_path)
            if fields.get("ZIP_SHA256", "").lower() != expected_sha:
                problems.append("HANDOFF_READY ZIP_SHA256 mismatch")

        if fields.get("VIDEO_BASE", "") != "video.mp4":
            problems.append(f"HANDOFF_READY VIDEO_BASE mismatch: {fields.get('VIDEO_BASE', '')}")
        if fields.get("VIDEO_MUSIC_AUTO", "") != "video_music_auto.mp4":
            problems.append(
                f"HANDOFF_READY VIDEO_MUSIC_AUTO mismatch: {fields.get('VIDEO_MUSIC_AUTO', '')}"
            )
        if fields.get("VIDEO_FINAL", "") != "video_final.mp4":
            problems.append(f"HANDOFF_READY VIDEO_FINAL mismatch: {fields.get('VIDEO_FINAL', '')}")

        auto_music_enabled = fields.get("AUTO_MUSIC_ENABLED", "").strip().lower()
        if auto_music_enabled not in ("true", "false"):
            problems.append(
                f"HANDOFF_READY AUTO_MUSIC_ENABLED invalido: {fields.get('AUTO_MUSIC_ENABLED', '')}"
            )

        if fields.get("DETERMINISTIC", "").strip().lower() != "true":
            problems.append(
                f"HANDOFF_READY DETERMINISTIC invalido: {fields.get('DETERMINISTIC', '')}"
            )

    for rel in ("video.mp4", "video_music_auto.mp4", "video_final.mp4"):
        fp = pack_dir / rel
        if fp.exists() and fp.is_file() and fp.stat().st_size <= 0:
            problems.append(f"video vacio: {rel}")

    pack_json_path = pack_dir / "pack.json"
    manifest_json_path = pack_dir / "manifest_v03.json"
    if pack_json_path.exists() and manifest_json_path.exists():
        try:
            pack_obj = _load_json(pack_json_path)
            manifest_obj = _load_json(manifest_json_path)
        except Exception as exc:
            problems.append(f"no se pudo leer pack/manifest final para contrato visual: {exc}")
        else:
            pack_scenes = list(pack_obj.get("scenes") or [])
            manifest_scenes = list(manifest_obj.get("scenes_v03") or [])
            if len(pack_scenes) != len(manifest_scenes):
                problems.append(
                    f"handoff final scenes count mismatch pack/manifest: "
                    f"pack={len(pack_scenes)} manifest={len(manifest_scenes)}"
                )
            else:
                for idx, (pack_scene, manifest_scene) in enumerate(zip(pack_scenes, manifest_scenes), start=1):
                    label = str(pack_scene.get("id") or manifest_scene.get("id") or f"scene_{idx:03d}").strip()
                    if not label:
                        label = f"scene_{idx:03d}"
                    _validate_scene_visual_contract(pack_scene, manifest_scene, label, problems)

    if zip_path.exists() and zip_path.is_file():
        try:
            with zipfile.ZipFile(zip_path, "r") as zf:
                names = set(zf.namelist())
        except Exception as exc:
            problems.append(f"zip invalido: {exc}")
        else:
            required_members = [
                f"{pack_dir.name}/pack.json",
                f"{pack_dir.name}/manifest_v03.json",
                f"{pack_dir.name}/video.mp4",
                f"{pack_dir.name}/video_music_auto.mp4",
                f"{pack_dir.name}/video_final.mp4",
            ]
            for member in required_members:
                if member not in names:
                    problems.append(f"zip falta miembro requerido: {member}")

    return problems


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack-dir", required=True)
    args = ap.parse_args()

    pack_dir = Path(args.pack_dir).expanduser().resolve()
    problems = validate(pack_dir)
    if problems:
      print("RESULT: FAIL")
      for item in problems:
          print(f" - {item}")
      return 1

    print("RESULT: PASS")
    print(f"PACK_DIR: {pack_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
