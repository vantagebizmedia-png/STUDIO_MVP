# -*- coding: utf-8 -*-
"""Renderiza un pack exportado (pack_v03_*) a video.mp4 usando FFmpeg.

def _detect_subtitles_srt(pack_dir: str) -> str:
    try:
        import os, json
        pd = os.path.abspath(pack_dir or "")
        if not pd or not os.path.isdir(pd):
            return ""
        # 1) si existe directo
        direct = os.path.join(pd, "subtitles.srt")
        if os.path.exists(direct):
            return direct
        # 2) si manifest tiene artifacts.subtitles
        mf = os.path.join(pd, "manifest_v03.json")
        if os.path.exists(mf):
            m = json.loads(open(mf, "r", encoding="utf-8").read())
            sub = ((m.get("artifacts") or {}).get("subtitles") or "").strip()
            if sub:
                cand = os.path.join(pd, sub)
                if os.path.exists(cand):
                    return cand
        # 3) si pack.json tiene source/paths (o scenes) - best effort
        pj = os.path.join(pd, "pack.json")
        if os.path.exists(pj):
            p = json.loads(open(pj, "r", encoding="utf-8").read())
            # algunos packs podrían guardar ruta directa
            sub = (p.get("subtitles") or "").strip()
            if sub:
                cand = os.path.join(pd, sub)
                if os.path.exists(cand):
                    return cand
        return ""
    except Exception:
        return ""
Compat:
- pack sin scenes: usa artifacts/image.png + artifacts/audio.wav
- pack con scenes[] (pack.json): renderiza segmentos y concatena

Determinista:
- args list (sin shell), -map_metadata/-map_chapters a -1
"""
from __future__ import annotations

import argparse
import os
import json
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import List

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

def _run(cmd: List[str]) -> None:
    print("FFMPEG:", _pretty(cmd))
    p = subprocess.run(cmd)
    if p.returncode != 0:
        raise SystemExit(p.returncode)

def _read_pack(pack_dir: Path) -> dict:
    p = pack_dir / "pack.json"
    if not p.exists():
        raise SystemExit(f"ERROR: no existe pack.json en: {pack_dir}")
    return json.loads(p.read_text(encoding="utf-8"))

def _resolve(pack_dir: Path, rel: str) -> Path:
    p = Path(rel)
    return p if p.is_absolute() else (pack_dir / p)

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
        # ffmpeg concat list prefiere paths con /
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






def _ffmpeg_subtitles_path(p: Path) -> str:
    # Similar a tools/burn_subtitles.py
    s = str(p.resolve()).replace("\\", "/")
    # Escapa "C:" -> "C\:" para el filtro subtitles
    if len(s) >= 2 and s[1] == ":":
        s = s[0] + "\\:" + s[2:]
    return s



def _burn_subtitles_from_pack(
    ffmpeg: str,
    pack_dir: Path,
    video_in: Path,
    video_out: Path,
    crf: str,
    preset: str,
    audio_bitrate: str,
    loglevel: str,
    stats: bool,

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

    tmp_root = pack_dir / "_tmp_render"
    tmp_root.mkdir(parents=True, exist_ok=True)
    tmp_dir = Path(tempfile.mkdtemp(prefix="studio_pack_render_", dir=str(tmp_root)))
    try:
        if scenes:
            segs: List[Path] = []
            for s in scenes:
                idx = int(s.get("index", 0) or 0)
                img = _resolve(pack_dir, str(s.get("image", "")))
                aud = _resolve(pack_dir, str(s.get("audio", "")))
                vf = _vf(args.w, args.h, args.fit)
                dt = _overlay_drawtext_for_scene(s, args.w, args.h, tmp_dir)
                if dt:
                    vf = vf + "," + dt
                if not (img.exists() and aud.exists()):
                    raise SystemExit(f"ERROR: escena {idx} missing: image={img.exists()} audio={aud.exists()}")
                seg = tmp_dir / f"seg_{idx:02d}.mp4"
                _make_segment(args.ffmpeg, img, aud, seg, args.w, args.h, args.fps, args.fit,
                              args.crf, args.preset, args.audio_bitrate, args.loglevel, args.stats, vf)
                segs.append(seg)
            _concat(args.ffmpeg, segs, out, args.loglevel, args.stats)
        else:
            img = pack_dir / "artifacts" / "image.png"
            aud = pack_dir / "artifacts" / "audio.wav"
            if not img.exists(): raise SystemExit(f"ERROR: falta image: {img}")
            if not aud.exists(): raise SystemExit(f"ERROR: falta audio: {aud}")
            _make_segment(args.ffmpeg, img, aud, out, args.w, args.h, args.fps, args.fit,
                          args.crf, args.preset, args.audio_bitrate, args.loglevel, args.stats)

        if out.exists():
            # Burn-in subtitles (si existe pack_dir/subtitles.srt)
            try:
                if "_burn_subtitles_from_pack" in globals():
                    out_sub = out.with_name("video_subtitles.mp4")
                    if _burn_subtitles_from_pack(
                        args.ffmpeg, pack_dir, out, out_sub,
                        args.crf, args.preset, args.audio_bitrate,
                        args.loglevel, args.stats,
                    ):
                        print("OK: video_subtitles creado")
                        print(f"VIDEO_SUBTITLES: {out_sub}")
                else:
                    print("WARNING: burn subtitles skipped: helper not defined")
            except Exception as e:
                print(f"WARNING: burn subtitles failed: {e}")
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

) -> bool:
    srt = pack_dir / "subtitles.srt"
    if not srt.exists():
        return False

    sub_path = _ffmpeg_subtitles_path(srt)
    vf = (
        f"subtitles='{sub_path}':charenc=UTF-8:"
        f"force_style='FontName=Arial,FontSize=20,Outline=2,Shadow=0,MarginV=28,Alignment=2'"
    )

    cmd: List[str] = [ffmpeg, "-hide_banner", "-loglevel", loglevel, "-y"]
    if stats:
        cmd.append("-stats")

    cmd += [
        "-i", str(video_in),
        "-vf", vf,
        "-c:v", "libx264",
        "-pix_fmt", "yuv420p",
        "-preset", str(preset),
        "-crf", str(crf),
        "-c:a", "aac",
        "-b:a", str(audio_bitrate),
        "-movflags", "+faststart",
        "-map_metadata", "-1",
        "-map_chapters", "-1",
        str(video_out),
    ]

    print("FFMPEG:", _pretty(cmd))
    subprocess.check_call(cmd)
    return True







if __name__ == "__main__":
    raise SystemExit(main())











