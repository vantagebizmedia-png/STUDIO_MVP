# -*- coding: utf-8 -*-
# app/video_pipeline.py  Generación automática de video (reels) sobre STUDIO v0.2
#
# Flujo:
#   prompt -> generate_v02 (content_pack) -> media (voz+imágenes) -> render mp4 (1080x1920)
#
# Flags (principales):
#   --fit crop|letterbox
#   --subs (quema subtítulos en las imágenes)
#   --music_mode fixed|random|topic|menu|off
#   --ducking_mode fixed|dynamic
#   --music_volume, --ducking

from __future__ import annotations

import logging
import os
import json
import shutil
import argparse
import hashlib
from typing import Any, Dict, List, Optional

from app.v02_core import generate_v02
from app.providers.image_provider import ProviderImage
from app.providers.voice_provider import ProviderVoice
from app.video_render import render_slideshow_video
from app.music_picker import pick_music_path

logger = logging.getLogger(__name__)


def _read_json(path: str) -> Any:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def _write_json(path: str, obj: Any) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)
        f.write("\n")


def _sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            b = f.read(1024 * 1024)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def _collect_scenes(pack_dir: str) -> List[Dict[str, Any]]:
    storyboard = _read_json(os.path.join(pack_dir, "storyboard.json"))
    clips = _read_json(os.path.join(pack_dir, "script_by_clips.json"))

    clip_by_id = {c.get("clip_id"): c for c in clips if isinstance(c, dict)}
    out: List[Dict[str, Any]] = []

    for s in storyboard:
        if not isinstance(s, dict):
            continue
        scene_id = str(s.get("scene_id") or "").strip()
        from_clip = str(s.get("from_clip_id") or "").strip()
        prompt_ref = str(s.get("image_prompt_ref") or "").strip()
        if not scene_id or not from_clip or not prompt_ref:
            continue

        clip = clip_by_id.get(from_clip) or {}
        voiceover = str(clip.get("voiceover") or "").strip()

        prompt_path = os.path.join(pack_dir, prompt_ref.replace("/", os.sep))
        if not os.path.exists(prompt_path):
            continue

        with open(prompt_path, "r", encoding="utf-8") as f:
            prompt_txt = f.read().strip()

        out.append(
            {
                "scene_id": scene_id,
                "clip_id": from_clip,
                "voiceover": voiceover,
                "image_prompt": prompt_txt,
                "stock_query": str(s.get("stock_query") or "").strip(),
                "image_stock_query": str(s.get("image_stock_query") or "").strip(),
                "image_source_mode": str(s.get("image_source_mode") or "").strip(),
                "image_provider_override": str(s.get("image_provider_override") or "").strip(),
            }
        )

    return out


def _ensure_dirs(run_dir: str) -> Dict[str, str]:
    render_dir = os.path.join(run_dir, "render")
    images_dir = os.path.join(render_dir, "images")
    audio_dir = os.path.join(render_dir, "audio")
    os.makedirs(images_dir, exist_ok=True)
    os.makedirs(audio_dir, exist_ok=True)
    return {"render_dir": render_dir, "images_dir": images_dir, "audio_dir": audio_dir}


def _project_root() -> str:
    return os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def _abs_if_exists(path: str, base_dir: Optional[str] = None) -> str:
    """Devuelve ruta absoluta si existe archivo, si no ''."""
    p = (path or "").strip()
    if not p:
        return ""
    if not os.path.isabs(p) and base_dir:
        p = os.path.join(base_dir, p)
    p = os.path.abspath(p)
    return p if os.path.isfile(p) else ""


def _get_video_duration(video_path: str) -> float:
    """Obtiene la duración de un video usando ffprobe (sin cargar el video en memoria)."""
    try:
        import subprocess
        cmd = [
            "ffprobe", "-v", "quiet",
            "-show_entries", "format=duration",
            "-of", "csv=p=0",
            video_path,
        ]
        out = subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL).strip()
        return float(out) if out else 0.0
    except Exception:
        return 0.0


def _apply_dynamic_ducking_ffmpeg(
    video_path: str,
    music_path: str,
    music_volume: float,
    ducking: float,
    fade_in_s: float = 0.6,
    fade_out_s: float = 0.8,
) -> bool:
    """Ducking dinámico real con FFmpeg sidechaincompress.
    Voz (audio del video) = sidechain; música = main, baja cuando hay voz.
    """
    if not music_path:
        return False

    try:
        from imageio_ffmpeg import get_ffmpeg_exe
        import subprocess
    except Exception:
        return False

    # Duración del video via ffprobe (ligero, sin cargar frames en RAM)
    dur = _get_video_duration(video_path)

    if dur <= 0.1:
        return False

    ff = get_ffmpeg_exe()
    tmp = video_path + ".duck.tmp.mp4"

    d = float(ducking)
    # ducking (0.40..0.80) -> ratio (alto = más compresión)
    ratio = max(2.0, min(14.0, 2.0 + (1.0 - d) * 16.0))

    threshold = 0.06
    attack_ms = 35
    release_ms = 250
    fo_start = max(0.0, dur - float(fade_out_s))

    # music: recorte a dur + volumen + fades
    # sidechaincompress: reduce music cuando hay voz (0:a)
    # amix: mezcla music+voz
    filter_complex = (
        f"[1:a]atrim=0:{dur},asetpts=N/SR/TB,volume={float(music_volume)}"
        f",afade=t=in:st=0:d={float(fade_in_s)},afade=t=out:st={fo_start}:d={float(fade_out_s)}[m];"
        f"[m][0:a]sidechaincompress=threshold={threshold}:ratio={ratio}:attack={attack_ms}:release={release_ms}[md];"
        f"[md][0:a]amix=inputs=2:duration=first:dropout_transition=2[aout]"
    )

    cmd = [
        ff, "-y", "-hide_banner",
        "-i", video_path,
        "-stream_loop", "-1",
        "-i", music_path,
        "-filter_complex", filter_complex,
        "-map", "0:v:0",
        "-map", "[aout]",
        "-c:v", "copy",
        "-c:a", "aac",
        "-shortest",
        tmp
    ]

    try:
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        if p.returncode != 0:
            logger.warning("ducking dinámico FFmpeg falló (rc=%d): %s", p.returncode, p.stdout[-400:] if p.stdout else "")
            return False
        os.replace(tmp, video_path)
        return True
    except Exception as exc:
        logger.warning("ducking dinámico excepción: %s", exc)
        return False


def main() -> None:
    logging.basicConfig(level=logging.WARNING, format="%(levelname)s %(name)s: %(message)s")
    ap = argparse.ArgumentParser()
    ap.add_argument("prompt", type=str, help="Tema / prompt del reel")
    ap.add_argument("--seed", type=int, default=123)
    ap.add_argument("--target_format", type=str, default="reel_short")
    ap.add_argument("--language", type=str, default="es")
    ap.add_argument("--style_id", type=str, default="infografia")
    ap.add_argument("--voice_pacing", type=str, default="medio")
    ap.add_argument("--audience_level", type=str, default="principiante")
    ap.add_argument("--max_scenes", type=int, default=5, help="Maximo de escenas a renderizar")
    ap.add_argument("--pack_dir", type=str, default="", help="Usar content_pack existente (omite generate_v02)")

    ap.add_argument(
        "--fit",
        choices=["crop", "letterbox"],
        default="crop",
        help="Ajuste a 9:16: crop (recorta) o letterbox (barras negras)",
    )

    ap.add_argument("--subs", action="store_true", help="Quema subtítulos en las imágenes antes del render")
    ap.add_argument(
        "--subs_font",
        type=str,
        default=r"C:\Windows\Fonts\arial.ttf",
        help="Ruta a .ttf (Windows: C:\\Windows\\Fonts\\arial.ttf)",
    )
    ap.add_argument("--subs_size", type=int, default=64, help="Tamaño de fuente de subtítulos")

    # Flags música/ducking
    ap.add_argument("--music", type=str, default="music/bg.mp3", help="Ruta música (fixed). Ej: music/bg.mp3")
    ap.add_argument("--music_volume", type=float, default=0.20, help="Volumen música (puede ser >1.0 si el wav es bajo)")
    ap.add_argument("--ducking", type=float, default=0.55, help="Ducking factor (0.250.80)")

    ap.add_argument("--music_mode", choices=["fixed", "random", "topic", "menu", "off"], default="fixed",
                    help="Musica: fixed/random/topic/menu/off")
    ap.add_argument("--music_dir", type=str, default="music", help="Carpeta con música (mp3/wav/m4a/aac)")
    ap.add_argument("--music_tag", type=str, default="", help="Tag/keyword para ayudar a elegir música")
    ap.add_argument("--ducking_mode", choices=["fixed", "dynamic"], default="fixed",
                    help="Ducking: fixed (simple) o dynamic (FFmpeg sidechain)")

    # Motion/FX deterministas (opcionales, 100% reproducibles con el mismo seed + inputs)
    ap.add_argument("--motion", type=str, default="none",
                    help="Perfil motion: none/slow_zoom_in/slow_zoom_out/pan_left/pan_right/pan_up/pan_down")
    ap.add_argument("--motion_strength", type=float, default=0.10, help="Intensidad de motion (0.0..0.25 típico)")
    ap.add_argument("--jitter_px", type=float, default=0.0, help="Micro-jitter (px). 0 = OFF")
    ap.add_argument("--jitter_hz", type=float, default=0.9, help="Frecuencia jitter")
    ap.add_argument("--grain_amount", type=float, default=0.0, help="Film grain (0 = OFF)")
    ap.add_argument("--vignette", type=float, default=0.0, help="Vignette (0 = OFF)")

    # FFmpeg tuning (opcionales; si no los pasas, usa defaults del renderer)
    ap.add_argument("--crf", type=int, default=0, help="CRF x264 (0 = no setea)")
    ap.add_argument("--x264_preset", type=str, default="", help="Preset x264 (\"\" = no setea)")
    ap.add_argument("--pix_fmt", type=str, default="", help="Pixel format (\"\" = no setea)")
    ap.add_argument("--faststart", action="store_true", help="Setea -movflags +faststart")
    args = ap.parse_args()

    root = _project_root()
    music_dir = str(args.music_dir or "music")
    if not os.path.isabs(music_dir):
        music_dir = os.path.abspath(os.path.join(root, music_dir))

    # --- Selección de música ---
    topic_for_music = str(args.prompt or "")
    picked = pick_music_path(
        topic=topic_for_music,
        seed=int(args.seed or 0),
        mode=str(args.music_mode),
        music_path=str(getattr(args, "music", "")),
        music_dir=music_dir,
        tag=str(args.music_tag),
    )

    # Off -> nada
    if str(args.music_mode).lower() == "off":
        picked = ""

    # VALIDACIÓN IMPORTANTE:
    # En dynamic, NO usamos args.music para render, así que validamos picked aquí y lo guardamos en music_dynamic.
    picked_abs = _abs_if_exists(picked, base_dir=root)

    music_path = ""
    music_dynamic = ""

    if str(args.ducking_mode).lower() == "dynamic":
        music_dynamic = picked_abs
    else:
        music_path = picked_abs

    if music_path:
        print(f" Musica: {music_path}")
    elif music_dynamic:
        print(f" Musica (dynamic): {music_dynamic}")
    else:
        print(" Musica: OFF")

    if str(args.ducking_mode).lower() == "dynamic" and not music_dynamic:
        print("  ducking_mode=dynamic pero no hay música válida. Se renderiza solo voz.")
    if str(args.ducking_mode).lower() == "fixed" and str(args.music_mode).lower() != "off" and not music_path:
        print("  music_mode no es off pero no hay música válida. Se renderiza solo voz.")

    # 1) Content pack: nuevo (generate_v02) o existente (--pack_dir)
    pack_override = str(args.pack_dir or "").strip()
    if pack_override:
        pack_dir = pack_override
        if not os.path.isabs(pack_dir):
            pack_dir = os.path.abspath(os.path.join(root, pack_dir))
        if not os.path.isdir(pack_dir):
            raise SystemExit(f"--pack_dir no existe o no es directorio: {pack_dir}")
        pack_dir = os.path.abspath(pack_dir)
        run_dir = os.path.dirname(pack_dir)
    else:
        gen = generate_v02(
            prompt=args.prompt,
            seed=int(args.seed),
            target_format=args.target_format,
            language=args.language,
            style_id=args.style_id,
            voice_pacing=args.voice_pacing,
            audience_level=args.audience_level,
        )
        pack_dir = os.path.abspath(gen["pack_dir"])
        run_dir = os.path.dirname(pack_dir)

    dirs = _ensure_dirs(run_dir)

    # 2) Cargar escenas
    scenes = _collect_scenes(pack_dir)[: max(1, int(args.max_scenes))]

    # 3) Generar imágenes (REUSE si ya existen para ahorrar API)
    default_img = ProviderImage()
    img_paths: List[str] = []
    img_meta: List[Dict[str, Any]] = []

    def _build_image_provider_override(provider_name: str) -> ProviderImage:
        cfg_obj = _read_json(default_img.config_path)
        cfg_obj.setdefault("image", {})
        cfg_obj["image"]["active_provider"] = provider_name

        import tempfile
        tmp_fd, tmp_cfg_path = tempfile.mkstemp(suffix=f"_providers_image_{provider_name}.json", prefix="studio_")
        os.close(tmp_fd)
        _write_json(tmp_cfg_path, cfg_obj)
        prov = ProviderImage(config_path=tmp_cfg_path)
        # limpiar para que no se filtre en export/zip
        try:
            os.unlink(tmp_cfg_path)
        except OSError:
            pass
        return prov

    image_provider_cache: Dict[str, ProviderImage] = {
        default_img.active_provider: default_img
    }

    for j, s in enumerate(scenes, start=1):
        out_path = os.path.join(dirs["images_dir"], f"{s['scene_id']}.png")
        if os.path.exists(out_path):
            img_paths.append(out_path)
            img_meta.append({"provider":"REUSE_RENDER","model":"","mode":"REUSE","cache_hit":True,"cache_key":"","note":"reused existing render/image"})
            continue

        full_prompt = "Imagen vertical 9:16, alta calidad, lista para reel.\n\n" + s["image_prompt"]
        stock_query = str(s.get("stock_query") or s.get("image_stock_query") or "").strip()
        image_source_mode = str(s.get("image_source_mode") or "").strip().lower()
        provider_override = str(s.get("image_provider_override") or "").strip()

        chosen_provider_name = provider_override
        if not chosen_provider_name and image_source_mode == "stock":
            chosen_provider_name = "pixabay_images"

        current_img = default_img
        if chosen_provider_name:
            if chosen_provider_name not in image_provider_cache:
                image_provider_cache[chosen_provider_name] = _build_image_provider_override(chosen_provider_name)
            current_img = image_provider_cache[chosen_provider_name]

        gen_kwargs = {}
        if stock_query:
            gen_kwargs["stock_query"] = stock_query

        r = current_img.generate(
            purpose=f"scene_image_{j:02d}",
            prompt=full_prompt,
            seed=args.seed,
            **gen_kwargs,
        )

        if os.path.abspath(r["path"]) != os.path.abspath(out_path):
            try:
                shutil.copy2(r["path"], out_path)
            except Exception as exc:
                logger.warning("No se pudo copiar imagen %s -> %s: %s", r["path"], out_path, exc)
                out_path = r["path"]

        img_paths.append(out_path)
        img_meta.append({k: r.get(k) for k in ("provider","model","mode","cache_hit","cache_key","note")})

    if args.subs:
        from app.subtitles_burn import burn_subtitles_on_image

        subbed: List[str] = []
        for s, pth in zip(scenes, img_paths):
            out_p = os.path.join(dirs["images_dir"], f"{s['scene_id']}_sub.png")
            burn_subtitles_on_image(
                img_path=pth,
                out_path=out_p,
                text=str(s.get("voiceover") or ""),
                target_w=1080,
                target_h=1920,
                font_path=args.subs_font,
                font_size=int(args.subs_size),
            )
            subbed.append(out_p)
        img_paths = subbed

    # 4) Generar voz por clip
    tts = ProviderVoice()
    audio_paths: List[str] = []
    audio_meta: List[Dict[str, Any]] = []

    for i, s in enumerate(scenes, start=1):
        # REUSE audio: si ya existe, no llamar TTS
        existing = None
        for ext in (".wav",".mp3",".m4a",".aac",".flac",".ogg"):
            cand = os.path.join(dirs["audio_dir"], f"{s['scene_id']}{ext}")
            if os.path.exists(cand):
                existing = cand
                break
        if existing:
            audio_paths.append(existing)
            audio_meta.append({"provider":"REUSE_RENDER","model":"","mode":"REUSE","cache_hit":True,"cache_key":"","note":"reused existing render/audio"})
            continue

        text = str(s.get("voiceover") or s.get("text") or s.get("narration") or "").strip()
        if not text:
            raise ValueError("voiceover vacío en scene_id=%s clip_id=%s" % (s.get("scene_id"), s.get("clip_id")))
        r = tts.speak(purpose=f"scene_voice_{i:02d}", text=text, seed=args.seed)

        ext = os.path.splitext(r["path"])[1] or ".wav"
        out_path = os.path.join(dirs["audio_dir"], f"{s['scene_id']}{ext}")

        if os.path.abspath(r["path"]) != os.path.abspath(out_path):
            try:
                shutil.copy2(r["path"], out_path)
            except Exception as exc:
                logger.warning("No se pudo copiar audio %s -> %s: %s", r["path"], out_path, exc)
                out_path = r["path"]

        audio_paths.append(out_path)
        audio_meta.append({k: r.get(k) for k in ("provider", "model", "mode", "cache_hit", "cache_key", "note")})

    # 5) Render (si ducking_mode fixed -> música aquí; si dynamic -> NO música aquí)
    video_out = os.path.join(dirs["render_dir"], "video_final.mp4")

    video_info = render_slideshow_video(
        image_paths=img_paths,
        audio_paths=audio_paths,
        out_path=video_out,
        fit_mode=args.fit,
        target_w=1080,
        target_h=1920,
        music_path=(music_path or None),
        music_volume=float(args.music_volume),
        ducking=float(args.ducking),
        motion_profile=str(args.motion),
        motion_strength=float(args.motion_strength),
        jitter_px=float(args.jitter_px),
        jitter_hz=float(args.jitter_hz),
        grain_amount=float(args.grain_amount),
        vignette=float(args.vignette),
        crf=int(args.crf),
        x264_preset=str(args.x264_preset),
        pix_fmt=str(args.pix_fmt),
        faststart=bool(args.faststart),)

    # --- Ducking dinámico real (FFmpeg sidechain) ---
    if str(args.ducking_mode).lower() == "dynamic" and music_dynamic:
        print(f" Aplicando ducking dinámico a: {os.path.basename(music_dynamic)}")
        ok = _apply_dynamic_ducking_ffmpeg(
            video_info["path"],
            music_dynamic,
            float(args.music_volume),
            float(args.ducking),
        )
        if not ok:
            print(" ducking dinámico falló (se deja solo voz)")
        else:
            print(" ducking dinámico aplicado ")

    # 6) Manifest
    manifest = {
        "schema": "STUDIO_RENDER_V1",
        "inputs": {
            "prompt": args.prompt,
            "seed": int(args.seed),
            "pack_dir": pack_dir,
            "run_dir": run_dir,
            "fit": args.fit,
            "subs": bool(args.subs),
            "music": (music_dynamic or music_path or ""),
            "music_mode": str(args.music_mode),
            "ducking_mode": str(args.ducking_mode),
            "music_volume": float(args.music_volume),
            "ducking": float(args.ducking),
        },
        "images": {
            "count": len(img_paths),
            "paths": [os.path.relpath(p, run_dir) for p in img_paths],
            "sha256": [_sha256_file(p) for p in img_paths],
            "meta": img_meta,
        },
        "audio": {
            "count": len(audio_paths),
            "paths": [os.path.relpath(p, run_dir) for p in audio_paths],
            "sha256": [_sha256_file(p) for p in audio_paths],
            "meta": audio_meta,
        },
        "video": {
            "path": os.path.relpath(video_info["path"], run_dir),
            "sha256": _sha256_file(video_info["path"]),
            "meta": {k: video_info.get(k) for k in ("cache_hit", "cache_key", "note")},
        },
    }
    p = os.path.join(run_dir, "render", "render_manifest.json")
    _write_json(p, manifest)

    # Copia "producto" estable: %STUDIO_WORKSPACE%/output/video_final.mp4 (siempre el último)
    ws = os.getenv("STUDIO_WORKSPACE", "workspace")
    ws_root = ws if os.path.isabs(ws) else os.path.join(root, ws)
    stable_out_dir = os.path.join(ws_root, "output")
    os.makedirs(stable_out_dir, exist_ok=True)
    rid = os.path.basename(run_dir)
    stable_out = os.path.join(stable_out_dir, f"video_final_{rid}.mp4")
    stable_out_latest = os.path.join(stable_out_dir, "video_final_latest.mp4")
    try:
        shutil.copy2(video_info["path"], stable_out)
        shutil.copy2(video_info["path"], stable_out_latest)
    except Exception as exc:
        logger.warning("No se pudo copiar video estable: %s", exc)
    print("")
    print(" Video listo:")
    print(video_info["path"])
    print(" Copia estable (producto):")
    print(stable_out)
    print(" Latest:")
    print(stable_out_latest)
if __name__ == "__main__":
    main()
