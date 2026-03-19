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
