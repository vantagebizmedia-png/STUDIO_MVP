# -*- coding: utf-8 -*-
# app/video_render.py  Render slideshow 9:16 con audio por escena + música opcional
#
# Motion Engine determinista:
#   - zoom: slow_zoom_in / slow_zoom_out
#   - pan:  pan_left / pan_right / pan_up / pan_down
# Soporta motion_profile por escena + motion_strength por escena.
#
# Extras deterministas:
#   - micro-jitter (handheld) por escena (MoviePy)
#   - film grain + vignette aplicados por FFmpeg (-vf) (más rápido que Python)
#
# Cache por hash con compat:
#   - motion_strength (scalar) + motion_strengths (solo si varía)
#   - jitter_* solo si jitter_px > 0
#   - grain_amount solo si grain_amount > 0
#   - vignette solo si vignette > 0
#   - ffmpeg tuning (crf/preset/pix_fmt/faststart) solo si se setea

import os
import json
import hashlib
import math
from typing import Any, Dict, List, Optional, Sequence, Union

# --- COMPAT FIX (Pillow >=10 quita Image.ANTIALIAS) ---
try:
    from PIL import Image as PILImage  # type: ignore
    if not hasattr(PILImage, "ANTIALIAS"):
        if hasattr(PILImage, "Resampling"):
            PILImage.ANTIALIAS = PILImage.Resampling.LANCZOS  # type: ignore
        else:
            PILImage.ANTIALIAS = getattr(PILImage, "LANCZOS", 1)  # type: ignore
except Exception:
    pass

from moviepy.editor import (
    ImageClip,
    AudioFileClip,
    concatenate_videoclips,
    concatenate_audioclips,
    CompositeAudioClip,
    CompositeVideoClip,
)

import moviepy.audio.fx.all as afx


# Importar funciones puras desde video_utils (testeable sin moviepy)
from app.video_utils import (
    stable_dumps as _stable_dumps,
    sha256_hex as _sha256_hex,
    normalize_motion_profiles as _normalize_motion_profiles,
    normalize_motion_strengths as _normalize_motion_strengths,
    build_vf_filters as _build_vf_filters,
)


def _sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _project_root() -> str:
    return os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def _cache_dir() -> str:
    ws = os.getenv("STUDIO_WORKSPACE", "workspace")
    root = _project_root()
    ws_root = ws if os.path.isabs(ws) else os.path.join(root, ws)
    return os.path.join(ws_root, "cache", "video")


def _fit_to_9x16(clip, fit_mode: str, target_w: int, target_h: int):
    fit_mode = (fit_mode or "crop").strip().lower()
    w, h = clip.size
    if not w or not h:
        return clip
    if int(w) == int(target_w) and int(h) == int(target_h):
        return clip

    if fit_mode == "letterbox":
        scale = min(target_w / float(w), target_h / float(h))
        c = clip.resize(scale)
        return c.on_color(size=(target_w, target_h), color=(0, 0, 0), pos=("center", "center"))

    # crop (llenar y recortar)
    scale = max(target_w / float(w), target_h / float(h))
    c = clip.resize(scale)

    x1 = int(max(0, (c.w - target_w) / 2.0))
    y1 = int(max(0, (c.h - target_h) / 2.0))
    return c.crop(x1=x1, y1=y1, width=target_w, height=target_h)


def _loop_music_to_duration(music_clip: AudioFileClip, duration: float) -> AudioFileClip:
    if duration <= 0:
        return music_clip
    base_dur = float(music_clip.duration or 0.0)
    if base_dur <= 0:
        return music_clip

    parts = []
    t = 0.0
    while t < duration:
        parts.append(music_clip)
        t += base_dur

    looped = concatenate_audioclips(parts) if parts else music_clip
    return looped.subclip(0, duration)


# _normalize_motion_profiles -> importado desde video_utils


# _normalize_motion_strengths -> importado desde video_utils


def _apply_motion_profile(base, profile: str, duration: float, target_w: int, target_h: int, strength: float) -> Any:
    p = (profile or "none").strip().lower()
    dur = max(0.001, float(duration))
    s = float(strength)

    if p in ("", "none", "off"):
        return base

    # clamp razonable
    if s <= 0:
        s = 0.10
    s = max(0.02, min(0.30, s))

    if p == "slow_zoom_in":

        def f(t: float) -> float:
            return 1.0 + s * (float(t) / dur)

        moving = base.resize(lambda t: f(float(t)))
        out = CompositeVideoClip([moving.set_position(("center", "center"))], size=(target_w, target_h))
        return out.set_duration(dur)

    if p == "slow_zoom_out":
        start = 1.0 + s

        def f(t: float) -> float:
            return start - s * (float(t) / dur)

        moving = base.resize(lambda t: f(float(t)))
        out = CompositeVideoClip([moving.set_position(("center", "center"))], size=(target_w, target_h))
        return out.set_duration(dur)

    if p in ("pan_left", "pan_right", "pan_up", "pan_down"):
        scale = 1.0 + max(0.08, s)
        moving = base.resize(scale)

        extra_x = float(max(0, moving.w - target_w))
        extra_y = float(max(0, moving.h - target_h))

        if extra_x < 2.0 and extra_y < 2.0:
            out = CompositeVideoClip([moving.set_position(("center", "center"))], size=(target_w, target_h))
            return out.set_duration(dur)

        if p in ("pan_left", "pan_right") and extra_x < 2.0:
            out = CompositeVideoClip([moving.set_position(("center", "center"))], size=(target_w, target_h))
            return out.set_duration(dur)

        if p in ("pan_up", "pan_down") and extra_y < 2.0:
            out = CompositeVideoClip([moving.set_position(("center", "center"))], size=(target_w, target_h))
            return out.set_duration(dur)

        x0 = -extra_x / 2.0
        y0 = -extra_y / 2.0

        if p == "pan_right":

            def x(t: float) -> float:
                return -extra_x * (float(t) / dur)

            moving = moving.set_position(lambda t: (x(float(t)), y0))

        elif p == "pan_left":

            def x(t: float) -> float:
                return -extra_x * (1.0 - (float(t) / dur))

            moving = moving.set_position(lambda t: (x(float(t)), y0))

        elif p == "pan_down":

            def y(t: float) -> float:
                return -extra_y * (float(t) / dur)

            moving = moving.set_position(lambda t: (x0, y(float(t))))

        else:  # pan_up

            def y(t: float) -> float:
                return -extra_y * (1.0 - (float(t) / dur))

            moving = moving.set_position(lambda t: (x0, y(float(t))))

        out = CompositeVideoClip([moving], size=(target_w, target_h))
        return out.set_duration(dur)

    return base


def _apply_micro_jitter(clip, duration: float, target_w: int, target_h: int, jitter_px: float, jitter_hz: float, scene_idx: int):
    """Micro-jitter determinista (handheld).
    - jitter_px: amplitud máxima (1..3 recomendado)
    - jitter_hz: frecuencia (0.6..1.5 recomendado)
    """
    try:
        j = float(jitter_px)
    except Exception:
        j = 0.0
    if j <= 0.0:
        return clip

    dur = max(0.001, float(duration))
    hz = float(jitter_hz) if jitter_hz else 0.9

    scale = 1.0 + min(0.03, max(0.01, j / 150.0))
    moving = clip.resize(scale)

    extra_x = float(max(0, moving.w - target_w))
    extra_y = float(max(0, moving.h - target_h))
    x0 = -extra_x / 2.0
    y0 = -extra_y / 2.0

    amp_x = min(j, extra_x / 2.0) if extra_x > 0 else 0.0
    amp_y = min(j, extra_y / 2.0) if extra_y > 0 else 0.0

    seed = int(hashlib.sha256(f"jitter|{scene_idx}|{dur:.3f}".encode("utf-8")).hexdigest()[:8], 16)
    phx = (seed % 1000) / 1000.0 * 2.0 * math.pi
    phy = ((seed // 1000) % 1000) / 1000.0 * 2.0 * math.pi

    fx = max(0.2, float(hz))
    fy = max(0.2, float(hz) * 1.17)

    def pos(t: float):
        tt = float(t) / dur
        dx = amp_x * math.sin(2.0 * math.pi * fx * tt + phx)
        dy = amp_y * math.sin(2.0 * math.pi * fy * tt + phy)
        return (x0 + dx, y0 + dy)

    out = CompositeVideoClip([moving.set_position(pos)], size=(target_w, target_h))
    return out.set_duration(dur)


def _build_vf_filters(grain_amount: float, vignette: float, seed_int: int) -> str:
    """
    Construye -vf para FFmpeg:
    - grain: noise=alls=20:allf=t+u:all_seed=...
    - vignette: vignette=<angle>
    """
    vf: List[str] = []

    try:
        g = float(grain_amount)
    except Exception:
        g = 0.0
    if g > 0.0:
        # Map 0.020 -> 20 (rango permitido 0..100)
        alls = int(round(max(0.0, min(100.0, g * 1000.0))))
        vf.append(f"noise=alls={alls}:allf=t+u:all_seed={int(seed_int) & 0x7fffffff}")

    try:
        v = float(vignette)
    except Exception:
        v = 0.0
    if v > 0.0:
        # Vignette usa "angle" en radianes. Default PI/5. Ejemplo fuerte PI/4.
        angle = (math.pi / 5.0) + (v * (math.pi / 3.0))
        angle = max(0.0, min(math.pi / 2.0, angle))
        vf.append(f"vignette={angle:.6f}")

    return ",".join(vf)


def render_slideshow_video(
    *,
    image_paths: List[str],
    audio_paths: List[str],
    out_path: str,
    fps: int = 24,
    codec: str = "libx264",
    audio_codec: str = "aac",
    threads: int = 1,
    fit_mode: str = "crop",
    target_w: int = 1080,
    target_h: int = 1920,
    music_path: Optional[str] = None,
    music_volume: float = 0.22,
    ducking: float = 0.70,
    fade_in_s: float = 0.6,
    fade_out_s: float = 0.8,
    motion_profile: Union[str, Sequence[str], None] = "none",
    motion_strength: Union[float, Sequence[float], None] = 0.10,
    jitter_px: float = 0.0,
    jitter_hz: float = 0.9,
    grain_amount: float = 0.0,
    vignette: float = 0.0,

    # FFmpeg tuning (opcionales, para no romper compat/caches viejos)
    crf: int = 0,                # 0 = no setea -crf
    x264_preset: str = "",       # "" = no setea preset explícito
    pix_fmt: str = "",           # "" = no setea -pix_fmt
    faststart: bool = False,     # True => -movflags +faststart
) -> Dict[str, Any]:
    if not image_paths or not audio_paths or len(image_paths) != len(audio_paths):
        raise ValueError("image_paths y audio_paths deben existir y tener la misma longitud")

    out_path = os.path.abspath(out_path)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)

    music_path_norm = None
    music_sha = None
    if music_path:
        mp = os.path.abspath(music_path)
        if os.path.isfile(mp):
            music_path_norm = mp
            music_sha = _sha256_file(mp)

    motion_profiles = _normalize_motion_profiles(motion_profile, len(image_paths))

    default_strength = 0.10
    strengths = _normalize_motion_strengths(motion_strength, len(image_paths), default_strength)
    strength0 = float(strengths[0]) if strengths else float(default_strength)

    params: Dict[str, Any] = {
        "fps": int(fps),
        "codec": codec,
        "audio_codec": audio_codec,
        "threads": int(threads),
        "fit_mode": str(fit_mode),
        "target_w": int(target_w),
        "target_h": int(target_h),
        "images_sha256": [_sha256_file(p) for p in image_paths],
        "audios_sha256": [_sha256_file(p) for p in audio_paths],
        "music_path": music_path_norm or "",
        "music_sha256": music_sha or "",
        "music_volume": float(music_volume),
        "ducking": float(ducking),
        "fade_in_s": float(fade_in_s),
        "fade_out_s": float(fade_out_s),
        "motion_profiles": motion_profiles,
        "motion_strength": float(strength0),  # compat scalar
    }

    if any(abs(float(s) - strength0) > 1e-9 for s in strengths):
        params["motion_strengths"] = [float(s) for s in strengths]

    if float(jitter_px) > 0.0:
        params["jitter_px"] = float(jitter_px)
        params["jitter_hz"] = float(jitter_hz)

    if float(grain_amount) > 0.0:
        params["grain_amount"] = float(grain_amount)

    if float(vignette) > 0.0:
        params["vignette"] = float(vignette)

    # FFmpeg tuning solo si se activa
    if int(crf) > 0:
        params["crf"] = int(crf)
    if x264_preset:
        params["x264_preset"] = str(x264_preset)
    if pix_fmt:
        params["pix_fmt"] = str(pix_fmt)
    if bool(faststart):
        params["faststart"] = True

    cache_key = _sha256_hex(_stable_dumps(params))
    cache_root = _cache_dir()
    os.makedirs(cache_root, exist_ok=True)
    cache_mp4 = os.path.join(cache_root, f"{cache_key}.mp4")
    cache_meta = os.path.join(cache_root, f"{cache_key}.json")

    if os.path.exists(cache_mp4):
        if os.path.abspath(cache_mp4) != os.path.abspath(out_path):
            with open(cache_mp4, "rb") as src, open(out_path, "wb") as dst:
                dst.write(src.read())
        return {"path": out_path, "cache_hit": True, "cache_key": cache_key, "note": "video: cache_hit"}

    audio_clips = [AudioFileClip(a) for a in audio_paths]
    voice = concatenate_audioclips(audio_clips)
    total_dur = float(voice.duration or 0.0)

    final_audio = voice
    if music_path_norm and total_dur > 0:
        bg = AudioFileClip(music_path_norm)
        bg = _loop_music_to_duration(bg, total_dur)

        bg = bg.volumex(float(music_volume))
        bg = bg.volumex(float(ducking))

        if fade_in_s > 0:
            bg = bg.fx(afx.audio_fadein, float(fade_in_s))
        if fade_out_s > 0:
            bg = bg.fx(afx.audio_fadeout, float(fade_out_s))

        final_audio = CompositeAudioClip([bg, voice]).set_duration(total_dur)

    clips: List[Any] = []
    for idx, (img_path, aclip) in enumerate(zip(image_paths, audio_clips)):
        dur = max(0.2, float(aclip.duration or 0.0))
        base = ImageClip(img_path).set_duration(dur)
        base = _fit_to_9x16(base, fit_mode=fit_mode, target_w=target_w, target_h=target_h)

        prof = motion_profiles[idx] if idx < len(motion_profiles) else "none"
        s = float(strengths[idx]) if idx < len(strengths) else float(strength0)
        base = _apply_motion_profile(base, prof, dur, target_w, target_h, s)
        base = _apply_micro_jitter(base, dur, target_w, target_h, float(jitter_px), float(jitter_hz), idx)

        clips.append(base)

    video = concatenate_videoclips(clips, method="compose").set_audio(final_audio)

    # ffmpeg params: metadata reproducible + filtros
    ffmpeg_params = [
        "-metadata", "creation_time=1980-01-01T00:00:00Z",
        "-metadata", "comment=STUDIO_MVP",
    ]

    # VF (grain/vignette) determinista usando seed derivado del cache_key
    seed_int = int(str(cache_key)[:8], 16)
    vf = _build_vf_filters(float(grain_amount), float(vignette), seed_int)
    if vf:
        ffmpeg_params += ["-vf", vf]

    # tuning opcional
    if bool(faststart):
        ffmpeg_params += ["-movflags", "+faststart"]
    if pix_fmt:
        ffmpeg_params += ["-pix_fmt", str(pix_fmt)]
    if int(crf) > 0:
        ffmpeg_params += ["-crf", str(int(crf))]

    write_kwargs: Dict[str, Any] = {}
    if x264_preset:
        write_kwargs["preset"] = str(x264_preset)

    video.write_videofile(
        out_path,
        fps=int(fps),
        codec=codec,
        audio_codec=audio_codec,
        threads=int(threads),
        ffmpeg_params=ffmpeg_params,
        logger="bar",
        **write_kwargs,
    )

    try:
        with open(out_path, "rb") as src, open(cache_mp4, "wb") as dst:
            dst.write(src.read())
        meta = {"schema": "STUDIO_VIDEO_CACHE_V1", "cache_key": cache_key, "params": params}
        with open(cache_meta, "w", encoding="utf-8") as f:
            json.dump(meta, f, ensure_ascii=False, indent=2)
            f.write("\n")
    except Exception:
        pass

    return {"path": out_path, "cache_hit": False, "cache_key": cache_key, "note": "video: rendered"}