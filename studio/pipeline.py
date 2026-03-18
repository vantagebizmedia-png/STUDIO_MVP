# -*- coding: utf-8 -*-
"""Pipeline puro de STUDIO — sin prints, sin CLI, sin I/O de consola.

v0.3:
- (opcional) text provider genera un guion final desde un prompt
- genera imagen + audio (demo o LIVE según providers)
- escribe script_<tag>.txt en work_dir
- escribe manifest_v03.json en work_dir (bridge)

F2.0 (Multi-Scene):
- si pipe.multiscene=True y pipe.max_scenes>1:
  - divide el guion final en N escenas
  - genera image/audio por escena: image_<tag>_sNN.png, audio_<tag>_sNN.wav
  - escribe scenes[] en manifest (y mantiene artifacts apuntando a la escena 1 para compat)
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import wave
import base64
from dataclasses import dataclass, field
from typing import Callable, Optional, Any

from studio.providers.voice.base_voice import BaseVoiceProvider
from studio.providers.image.base_image import BaseImageProvider
from studio.providers.text.base_text import BaseTextProvider

from studio.scene_builder import build_scenes, render_scenes_strict
from studio.live_manifest_patch_v03 import apply_scene_builder_to_manifest


_FALLBACK_PNG_1X1 = base64.b64decode(
    b"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+X2dAAAAAASUVORK5CYII="
)


def _provider_id(p: Any) -> str:
    if p is None:
        return ""
    return str(getattr(p, "_provider_name", p.__class__.__name__))


def _sha8(text: str) -> str:
    h = hashlib.sha256(text.encode("utf-8")).hexdigest()
    return h[:8]


def _format_srt_time(ms_total: int) -> str:
    ms = max(0, int(ms_total))
    hh = ms // 3600000
    rem = ms % 3600000
    mm = rem // 60000
    rem = rem % 60000
    ss = rem // 1000
    mmm = rem % 1000
    return f"{hh:02d}:{mm:02d}:{ss:02d},{mmm:03d}"


def _sanitize_subtitle_text(text: str, idx: int) -> str:
    clean = str(text or "").replace("\r", " ").replace("\n", " ").strip()
    if clean:
        return clean
    return f"Escena {idx:02d}."


def _rel_to_base(path: str, base_dir: str) -> str:
    p = str(path or "").strip()
    if not p:
        return ""
    base_abs = os.path.abspath(base_dir or ".")
    abs_p = p if os.path.isabs(p) else os.path.abspath(os.path.join(base_abs, p))
    rel = os.path.relpath(abs_p, start=base_abs)
    return rel.replace("\\", "/")


def _default_text_cache_dir() -> str:
    ws = os.environ.get("STUDIO_WORKSPACE", "").strip()
    if not ws:
        ws = "workspace"
    return os.path.abspath(os.path.join(ws, "cache", "text"))


def _text_cache_key(provider_name: str, provider_cfg: dict, prompt: str) -> str:
    blob = {
        "provider": provider_name or "",
        "config": provider_cfg or {},
        "prompt": prompt or "",
    }
    raw = json.dumps(blob, sort_keys=True, ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _split_scenes(text: str, max_scenes: int, mode: str = "auto") -> list[str]:
    t = (text or "").strip()
    if not t:
        return []

    n = max(1, int(max_scenes or 1))
    mode = (mode or "auto").strip().lower()

    # 1) Separador explícito con '---' (con o sin espacios)
    if mode in ("auto", "dash", "---") and re.search(r"\n\s*---\s*\n", t):
        parts = [p.strip() for p in re.split(r"\n\s*---\s*\n", t) if p.strip()]
        return parts[:n] if parts else [t]

    # 2) Por bloques (líneas en blanco)
    if mode in ("auto", "blank", "blankline", "paragraph"):
        parts = [p.strip() for p in re.split(r"\n\s*\n+", t) if p.strip()]
        if len(parts) >= 2:
            return parts[:n]

    # 3) Por oraciones (fallback)
    sents = [p.strip() for p in re.split(r"(?<=[\.\!\?])\s+", t) if p.strip()]
    if len(sents) <= 1:
        return [t]

    # Agrupar oraciones en n grupos (aprox)
    groups: list[str] = []
    per = max(1, (len(sents) + n - 1) // n)
    for i in range(0, len(sents), per):
        groups.append(" ".join(sents[i:i + per]).strip())
        if len(groups) >= n:
            break
    return groups if groups else [t]


@dataclass
class StudioPipeline:
    """Pipeline de generación multimedia.

    Si text != None: run(script) interpreta `script` como prompt y produce un guion final.
    Si multiscene=True: genera N escenas (manteniendo artifacts de escena 1 por compat).
    """

    voice: BaseVoiceProvider
    image: BaseImageProvider
    text: Optional[BaseTextProvider] = None

    work_dir: str = "."
    on_progress: Optional[Callable[[str, int, int], None]] = field(default=None, repr=False)

    # knobs multi-scene (inyectados por builders desde config v0.3)
    multiscene: bool = False
    max_scenes: int = 1
    scene_split: str = "auto"

    # metadata para manifest (inyectado por builders)
    _v03_config_path: str = ""

    def _notify(self, step: str, curr: int, total: int) -> None:
        if self.on_progress is None:
            return
        try:
            self.on_progress(step, curr, total)
        except Exception:
            pass

    def _generate_text(self, prompt: str) -> str:
        """Genera guion final usando text provider (con cache determinista si está habilitado)."""
        if self.text is None:
            return prompt

        prompt = (prompt or "").strip()
        if not prompt:
            return ""

        # metadata del provider
        provider_name = _provider_id(self.text)

        tcfg = {}
        try:
            tcfg = dict(getattr(self.text, "_provider_cfg", {}) or {})
        except Exception:
            tcfg = {}

        cache_on = bool(tcfg.get("cache", True))
        cache_dir = str(tcfg.get("cache_dir") or _default_text_cache_dir())
        cache_dir = os.path.abspath(cache_dir)
        os.makedirs(cache_dir, exist_ok=True)

        key = _text_cache_key(provider_name, tcfg, prompt)
        cache_path = os.path.join(cache_dir, f"{key}.json")

        if cache_on and os.path.exists(cache_path):
            try:
                with open(cache_path, "r", encoding="utf-8") as f:
                    c = json.load(f)
                out = str(c.get("output", "")).strip()
                if out:
                    return out
            except Exception:
                pass  # fallback a generar de nuevo

        prompt_in = prompt
        if bool(getattr(self, "multiscene", False)) and int(getattr(self, "max_scenes", 1) or 1) > 1:
            max_scenes = max(1, int(getattr(self, "max_scenes", 1) or 1))
            prompt_in = (
                "Devuelve solo guion multiescena con formato estricto.\n"
                f"Reglas: hasta {max_scenes} escenas.\n"
                "Cada escena debe usar exactamente este bloque:\n"
                "ESCENA NN\n"
                "NARRACION: ...\n"
                "ONSCREEN: ...\n"
                "STOCK_QUERY: ...\n"
                "---\n"
                "No agregues texto fuera de esos bloques.\n\n"
                "Prompt base:\n"
                f"{prompt}"
            )

        out = self.text.generate(prompt_in)
        if cache_on:
            try:
                payload = {
                    "version": "v0.3",
                    "provider": provider_name,
                    "config": tcfg,
                    "prompt": prompt_in,
                    "output": out,
                }
                with open(cache_path, "w", encoding="utf-8") as f:
                    f.write(json.dumps(payload, ensure_ascii=False, indent=2))
            except Exception:
                pass

        return str(out or "").strip()

    def _write_fallback_png(self, path: str) -> str:
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        with open(path, "wb") as f:
            f.write(_FALLBACK_PNG_1X1)
        return path

    def _estimate_fallback_audio_duration_s(
        self,
        text: str,
        *,
        min_s: float = 1.2,
        max_s: float = 90.0,
        words_per_minute: float = 150.0,
    ) -> float:
        clean = str(text or "").replace("\r", " ").replace("\n", " ").strip()
        if not clean:
            return float(min_s)

        words = re.findall(r"[A-Za-zÀ-ÿ0-9']+", clean, flags=re.UNICODE)
        word_count = len(words)
        punctuation_count = len(re.findall(r"[\,\.;:\!\?]", clean))

        if word_count > 0:
            words_per_second = max(1.0, float(words_per_minute) / 60.0)
            duration_s = word_count / words_per_second
        else:
            duration_s = max(float(min_s), len(clean) / 14.0)

        duration_s += min(3.0, punctuation_count * 0.12)

        if len(clean) >= 240:
            duration_s += 0.35

        if duration_s < float(min_s):
            duration_s = float(min_s)
        if duration_s > float(max_s):
            duration_s = float(max_s)

        return float(duration_s)

    def _write_fallback_wav(
        self,
        path: str,
        *,
        duration_s: Optional[float] = None,
        text: str = "",
        sr: int = 22050,
    ) -> str:
        """
        Fallback determinista (sin TTS real):
        - Genera un WAV PCM mono 16-bit con SILENCIO (0).
        - La duración se estima desde el texto real cuando no viene forzada.
        - Permite override por env var STUDIO_FALLBACK_AUDIO_S (float).
        """
        import os
        import wave
        import struct

        resolved_duration_s: Optional[float] = duration_s

        try:
            env_s = os.environ.get("STUDIO_FALLBACK_AUDIO_S", "").strip()
            if env_s:
                resolved_duration_s = float(env_s)
        except Exception:
            pass

        if resolved_duration_s is None or float(resolved_duration_s or 0.0) <= 0.0:
            resolved_duration_s = self._estimate_fallback_audio_duration_s(text)

        duration_s = float(resolved_duration_s or 0.0)
        if duration_s < 0.2:
            duration_s = 0.2

        sr = int(sr or 22050)
        if sr < 8000:
            sr = 8000

        nframes = int(round(duration_s * sr))
        if nframes < 1:
            nframes = 1

        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)

        with wave.open(path, "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(sr)

            silence = struct.pack("<h", 0)
            chunk_frames = min(nframes, sr)
            chunk = silence * chunk_frames
            remaining = nframes

            while remaining > 0:
                take = min(remaining, chunk_frames)
                wf.writeframes(chunk[: take * 2])
                remaining -= take

        return path
    def _copy_scene_aliases(self, *, idx: int, script_src: str, image_src: str, audio_src: str) -> dict[str, str]:
        scene_dir = os.path.join(self.work_dir, "artifacts", "scenes", f"scene_{idx:02d}")
        os.makedirs(scene_dir, exist_ok=True)

        script_dst = os.path.join(scene_dir, "script.txt")
        image_dst = os.path.join(scene_dir, "image.png")
        audio_dst = os.path.join(scene_dir, "audio.wav")

        shutil.copyfile(script_src, script_dst)
        shutil.copyfile(image_src, image_dst)
        shutil.copyfile(audio_src, audio_dst)

        return {
            "script": script_dst,
            "image": image_dst,
            "audio": audio_dst,
        }

    def _write_subtitles_srt(self, scenes: list[dict]) -> str:
        outp = os.path.join(self.work_dir, "subtitles.srt")
        os.makedirs(os.path.dirname(outp) or ".", exist_ok=True)

        def _safe_int(value, default: int = 0) -> int:
            try:
                return int(value)
            except Exception:
                return default

        def _scene_index(scene: dict, pos: int) -> int:
            idx = _safe_int((scene or {}).get("index", 0), 0)
            return idx if idx >= 1 else (pos + 1)

        def _pick_scene_text(scene: dict, idx: int) -> str:
            for key in ("script_text", "narration", "onscreen", "audio_text", "stock_query", "text"):
                value = str((scene or {}).get(key, "") or "").strip()
                if value:
                    return _sanitize_subtitle_text(value, idx)
            return _sanitize_subtitle_text("", idx)

        def _resolve_audio_path(scene: dict) -> str:
            artifacts = (scene or {}).get("artifacts")
            assets = (scene or {}).get("assets")

            candidates = []

            if isinstance(artifacts, dict):
                candidates.append(str(artifacts.get("audio", "") or "").strip())

            if isinstance(assets, dict):
                candidates.append(str(assets.get("audio_clip", "") or "").strip())

            candidates.append(str((scene or {}).get("audio", "") or "").strip())

            for raw in candidates:
                if not raw:
                    continue
                p = raw
                if not os.path.isabs(p):
                    p = os.path.join(self.work_dir, p)
                p = os.path.abspath(p)
                if os.path.exists(p):
                    return p

            return ""

        def _audio_duration_ms(scene: dict) -> int:
            audio_path = _resolve_audio_path(scene)
            if not audio_path:
                return 0
            try:
                with wave.open(audio_path, "rb") as wf:
                    return int((wf.getnframes() / float(wf.getframerate())) * 1000)
            except Exception:
                return 0

        def _fallback_duration_ms(scene: dict, idx: int) -> int:
            explicit_duration = _safe_int((scene or {}).get("duration_ms", 0), 0)
            if explicit_duration > 0:
                return explicit_duration

            audio_ms = _audio_duration_ms(scene)
            if audio_ms > 0:
                return audio_ms

            raw_text = ""
            for key in ("script_text", "narration", "onscreen", "audio_text", "stock_query", "text"):
                value = str((scene or {}).get(key, "") or "").strip()
                if value:
                    raw_text = value
                    break

            word_count = len([tok for tok in raw_text.split() if tok.strip()])
            if word_count <= 0:
                return 1500

            return max(1200, word_count * 280)

        normalized: list[dict] = []
        for pos, raw_scene in enumerate(scenes or []):
            scene = dict(raw_scene or {})
            scene["__sort_index"] = _scene_index(scene, pos)
            normalized.append(scene)

        ordered = sorted(normalized, key=lambda x: int(x.get("__sort_index", 0) or 0))

        blocks: list[str] = []
        cursor_ms = 0

        for pos, scene in enumerate(ordered):
            idx = _safe_int(scene.get("__sort_index", pos + 1), pos + 1)

            start_ms = _safe_int(scene.get("start_ms", -1), -1)
            end_ms = _safe_int(scene.get("end_ms", -1), -1)
            duration_ms = _safe_int(scene.get("duration_ms", 0), 0)

            if start_ms >= 0 and end_ms > start_ms:
                pass
            else:
                if duration_ms <= 0:
                    duration_ms = _audio_duration_ms(scene)
                if duration_ms <= 0:
                    duration_ms = _fallback_duration_ms(scene, idx)

                start_ms = max(0, cursor_ms)
                end_ms = start_ms + max(1, duration_ms)

            cursor_ms = max(cursor_ms, end_ms)

            text = _pick_scene_text(scene, idx)
            blocks.append(
                f"{pos + 1}\n"
                f"{_format_srt_time(start_ms)} --> {_format_srt_time(end_ms)}\n"
                f"{text}\n"
            )

        payload = "\n".join(blocks).rstrip() + "\n"
        with open(outp, "w", encoding="utf-8") as f:
            f.write(payload)
        return outp

    def _write_manifest(
        self,
        *,
        script_path: str,
        img_path: str,
        aud_path: str,
        scenes: list[dict] | None = None,
        subtitles_path: str = "",
    ) -> None:
        """
        v0.3 manifest writer:
        - mantiene artifacts + scenes legacy
        - usa Scene Builder v03 real cuando multiscene=True
        """
        os.makedirs(self.work_dir, exist_ok=True)

        final_script = ""
        try:
            with open(script_path, "r", encoding="utf-8") as f:
                final_script = str(f.read() or "").strip()
        except Exception:
            final_script = ""

        manifest = {
            "version": "v0.3",
            "mode": "RUN",
            "work_dir": ".",
            "config_path": _rel_to_base(getattr(self, "_v03_config_path", "") or "", self.work_dir),
            "script_text": final_script,
            "providers": {
                "text": _provider_id(self.text),
                "image": _provider_id(self.image),
                "voice": _provider_id(self.voice),
            },
            "artifacts": {
                "script": _rel_to_base(script_path, self.work_dir),
                "image": _rel_to_base(img_path, self.work_dir),
                "audio": _rel_to_base(aud_path, self.work_dir),
            },
        }

        if subtitles_path:
            manifest["artifacts"]["subtitles"] = _rel_to_base(subtitles_path, self.work_dir)

        if isinstance(scenes, list) and len(scenes) >= 1:
            legacy_scenes: list[dict[str, Any]] = []
            for i, sc in enumerate(scenes, start=1):
                sc_art = dict((sc or {}).get("artifacts") or {})
                legacy_scenes.append(
                    {
                        "id": f"s{i:02d}",
                        "index": i,
                        "narration": str((sc or {}).get("narration", "") or ""),
                        "onscreen": str((sc or {}).get("onscreen", "") or ""),
                        "stock_query": str((sc or {}).get("stock_query", "") or ""),
                        "artifacts": {
                            "script": _rel_to_base(str(sc_art.get("script", "") or ""), self.work_dir),
                            "image": _rel_to_base(str(sc_art.get("image", "") or ""), self.work_dir),
                            "audio": _rel_to_base(str(sc_art.get("audio", "") or ""), self.work_dir),
                        },
                    }
                )
            manifest["scenes"] = legacy_scenes

        total_audio_ms = 0
        try:
            with wave.open(aud_path, "rb") as wf:
                total_audio_ms = int((wf.getnframes() / float(wf.getframerate())) * 1000)
        except Exception:
            total_audio_ms = 0

        manifest["audio_duration_ms"] = int(total_audio_ms)
        manifest["seed"] = 0
        manifest["replay_strict"] = False

        if bool(getattr(self, "multiscene", False)) and int(getattr(self, "max_scenes", 1) or 1) > 1:
            manifest = apply_scene_builder_to_manifest(
                manifest,
                pack_dir=self.work_dir,
                max_scenes=int(getattr(self, "max_scenes", 1) or 1),
            )
        else:
            q = final_script[:120].strip() if final_script.strip() else "concepto abstracto"
            manifest["scenes_v03"] = [
                {
                    "id": "s01",
                    "index": 0,
                    "start_ms": 0,
                    "end_ms": int(total_audio_ms),
                    "duration_ms": int(total_audio_ms),
                    "script_text": final_script,
                    "image_query": q,
                    "assets": {
                        "image": _rel_to_base(img_path, self.work_dir),
                        "audio_clip": _rel_to_base(aud_path, self.work_dir),
                        "image_meta": {
                            "provider": "pixabay" if "pixabay" in str(_provider_id(self.image)).lower() else "image_provider",
                            "cache_hit": False,
                            "cache_key": "",
                            "query": q,
                        },
                    },
                }
            ]
            manifest["scene_builder_v03"] = {
                "max_scenes": 1,
                "total_audio_ms": int(total_audio_ms),
                "provider_order": ["pixabay"],
                "note": "generated in LIVE by studio/pipeline.py; single-scene fallback preserved",
            }

        out_manifest = os.path.join(self.work_dir, "manifest_v03.json")
        with open(out_manifest, "w", encoding="utf-8") as f:
            json.dump(manifest, f, ensure_ascii=False, indent=2)

    def run(self, script: str) -> tuple[str, str]:
        """Ejecuta pipeline v0.3.

        Retorna (image_path, audio_path) de la escena 1 (compat).
        Si multiscene=True: genera escenas adicionales y las escribe en manifest.
        """
        prompt = str(script or "").strip()
        if not prompt:
            raise ValueError("script/prompt no puede estar vacío")

        os.makedirs(self.work_dir, exist_ok=True)

        # 1) Texto (opcional)
        total = 3 if self.text is not None else 2
        curr = 0

        final_script = prompt
        if self.text is not None:
            self._notify("texto", curr, total)
            final_script = self._generate_text(prompt)
            curr += 1

        final_script = str(final_script or "").strip()
        if not final_script:
            raise ValueError("guion final vacío")

        # Multi-scene (si aplica)
        if bool(getattr(self, "multiscene", False)) and int(getattr(self, "max_scenes", 1) or 1) > 1:
            scene_specs = build_scenes(final_script, max_scenes=int(self.max_scenes), split_mode=str(self.scene_split), base_tag=None)
            if not scene_specs:
                scene_specs = build_scenes(final_script, max_scenes=1, split_mode="auto", base_tag=None)
            final_script = render_scenes_strict(scene_specs)

        tag = _sha8(final_script)

        # script "global" siempre
        script_path = os.path.join(self.work_dir, f"script_{tag}.txt")
        with open(script_path, "w", encoding="utf-8") as f:
            f.write(final_script)

        if bool(getattr(self, "multiscene", False)) and int(getattr(self, "max_scenes", 1) or 1) > 1:
            scene_specs = build_scenes(final_script, max_scenes=int(self.max_scenes), split_mode=str(self.scene_split), base_tag=tag)

            scenes_meta: list[dict] = []
            first_script = ""
            first_img = ""
            first_aud = ""

            # progreso: imagen/audio por escena
            total_ms = (1 if self.text is not None else 0) + (2 * len(scene_specs))
            curr_ms = (1 if self.text is not None else 0)

            for spec in scene_specs:
                idx = int(getattr(spec, "index", 0) or 0) or 1
                stag = str(getattr(spec, "tag", "") or "").strip() or f"{tag}_s{idx:02d}"
                narration = str(getattr(spec, "narration", "") or "").strip()
                onscreen = str(getattr(spec, "onscreen", "") or "").strip()
                stock_query = str(getattr(spec, "stock_query", "") or "").strip()
                if not narration and not stock_query:
                    continue

                # Guardamos un script legacy por escena: script_<tag>_sNN.txt
                sp = os.path.join(self.work_dir, f"script_{tag}_s{idx:02d}.txt")
                with open(sp, "w", encoding="utf-8") as f:
                    f.write(f"ESCENA {idx:02d}\n")
                    f.write(f"NARRACION: {narration}\n")
                    f.write(f"ONSCREEN: {onscreen}\n")
                    f.write(f"STOCK_QUERY: {stock_query}\n")
                    f.write("---\n")

                ip = os.path.join(self.work_dir, f"image_{stag}.png")
                ap = os.path.join(self.work_dir, f"audio_{stag}.wav")

                image_prompt = stock_query or narration
                audio_text = narration or stock_query

                self._notify(f"imagen_s{idx:02d}", curr_ms, total_ms)
                try:
                    img = self.image.generate(image_prompt, ip)
                except Exception:
                    img = self._write_fallback_png(ip)
                curr_ms += 1

                self._notify(f"audio_s{idx:02d}", curr_ms, total_ms)
                try:
                    aud = self.voice.synthesize(audio_text, ap)
                except Exception:
                    aud = self._write_fallback_wav(ap, text=audio_text)
                curr_ms += 1

                aliases = self._copy_scene_aliases(
                    idx=idx,
                    script_src=sp,
                    image_src=img,
                    audio_src=aud,
                )

                if idx == 1:
                    first_script = sp
                    first_img, first_aud = img, aud

                scenes_meta.append({
                    "index": idx,
                    "tag": stag,
                    "narration": narration,
                    "onscreen": onscreen,
                    "stock_query": stock_query,
                    "image_prompt": image_prompt,
                    "audio_text": audio_text,
                    "artifacts": {
                        "script": os.path.abspath(aliases["script"]),
                        "image": os.path.abspath(aliases["image"]),
                        "audio": os.path.abspath(aliases["audio"]),
                    }
                })
            if not first_img:
                # fallback si por algún motivo no generó escena 1
                first_script = os.path.join(self.work_dir, f"script_{tag}_s01.txt")
                first_img = os.path.join(self.work_dir, f"image_{tag}.png")
                first_aud = os.path.join(self.work_dir, f"audio_{tag}.wav")
                if not os.path.exists(first_script):
                    with open(first_script, "w", encoding="utf-8") as f:
                        f.write("ESCENA 01\n")
                        f.write(f"NARRACION: {final_script}\n")
                        f.write("ONSCREEN: Idea clave enfoque claro uso practico\n")
                        f.write("STOCK_QUERY: persona explicando tema estudio\n")
                        f.write("---\n")
                try:
                    first_img = self.image.generate(final_script, first_img)
                except Exception:
                    first_img = self._write_fallback_png(first_img)
                try:
                    first_aud = self.voice.synthesize(final_script, first_aud)
                except Exception:
                    first_aud = self._write_fallback_wav(first_aud, text=final_script)
                aliases = self._copy_scene_aliases(
                    idx=1,
                    script_src=first_script,
                    image_src=first_img,
                    audio_src=first_aud,
                )
                scenes_meta = [{
                    "index": 1,
                    "tag": f"{tag}_s01",
                    "narration": final_script,
                    "onscreen": "",
                    "stock_query": "",
                    "image_prompt": final_script,
                    "audio_text": final_script,
                    "artifacts": {
                        "script": os.path.abspath(aliases["script"]),
                        "image": os.path.abspath(aliases["image"]),
                        "audio": os.path.abspath(aliases["audio"]),
                    },
                }]
            if not first_script:
                first_script = script_path

            subtitles_path = self._write_subtitles_srt(scenes_meta)

            # artifacts apuntan a escena 1 (compat), script "global" se mantiene
            self._write_manifest(
                script_path=first_script,
                img_path=first_img,
                aud_path=first_aud,
                scenes=scenes_meta,
                subtitles_path=subtitles_path,
            )
            self._notify("listo", total_ms, total_ms)
            return first_img, first_aud

        # Single-scene normal
        image_path = os.path.join(self.work_dir, f"image_{tag}.png")
        audio_path = os.path.join(self.work_dir, f"audio_{tag}.wav")

        self._notify("imagen", curr, total)
        try:
            img = self.image.generate(final_script, image_path)
        except Exception:
            img = self._write_fallback_png(image_path)
        curr += 1

        self._notify("audio", curr, total)
        try:
            aud = self.voice.synthesize(final_script, audio_path)
        except Exception:
            aud = self._write_fallback_wav(audio_path, text=final_script)
        curr += 1

        self._write_manifest(script_path=script_path, img_path=img, aud_path=aud, scenes=None)
        self._notify("listo", curr, total)
        return img, aud






