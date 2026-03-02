# -*- coding: utf-8 -*-
"""Finalize/handoff v0.3 for an exported pack directory.

def _zip_add_deterministic(zf, file_path: Path, arcname: str):
    data = file_path.read_bytes()
    zi = zipfile.ZipInfo(arcname)
    # timestamp fijo (1980-01-01 00:00:00) -> determinista en ZIP
    zi.date_time = (1980, 1, 1, 0, 0, 0)
    zi.compress_type = zipfile.ZIP_DEFLATED
    zf.writestr(zi, data)

Creates deterministic delivery artifacts:
- video.mp4
- video_music_auto.mp4
- video_final.mp4
- <pack>.final_delivery.zip
- <pack>.final_delivery.zip.sha256.txt
- HANDOFF_READY.txt
"""
from __future__ import annotations

def _zip_add_deterministic(zf, file_path: Path, arcname: str):
    data = file_path.read_bytes()
    zi = zipfile.ZipInfo(arcname)
    # timestamp fijo (1980-01-01 00:00:00) -> determinista en ZIP
    zi.date_time = (1980, 1, 1, 0, 0, 0)
    zi.compress_type = zipfile.ZIP_DEFLATED
    zf.writestr(zi, data)

import argparse
import hashlib
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path
from typing import Iterable

def _zip_add_deterministic(zf, file_path: Path, arcname: str):
    data = file_path.read_bytes()
    zi = zipfile.ZipInfo(arcname)
    # timestamp fijo (1980-01-01 00:00:00) -> determinista en ZIP
    zi.date_time = (1980, 1, 1, 0, 0, 0)
    zi.compress_type = zipfile.ZIP_DEFLATED
    zf.writestr(zi, data)


def sha256_file(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def _zip_add_deterministic(zf, file_path: Path, arcname: str):
    data = file_path.read_bytes()
    zi = zipfile.ZipInfo(arcname)
    # timestamp fijo (1980-01-01 00:00:00) -> determinista en ZIP
    zi.date_time = (1980, 1, 1, 0, 0, 0)
    zi.compress_type = zipfile.ZIP_DEFLATED
    zf.writestr(zi, data)


def _stable_files(root: Path) -> Iterable[Path]:
    items = [p for p in root.rglob("*") if p.is_file()]
    return sorted(items, key=lambda x: str(x.relative_to(root)).replace("\\", "/"))

def _zip_add_deterministic(zf, file_path: Path, arcname: str):
    data = file_path.read_bytes()
    zi = zipfile.ZipInfo(arcname)
    # timestamp fijo (1980-01-01 00:00:00) -> determinista en ZIP
    zi.date_time = (1980, 1, 1, 0, 0, 0)
    zi.compress_type = zipfile.ZIP_DEFLATED
    zf.writestr(zi, data)


def make_deterministic_zip(pack_dir: Path, out_zip: Path) -> None:
    out_zip.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(out_zip, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        for fp in _stable_files(pack_dir):
            rel = fp.relative_to(pack_dir)
            arc = (Path(pack_dir.name) / rel).as_posix()
            zi = zipfile.ZipInfo(arc)
            zi.date_time = (1980, 1, 1, 0, 0, 0)
            zi.compress_type = zipfile.ZIP_DEFLATED
            zi.external_attr = 0o100644 << 16
            zf.writestr(zi, fp.read_bytes())

def _zip_add_deterministic(zf, file_path: Path, arcname: str):
    data = file_path.read_bytes()
    zi = zipfile.ZipInfo(arcname)
    # timestamp fijo (1980-01-01 00:00:00) -> determinista en ZIP
    zi.date_time = (1980, 1, 1, 0, 0, 0)
    zi.compress_type = zipfile.ZIP_DEFLATED
    zf.writestr(zi, data)


def write_sha_file(zip_path: Path) -> Path:
    sha = sha256_file(zip_path)
    out = zip_path.with_name(zip_path.name + ".sha256.txt")
    out.write_text(f"{sha}  {zip_path.name}\n", encoding="ascii")
    return out

def _zip_add_deterministic(zf, file_path: Path, arcname: str):
    data = file_path.read_bytes()
    zi = zipfile.ZipInfo(arcname)
    # timestamp fijo (1980-01-01 00:00:00) -> determinista en ZIP
    zi.date_time = (1980, 1, 1, 0, 0, 0)
    zi.compress_type = zipfile.ZIP_DEFLATED
    zf.writestr(zi, data)


def write_handoff_ready(pack_dir: Path, zip_path: Path, zip_sha: str, auto_music: bool) -> Path:
    lines = [
        "HANDOFF_READY",
        f"PACK_ID: {pack_dir.name}",
        f"ZIP_FILE: {zip_path.name}",
        f"ZIP_SHA256: {zip_sha}",
        "VIDEO_BASE: video.mp4",
        "VIDEO_MUSIC_AUTO: video_music_auto.mp4",
        "VIDEO_FINAL: video_final.mp4",
        f"AUTO_MUSIC_ENABLED: {'true' if auto_music else 'false'}",
        "DETERMINISTIC: true",
    ]
    out = pack_dir / "HANDOFF_READY.txt"
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return out

def _zip_add_deterministic(zf, file_path: Path, arcname: str):
    data = file_path.read_bytes()
    zi = zipfile.ZipInfo(arcname)
    # timestamp fijo (1980-01-01 00:00:00) -> determinista en ZIP
    zi.date_time = (1980, 1, 1, 0, 0, 0)
    zi.compress_type = zipfile.ZIP_DEFLATED
    zf.writestr(zi, data)


def _run(cmd: list[str]) -> None:
    p = subprocess.run(cmd, text=True, **kwargs)
    if p.returncode != 0:
        raise SystemExit(f"ERROR: comando falló (exit={p.returncode}): {' '.join(cmd)}")

def _zip_add_deterministic(zf, file_path: Path, arcname: str):
    data = file_path.read_bytes()
    zi = zipfile.ZipInfo(arcname)
    # timestamp fijo (1980-01-01 00:00:00) -> determinista en ZIP
    zi.date_time = (1980, 1, 1, 0, 0, 0)
    zi.compress_type = zipfile.ZIP_DEFLATED
    zf.writestr(zi, data)


def ensure_video_base(pack_dir: Path, python_exe: str) -> Path:
    video = pack_dir / "video.mp4"
    if video.exists() and video.stat().st_size > 0:
        return video
    _run([python_exe, "tools/render_pack_v03.py", "--pack-dir", str(pack_dir)])
    if not video.exists() or video.stat().st_size <= 0:
        raise SystemExit(f"ERROR: no se generó video.mp4 en {pack_dir}")
    return video

def _zip_add_deterministic(zf, file_path: Path, arcname: str):
    data = file_path.read_bytes()
    zi = zipfile.ZipInfo(arcname)
    # timestamp fijo (1980-01-01 00:00:00) -> determinista en ZIP
    zi.date_time = (1980, 1, 1, 0, 0, 0)
    zi.compress_type = zipfile.ZIP_DEFLATED
    zf.writestr(zi, data)


def _copy_file(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dst)

def _zip_add_deterministic(zf, file_path: Path, arcname: str):
    data = file_path.read_bytes()
    zi = zipfile.ZipInfo(arcname)
    # timestamp fijo (1980-01-01 00:00:00) -> determinista en ZIP
    zi.date_time = (1980, 1, 1, 0, 0, 0)
    zi.compress_type = zipfile.ZIP_DEFLATED
    zf.writestr(zi, data)


def produce_delivery_videos(pack_dir: Path, python_exe: str, auto_music: bool, music_dir: str) -> tuple[Path, Path, Path]:
    video = ensure_video_base(pack_dir, python_exe)
    video_music = pack_dir / "video_music_auto.mp4"
    video_final = pack_dir / "video_final.mp4"

def _zip_add_deterministic(zf, file_path: Path, arcname: str):
    data = file_path.read_bytes()
    zi = zipfile.ZipInfo(arcname)
    # timestamp fijo (1980-01-01 00:00:00) -> determinista en ZIP
    zi.date_time = (1980, 1, 1, 0, 0, 0)
    zi.compress_type = zipfile.ZIP_DEFLATED
    zf.writestr(zi, data)

    if auto_music:
        _run([
            "powershell",
            "-NoProfile",
            "-NoLogo",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            "tools/finalize_pack_auto_music.ps1",
            "-PackDir",
            str(pack_dir),
            "-MusicDir",
            music_dir,
            "-VideoName",
            "video.mp4",
            "-OutputVideoName",
            "video_music_auto.mp4",
            "-FinalVideoName",
            "video_final.mp4",
        ])
        if not video_music.exists() or video_music.stat().st_size <= 0:
            raise SystemExit(f"ERROR: falta video_music_auto.mp4 en {pack_dir}")
        if not video_final.exists() or video_final.stat().st_size <= 0:
            raise SystemExit(f"ERROR: falta video_final.mp4 en {pack_dir}")
    else:
        _copy_file(video, video_music)
        _copy_file(video, video_final)

def _zip_add_deterministic(zf, file_path: Path, arcname: str):
    data = file_path.read_bytes()
    zi = zipfile.ZipInfo(arcname)
    # timestamp fijo (1980-01-01 00:00:00) -> determinista en ZIP
    zi.date_time = (1980, 1, 1, 0, 0, 0)
    zi.compress_type = zipfile.ZIP_DEFLATED
    zf.writestr(zi, data)

    return video, video_music, video_final

def _zip_add_deterministic(zf, file_path: Path, arcname: str):
    data = file_path.read_bytes()
    zi = zipfile.ZipInfo(arcname)
    # timestamp fijo (1980-01-01 00:00:00) -> determinista en ZIP
    zi.date_time = (1980, 1, 1, 0, 0, 0)
    zi.compress_type = zipfile.ZIP_DEFLATED
    zf.writestr(zi, data)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack-dir", required=True)
    ap.add_argument("--auto-music", action="store_true")
    ap.add_argument("--music-dir", default="music")
    ap.add_argument("--python-exe", default=sys.executable)
    args = ap.parse_args()

def _zip_add_deterministic(zf, file_path: Path, arcname: str):
    data = file_path.read_bytes()
    zi = zipfile.ZipInfo(arcname)
    # timestamp fijo (1980-01-01 00:00:00) -> determinista en ZIP
    zi.date_time = (1980, 1, 1, 0, 0, 0)
    zi.compress_type = zipfile.ZIP_DEFLATED
    zf.writestr(zi, data)

    pack_dir = Path(args.pack_dir).expanduser().resolve()
    if not pack_dir.exists() or not pack_dir.is_dir():
        raise SystemExit(f"ERROR: pack-dir invalido: {pack_dir}")
    if not (pack_dir / "pack.json").exists():
        raise SystemExit(f"ERROR: no existe pack.json en: {pack_dir}")

def _zip_add_deterministic(zf, file_path: Path, arcname: str):
    data = file_path.read_bytes()
    zi = zipfile.ZipInfo(arcname)
    # timestamp fijo (1980-01-01 00:00:00) -> determinista en ZIP
    zi.date_time = (1980, 1, 1, 0, 0, 0)
    zi.compress_type = zipfile.ZIP_DEFLATED
    zf.writestr(zi, data)

    produce_delivery_videos(pack_dir, args.python_exe, bool(args.auto_music), str(args.music_dir))

def _zip_add_deterministic(zf, file_path: Path, arcname: str):
    data = file_path.read_bytes()
    zi = zipfile.ZipInfo(arcname)
    # timestamp fijo (1980-01-01 00:00:00) -> determinista en ZIP
    zi.date_time = (1980, 1, 1, 0, 0, 0)
    zi.compress_type = zipfile.ZIP_DEFLATED
    zf.writestr(zi, data)

    zip_path = pack_dir.parent / f"{pack_dir.name}.final_delivery.zip"
    make_deterministic_zip(pack_dir, zip_path)
    sha_path = write_sha_file(zip_path)
    zip_sha = sha_path.read_text(encoding="ascii").split("  ", 1)[0].strip().lower()
    handoff = write_handoff_ready(pack_dir, zip_path, zip_sha, bool(args.auto_music))

def _zip_add_deterministic(zf, file_path: Path, arcname: str):
    data = file_path.read_bytes()
    zi = zipfile.ZipInfo(arcname)
    # timestamp fijo (1980-01-01 00:00:00) -> determinista en ZIP
    zi.date_time = (1980, 1, 1, 0, 0, 0)
    zi.compress_type = zipfile.ZIP_DEFLATED
    zf.writestr(zi, data)

    print("OK: finalize handoff")
    print("PACK_DIR:", str(pack_dir))
    print("VIDEO_BASE:", str(pack_dir / "video.mp4"))
    print("VIDEO_MUSIC_AUTO:", str(pack_dir / "video_music_auto.mp4"))
    print("VIDEO_FINAL:", str(pack_dir / "video_final.mp4"))
    print("ZIP:", str(zip_path))
    print("ZIP_SHA256_FILE:", str(sha_path))
    print("HANDOFF_READY:", str(handoff))
    return 0

def _zip_add_deterministic(zf, file_path: Path, arcname: str):
    data = file_path.read_bytes()
    zi = zipfile.ZipInfo(arcname)
    # timestamp fijo (1980-01-01 00:00:00) -> determinista en ZIP
    zi.date_time = (1980, 1, 1, 0, 0, 0)
    zi.compress_type = zipfile.ZIP_DEFLATED
    zf.writestr(zi, data)


if __name__ == "__main__":
    raise SystemExit(main())

def _zip_add_deterministic(zf, file_path: Path, arcname: str):
    data = file_path.read_bytes()
    zi = zipfile.ZipInfo(arcname)
    # timestamp fijo (1980-01-01 00:00:00) -> determinista en ZIP
    zi.date_time = (1980, 1, 1, 0, 0, 0)
    zi.compress_type = zipfile.ZIP_DEFLATED
    zf.writestr(zi, data)



