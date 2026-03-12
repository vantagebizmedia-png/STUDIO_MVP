# -*- coding: utf-8 -*-
"""Renderiza un pack exportado (pack_v03_*) a video.mp4 usando FFmpeg.

Compat:
- prioriza manifest_v03.json si puede derivar escenas renderizables desde scenes_v03/scenes
- fallback a pack.json (scenes[])
- fallback final: artifacts/image.png + artifacts/audio.wav

Soporte visual:
- image  -> segmento con imagen fija + audio
- video  -> segmento con video loop + audio externo

Determinista:
- args list (sin shell), -map_metadata/-map_chapters a -1
- no depende del orden del FS: orden por index asc

IMPORTANTE:
- video.mp4 sale LIMPIO (sin drawtext / sin burn-in)
- subtítulos se manejan fuera de este renderer
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Optional


def _vf(w: int, h: int, fit: str) -> str:
    if fit == "contain":
        return (
            f"scale={w}:{h}:force_original_aspect_ratio=decrease,"
            f"pad={w}:{h}:(ow-iw)/2:(oh-ih)/2,format=yuv420p"
        )
    return f"scale={w}:{h}:force_original_aspect_ratio=increase,crop={w}:{h},format=yuv420p"


def _pretty(cmd: List[str]) -> str:
    try:
        return subprocess.list2cmdline([str(x) for x in cmd])
    except Exception:
        return " ".join(str(x) for x in cmd)


def _read_pack(pack_dir: Path) -> dict:
    p = pack_dir / "pack.json"
    if not p.exists():
        raise SystemExit(f"ERROR: no existe pack.json en: {pack_dir}")
    return json.loads(p.read_text(encoding="utf-8"))


def _resolve(pack_dir: Path, rel: str) -> Path:
    p = Path(str(rel or "")).expanduser()
    return p if p.is_absolute() else (pack_dir / p)


def _scene_dir(pack_dir: Path, idx1: int) -> Path:
    return pack_dir / "artifacts" / "scenes" / f"scene_{idx1:02d}"


def _try_read_manifest(pack_dir: Path) -> Dict[str, Any]:
    mp = pack_dir / "manifest_v03.json"
    if not mp.exists():
        return {}
    try:
        return json.loads(mp.read_text(encoding="utf-8"))
    except Exception:
        return {}


def _coerce_int(x: object, default: int = 0) -> int:
    try:
        return int(x)  # type: ignore[arg-type]
    except Exception:
        return default


def _asset_value(value: Any) -> str:
    if value is None:
        return ""

    if isinstance(value, str):
        return value.strip()

    if isinstance(value, dict):
        return _asset_value(value.get("path"))

    if isinstance(value, (list, tuple)) and value:
        return _asset_value(value[0])

    return ""


def _pack_rel(pack_dir: Path, p: Optional[Path]) -> str:
    if p is None:
        return ""
    try:
        return str(p.resolve().relative_to(pack_dir.resolve()).as_posix())
    except Exception:
        return str(p)


def _first_existing(candidates: List[Path]) -> Optional[Path]:
    seen = set()
    first: Optional[Path] = None

    for c in candidates:
        key = str(c)
        if key in seen:
            continue
        seen.add(key)

        if first is None:
            first = c

        if c.exists():
            return c

    return first


def _candidate_image_paths(pack_dir: Path, idx1: int, explicit_rel: str) -> List[Path]:
    scene_dir = _scene_dir(pack_dir, idx1)
    out: List[Path] = []

    if explicit_rel:
        out.append(_resolve(pack_dir, explicit_rel))

    for name in ("image.png", "image.jpg", "image.jpeg", "image.webp"):
        out.append(scene_dir / name)

    for name in ("image.png", "image.jpg", "image.jpeg", "image.webp"):
        out.append(pack_dir / "artifacts" / name)

    return out


def _candidate_video_paths(pack_dir: Path, idx1: int, explicit_rel: str) -> List[Path]:
    scene_dir = _scene_dir(pack_dir, idx1)
    out: List[Path] = []

    if explicit_rel:
        out.append(_resolve(pack_dir, explicit_rel))

    for name in ("video.mp4", "video.mov", "video.webm"):
        out.append(scene_dir / name)

    return out


def _candidate_audio_paths(pack_dir: Path, idx1: int, explicit_rel: str) -> List[Path]:
    scene_dir = _scene_dir(pack_dir, idx1)
    out: List[Path] = []

    if explicit_rel:
        out.append(_resolve(pack_dir, explicit_rel))

    out.append(pack_dir / "artifacts" / f"audio_s{idx1:02d}.wav")
    out.append(pack_dir / "assets" / "audio_clips" / f"s{idx1:02d}.wav")
    out.append(scene_dir / "audio.wav")
    out.append(pack_dir / "artifacts" / "audio.wav")

    return out


def _ordinal_from_id(value: Any) -> int:
    s = str(value or "").strip()
    m = re.match(r"^scene_(\d+)$", s, re.IGNORECASE)
    if not m:
        return 0
    return _coerce_int(m.group(1), 0)


def _resolve_visual_kind(raw_kind: str, has_image: bool, has_video: bool) -> str:
    vk = str(raw_kind or "").strip().lower()

    if vk == "video" and has_video:
        return "video"
    if has_image:
        return "image"
    if has_video:
        return "video"
    return "image"


def _scene_from_v03_row(pack_dir: Path, row: Dict[str, Any], ordinal: int) -> Dict[str, Any]:
    idx1 = _ordinal_from_id(row.get("id"))
    if idx1 <= 0:
        idx0 = _coerce_int(row.get("index", ordinal - 1), ordinal - 1)
        if idx0 < 0:
            idx0 = ordinal - 1
        idx1 = idx0 + 1

    assets_obj = row.get("assets") if isinstance(row.get("assets"), dict) else {}
    assets = dict(assets_obj or {})

    img = _first_existing(_candidate_image_paths(pack_dir, idx1, _asset_value(assets.get("image"))))
    vid = _first_existing(_candidate_video_paths(pack_dir, idx1, _asset_value(assets.get("video"))))
    aud = _first_existing(_candidate_audio_paths(pack_dir, idx1, _asset_value(assets.get("audio_clip"))))

    has_image = img is not None and img.exists()
    has_video = vid is not None and vid.exists()
    vk = _resolve_visual_kind(str(row.get("visual_kind", "")), has_image, has_video)

    return {
        "index": idx1,
        "image": _pack_rel(pack_dir, img),
        "video": _pack_rel(pack_dir, vid),
        "audio": _pack_rel(pack_dir, aud),
        "visual_kind": vk,
    }


def _scene_from_legacy_row(pack_dir: Path, row: Dict[str, Any], ordinal: int) -> Dict[str, Any]:
    idx1 = _ordinal_from_id(row.get("id"))
    if idx1 <= 0:
        idx1 = _coerce_int(row.get("index", ordinal), ordinal)
        if idx1 <= 0:
            idx1 = ordinal

    arts_obj = row.get("artifacts") if isinstance(row.get("artifacts"), dict) else {}
    arts = dict(arts_obj or {})

    img_rel = _asset_value(row.get("image")) or _asset_value(arts.get("image"))
    vid_rel = _asset_value(row.get("video")) or _asset_value(arts.get("video"))
    aud_rel = _asset_value(row.get("audio")) or _asset_value(arts.get("audio"))

    img = _first_existing(_candidate_image_paths(pack_dir, idx1, img_rel))
    vid = _first_existing(_candidate_video_paths(pack_dir, idx1, vid_rel))
    aud = _first_existing(_candidate_audio_paths(pack_dir, idx1, aud_rel))

    has_image = img is not None and img.exists()
    has_video = vid is not None and vid.exists()
    vk = _resolve_visual_kind(str(row.get("visual_kind", "")), has_image, has_video)

    return {
        "index": idx1,
        "image": _pack_rel(pack_dir, img),
        "video": _pack_rel(pack_dir, vid),
        "audio": _pack_rel(pack_dir, aud),
        "visual_kind": vk,
    }


def _normalize_pack_scenes(pack_dir: Path, scenes_raw: Any) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []

    if not isinstance(scenes_raw, list):
        return out

    for ordinal, raw in enumerate(scenes_raw, start=1):
        if not isinstance(raw, dict):
            continue

        row = dict(raw or {})
        idx1 = _ordinal_from_id(row.get("id"))
        if idx1 <= 0:
            idx1 = _coerce_int(row.get("index", ordinal), ordinal)
            if idx1 <= 0:
                idx1 = ordinal

        img = _first_existing(_candidate_image_paths(pack_dir, idx1, _asset_value(row.get("image"))))
        vid = _first_existing(_candidate_video_paths(pack_dir, idx1, _asset_value(row.get("video"))))
        aud = _first_existing(_candidate_audio_paths(pack_dir, idx1, _asset_value(row.get("audio"))))

        has_image = img is not None and img.exists()
        has_video = vid is not None and vid.exists()
        vk = _resolve_visual_kind(str(row.get("visual_kind", "")), has_image, has_video)

        out.append({
            "index": idx1,
            "image": _pack_rel(pack_dir, img),
            "video": _pack_rel(pack_dir, vid),
            "audio": _pack_rel(pack_dir, aud),
            "visual_kind": vk,
        })

    out = [s for s in out if _coerce_int(s.get("index", 0), 0) > 0]
    out.sort(key=lambda x: _coerce_int(x.get("index", 0), 0))
    return out


def _scenes_from_manifest(pack_dir: Path, manifest: Dict[str, Any]) -> List[Dict[str, Any]]:
    """
    Deriva una lista de escenas renderizables desde manifest_v03.json.

    Output scenes:
    [{index,image,video,audio,visual_kind}]

    Prioridad:
    - scenes_v03 (assets.image / assets.video / assets.audio_clip)
    - scenes legacy
    """
    out: List[Dict[str, Any]] = []

    sv03 = manifest.get("scenes_v03")
    if isinstance(sv03, list) and sv03:
        for ordinal, raw in enumerate(sv03, start=1):
            if not isinstance(raw, dict):
                continue
            out.append(_scene_from_v03_row(pack_dir, dict(raw or {}), ordinal))

    if not out:
        slegacy = manifest.get("scenes")
        if isinstance(slegacy, list) and slegacy:
            for ordinal, raw in enumerate(slegacy, start=1):
                if not isinstance(raw, dict):
                    continue
                out.append(_scene_from_legacy_row(pack_dir, dict(raw or {}), ordinal))

    out = [s for s in out if _coerce_int(s.get("index", 0), 0) > 0]
    out.sort(key=lambda x: _coerce_int(x.get("index", 0), 0))
    return out


def _make_image_segment(
    ffmpeg: str,
    img: Path,
    aud: Path,
    out_mp4: Path,
    w: int,
    h: int,
    fps: int,
    fit: str,
    crf: int,
    preset: str,
    abitrate: str,
    loglevel: str,
    stats: bool,
) -> None:
    cmd: List[str] = [ffmpeg, "-hide_banner", "-loglevel", loglevel, "-y"]
    if stats:
        cmd.append("-stats")

    vf = _vf(w, h, fit)

    cmd += [
        "-loop", "1", "-i", str(img),
        "-i", str(aud),
        "-vf", vf,
        "-r", str(fps),
        "-map", "0:v:0",
        "-map", "1:a:0",
        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-preset", preset, "-crf", str(crf),
        "-c:a", "aac", "-b:a", abitrate, "-ar", "44100", "-ac", "2",
        "-shortest", "-movflags", "+faststart",
        "-map_metadata", "-1", "-map_chapters", "-1",
        str(out_mp4),
    ]
    print("FFMPEG:", _pretty(cmd))
    subprocess.check_call(cmd)


def _make_video_segment(
    ffmpeg: str,
    vid: Path,
    aud: Path,
    out_mp4: Path,
    w: int,
    h: int,
    fps: int,
    fit: str,
    crf: int,
    preset: str,
    abitrate: str,
    loglevel: str,
    stats: bool,
) -> None:
    cmd: List[str] = [ffmpeg, "-hide_banner", "-loglevel", loglevel, "-y"]
    if stats:
        cmd.append("-stats")

    vf = _vf(w, h, fit)

    cmd += [
        "-stream_loop", "-1", "-i", str(vid),
        "-i", str(aud),
        "-vf", vf,
        "-r", str(fps),
        "-map", "0:v:0",
        "-map", "1:a:0",
        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-preset", preset, "-crf", str(crf),
        "-c:a", "aac", "-b:a", abitrate, "-ar", "44100", "-ac", "2",
        "-shortest", "-movflags", "+faststart",
        "-map_metadata", "-1", "-map_chapters", "-1",
        str(out_mp4),
    ]
    print("FFMPEG:", _pretty(cmd))
    subprocess.check_call(cmd)


def _make_segment(
    ffmpeg: str,
    visual_kind: str,
    img: Optional[Path],
    vid: Optional[Path],
    aud: Path,
    out_mp4: Path,
    w: int,
    h: int,
    fps: int,
    fit: str,
    crf: int,
    preset: str,
    abitrate: str,
    loglevel: str,
    stats: bool,
) -> None:
    has_image = img is not None and img.exists()
    has_video = vid is not None and vid.exists()
    kind = _resolve_visual_kind(visual_kind, has_image, has_video)

    if not aud.exists():
        raise SystemExit(f"ERROR: falta audio: {aud}")

    if kind == "video":
        if vid is None or not vid.exists():
            raise SystemExit(f"ERROR: escena video sin archivo real: {vid}")
        _make_video_segment(
            ffmpeg, vid, aud, out_mp4,
            w, h, fps, fit, crf, preset, abitrate, loglevel, stats
        )
        return

    if img is None or not img.exists():
        raise SystemExit(f"ERROR: escena image sin archivo real: {img}")
    _make_image_segment(
        ffmpeg, img, aud, out_mp4,
        w, h, fps, fit, crf, preset, abitrate, loglevel, stats
    )


def _concat(ffmpeg: str, segs: List[Path], out_mp4: Path, loglevel: str, stats: bool) -> None:
    lst = out_mp4.parent / "_concat_list.txt"
    lines = []
    for p in segs:
        s = str(p.resolve()).replace("\\", "/").replace("'", "\\'")
        lines.append(f"file '{s}'")
    lst.write_text("\n".join(lines) + "\n", encoding="utf-8")

    cmd: List[str] = [ffmpeg, "-hide_banner", "-loglevel", loglevel, "-y"]
    if stats:
        cmd.append("-stats")

    cmd += [
        "-f", "concat", "-safe", "0", "-i", str(lst),
        "-c", "copy",
        "-movflags", "+faststart",
        "-map_metadata", "-1", "-map_chapters", "-1",
        str(out_mp4),
    ]
    print("FFMPEG:", _pretty(cmd))
    subprocess.check_call(cmd)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack-dir", required=True)
    ap.add_argument("--out", default="")
    ap.add_argument("--w", type=int, default=1080)
    ap.add_argument("--h", type=int, default=1920)
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--fit", choices=("crop", "contain"), default="crop")
    ap.add_argument("--crf", type=int, default=18)
    ap.add_argument("--preset", default="medium")
    ap.add_argument("--audio-bitrate", default="192k")
    ap.add_argument("--ffmpeg", default="ffmpeg")
    ap.add_argument("--loglevel", default="error")
    ap.add_argument("--stats", action="store_true")
    ap.add_argument("--keep-tmp", action="store_true")
    args = ap.parse_args()

    pack_dir = Path(args.pack_dir).expanduser().resolve()
    if not pack_dir.exists():
        raise SystemExit(f"ERROR: pack_dir no existe: {pack_dir}")

    out = Path(args.out).expanduser() if args.out else (pack_dir / "video.mp4")
    out = out.resolve()
    out.parent.mkdir(parents=True, exist_ok=True)

    meta = _read_pack(pack_dir)
    pack_scenes = _normalize_pack_scenes(pack_dir, meta.get("scenes"))

    manifest = _try_read_manifest(pack_dir)
    manifest_scenes = _scenes_from_manifest(pack_dir, manifest) if manifest else []

    scenes = manifest_scenes if manifest_scenes else pack_scenes

    tmp_root = pack_dir / "_tmp_render"
    tmp_root.mkdir(parents=True, exist_ok=True)
    tmp_dir = Path(tempfile.mkdtemp(prefix="studio_pack_render_", dir=str(tmp_root)))

    try:
        if scenes:
            segs: List[Path] = []

            for ordinal, s in enumerate(scenes, start=1):
                idx = _coerce_int(s.get("index", ordinal), ordinal)
                if idx <= 0:
                    idx = ordinal

                img_rel = _asset_value(s.get("image"))
                vid_rel = _asset_value(s.get("video"))
                aud_rel = _asset_value(s.get("audio"))
                raw_kind = str(s.get("visual_kind", ""))

                img = _resolve(pack_dir, img_rel) if img_rel else None
                vid = _resolve(pack_dir, vid_rel) if vid_rel else None
                aud = _resolve(pack_dir, aud_rel) if aud_rel else (pack_dir / "artifacts" / "audio.wav")

                has_image = img is not None and img.exists()
                has_video = vid is not None and vid.exists()
                kind = _resolve_visual_kind(raw_kind, has_image, has_video)

                if not aud.exists():
                    raise SystemExit(
                        f"ERROR: escena {idx} missing audio: audio={aud}"
                    )

                if kind == "video":
                    if vid is None or not vid.exists():
                        raise SystemExit(
                            f"ERROR: escena {idx} missing video: visual_kind=video image={has_image} video={has_video}"
                        )
                else:
                    if img is None or not img.exists():
                        raise SystemExit(
                            f"ERROR: escena {idx} missing image: visual_kind=image image={has_image} video={has_video}"
                        )

                seg = tmp_dir / f"seg_{idx:02d}.mp4"
                _make_segment(
                    args.ffmpeg,
                    kind,
                    img,
                    vid,
                    aud,
                    seg,
                    args.w,
                    args.h,
                    args.fps,
                    args.fit,
                    args.crf,
                    args.preset,
                    args.audio_bitrate,
                    args.loglevel,
                    args.stats,
                )
                segs.append(seg)

            _concat(args.ffmpeg, segs, out, args.loglevel, args.stats)
        else:
            img = pack_dir / "artifacts" / "image.png"
            aud = pack_dir / "artifacts" / "audio.wav"
            if not img.exists():
                raise SystemExit(f"ERROR: falta image: {img}")
            if not aud.exists():
                raise SystemExit(f"ERROR: falta audio: {aud}")

            _make_image_segment(
                args.ffmpeg,
                img,
                aud,
                out,
                args.w,
                args.h,
                args.fps,
                args.fit,
                args.crf,
                args.preset,
                args.audio_bitrate,
                args.loglevel,
                args.stats,
            )

        if out.exists():
            print("OK: video creado")
            print("VIDEO:", str(out))
            print("BYTES:", out.stat().st_size)
            return 0

        raise SystemExit("ERROR: no se generó output")
    finally:
        if args.keep_tmp:
            print("TMP (keep):", str(tmp_dir))
        else:
            shutil.rmtree(tmp_dir, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())