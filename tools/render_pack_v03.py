# -*- coding: utf-8 -*-
"""Renderiza un pack exportado (pack_v03_*) a video.mp4 usando FFmpeg.

Compat:
- pack con scenes[] (pack.json): renderiza segmentos y concatena (modo principal)
- pack sin scenes[]:
  - intenta derivar escenas desde manifest_v03.json (scenes_v03 o scenes)
  - si no, usa artifacts/image.png + artifacts/audio.wav

Determinista:
- args list (sin shell), -map_metadata/-map_chapters a -1
- no depende del orden del FS: orden por index asc
"""
from __future__ import annotations

import argparse
import os
import json
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import List, Tuple, Dict, Any

def _vf(w: int, h: int, fit: str) -> str:
    if fit == "contain":
        return (
            f"scale={w}:{h}:force_original_aspect_ratio=decrease,"
            f"pad={w}:{h}:(ow-iw)/2:(oh-ih)/2,format=yuv420p"
        )
    return f"scale={w}:{h}:force_original_aspect_ratio=increase,crop={w}:{h},format=yuv420p"

def _overlay_drawtext_for_scene(scene: dict, w: int, h: int, tmp_dir: Path | None = None) -> str:
    """Devuelve 'drawtext=...' o '' si no hay texto (usa tools/build_drawtext_filter.py)."""
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            suffix=".json",
            delete=False,
            encoding="utf-8",
            dir=str(tmp_dir) if tmp_dir else None,
        ) as tf:
            json.dump(scene, tf, ensure_ascii=False)
            tmp_json = tf.name

        default_fontfile = "C:/Windows/Fonts/arial.ttf" if os.name == "nt" else ""
        fontfile = os.environ.get("STUDIO_FONTFILE", default_fontfile).strip()

        cmd = [
            "python",
            str(Path(__file__).parent / "build_drawtext_filter.py"),
            "--scene-json", tmp_json,
            "--w", str(w),
            "--h", str(h),
            "--fontfile", fontfile,
        ]
        out = subprocess.check_output(cmd, text=True, stderr=subprocess.STDOUT).strip()
        return out
    except Exception:
        return ""
    finally:
        try:
            if "tmp_json" in locals() and tmp_json:
                Path(tmp_json).unlink(missing_ok=True)
        except Exception:
            pass

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
    p = Path(str(rel or ""))
    return p if p.is_absolute() else (pack_dir / p)

def _scene_dir(pack_dir: Path, idx: int) -> Path:
    return pack_dir / "artifacts" / "scenes" / f"scene_{idx:02d}"

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

def _scenes_from_manifest(pack_dir: Path, manifest: Dict[str, Any]) -> List[Dict[str, Any]]:
    """
    Deriva una lista de escenas renderizables desde manifest_v03.json.
    Output scenes: [{index,image,audio, ...campos_texto...}]
    - Prioridad: scenes_v03 (assets.image + assets.audio_clip)
    - Fallback : scenes (legacy) con artifacts
    - Fallback final: artifacts/scenes/scene_XX/{image.png,audio.wav}
    """
    out: List[Dict[str, Any]] = []

    # 1) scenes_v03
    sv03 = manifest.get("scenes_v03")
    if isinstance(sv03, list) and sv03:
        for i, row in enumerate([dict(r or {}) for r in sv03 if isinstance(r, dict)]):
            idx = _coerce_int(row.get("index", i), i)
            # En pipeline actual index es 0-based; para render preferimos 1..N
            idx1 = idx + 1 if idx <= 0 else idx
            assets = dict(row.get("assets") or {})
            img_rel = str(assets.get("image") or "")
            aud_rel = str(assets.get("audio_clip") or "")
            # Fallback a estructura estable del pack si no resolve
            img = _resolve(pack_dir, img_rel)
            aud = _resolve(pack_dir, aud_rel)
            if not img.exists():
                img = _scene_dir(pack_dir, idx1) / "image.png"
            if not aud.exists():
                aud = _scene_dir(pack_dir, idx1) / "audio.wav"

            scene = {
                "index": idx1,
                "text": row.get("script_text", "") or row.get("text", ""),
                "narration": row.get("script_text", "") or row.get("narration", "") or row.get("text", ""),
                "onscreen": row.get("onscreen", "") or "",
                "stock_query": row.get("image_query", "") or "",
                "image": str(img.relative_to(pack_dir).as_posix()) if img.is_absolute() else str(img),
                "audio": str(aud.relative_to(pack_dir).as_posix()) if aud.is_absolute() else str(aud),
            }
            out.append(scene)

    # 2) scenes legacy
    if not out:
        slegacy = manifest.get("scenes")
        if isinstance(slegacy, list) and slegacy:
            for row in [dict(r or {}) for r in slegacy if isinstance(r, dict)]:
                idx1 = _coerce_int(row.get("index", 0), 0)
                if idx1 <= 0:
                    continue
                arts = dict(row.get("artifacts") or {})
                img_rel = str(arts.get("image") or "")
                aud_rel = str(arts.get("audio") or "")
                img = _resolve(pack_dir, img_rel)
                aud = _resolve(pack_dir, aud_rel)
                if not img.exists():
                    img = _scene_dir(pack_dir, idx1) / "image.png"
                if not aud.exists():
                    aud = _scene_dir(pack_dir, idx1) / "audio.wav"

                scene = {
                    "index": idx1,
                    "text": row.get("narration") or row.get("audio_text") or row.get("text", ""),
                    "narration": row.get("narration", "") or row.get("audio_text", "") or row.get("text", ""),
                    "onscreen": row.get("onscreen", "") or "",
                    "stock_query": row.get("stock_query", "") or "",
                    "image": str(img.relative_to(pack_dir).as_posix()) if img.is_absolute() else str(img),
                    "audio": str(aud.relative_to(pack_dir).as_posix()) if aud.is_absolute() else str(aud),
                }
                out.append(scene)

    # Orden estable por index
    out = [s for s in out if _coerce_int(s.get("index", 0), 0) > 0]
    out.sort(key=lambda x: _coerce_int(x.get("index", 0), 0))
    return out

def _make_segment(
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
    vf_override: str = "",
) -> None:
    cmd: List[str] = [ffmpeg, "-hide_banner", "-loglevel", loglevel, "-y"]
    if stats:
        cmd.append("-stats")

    vf = vf_override or _vf(w, h, fit)

    cmd += [
        "-loop","1","-i",str(img),
        "-i",str(aud),
        "-vf",vf,
        "-r",str(fps),
        "-c:v","libx264","-pix_fmt","yuv420p","-preset",preset,"-crf",str(crf),
        "-c:a","aac","-b:a",abitrate,"-ar","44100","-ac","2",
        "-shortest","-movflags","+faststart",
        "-map_metadata","-1","-map_chapters","-1",
        str(out_mp4),
    ]
    print("FFMPEG:", _pretty(cmd))
    subprocess.check_call(cmd)

def _concat(ffmpeg: str, segs: List[Path], out_mp4: Path, loglevel: str, stats: bool) -> None:
    # concat demuxer (determinista)
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
        "-f","concat","-safe","0","-i",str(lst),
        "-c","copy",
        "-movflags","+faststart",
        "-map_metadata","-1","-map_chapters","-1",
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
    ap.add_argument("--fit", choices=("crop","contain"), default="crop")
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
    scenes = meta.get("scenes") if isinstance(meta.get("scenes"), list) else []

    # NUEVO: si pack.json no tiene scenes[], intentamos derivar desde manifest_v03.json / carpeta estable
    if not scenes:
        manifest = _try_read_manifest(pack_dir)
        derived = _scenes_from_manifest(pack_dir, manifest) if manifest else []
        scenes = derived

    tmp_root = pack_dir / "_tmp_render"
    tmp_root.mkdir(parents=True, exist_ok=True)
    tmp_dir = Path(tempfile.mkdtemp(prefix="studio_pack_render_", dir=str(tmp_root)))
    try:
        if scenes:
            segs: List[Path] = []
            for s in scenes:
                idx = _coerce_int(s.get("index", 0), 0)
                img = _resolve(pack_dir, str(s.get("image", "")))
                aud = _resolve(pack_dir, str(s.get("audio", "")))

                vf = _vf(args.w, args.h, args.fit)
                dt = _overlay_drawtext_for_scene(s, args.w, args.h, tmp_dir)
                if dt:
                    vf = vf + "," + dt

                if not (img.exists() and aud.exists()):
                    raise SystemExit(f"ERROR: escena {idx} missing: image={img.exists()} audio={aud.exists()}")

                seg = tmp_dir / f"seg_{idx:02d}.mp4"
                _make_segment(
                    args.ffmpeg, img, aud, seg,
                    args.w, args.h, args.fps, args.fit,
                    args.crf, args.preset, args.audio_bitrate,
                    args.loglevel, args.stats, vf
                )
                segs.append(seg)
            _concat(args.ffmpeg, segs, out, args.loglevel, args.stats)
        else:
            img = pack_dir / "artifacts" / "image.png"
            aud = pack_dir / "artifacts" / "audio.wav"
            if not img.exists(): raise SystemExit(f"ERROR: falta image: {img}")
            if not aud.exists(): raise SystemExit(f"ERROR: falta audio: {aud}")
            _make_segment(
                args.ffmpeg, img, aud, out,
                args.w, args.h, args.fps, args.fit,
                args.crf, args.preset, args.audio_bitrate,
                args.loglevel, args.stats
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
