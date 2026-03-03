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
def _write_fallback_wav(self, path: str, *, duration_s: float = 20.0, sr: int = 22050) -> str:
    """
    Fallback determinista (sin TTS real):
    - Genera un WAV PCM mono 16-bit con SILENCIO (0) de duración configurable.
    - Importante: duration_s por defecto es largo para que total_audio_ms no sea 1000ms.
    - Permite override por env var STUDIO_FALLBACK_AUDIO_S (float).
    """
    import os
    import wave
    import struct

    # Override opcional por environment (determinista si el operador lo fija)
    try:
        env_s = os.environ.get("STUDIO_FALLBACK_AUDIO_S", "").strip()
        if env_s:
            duration_s = float(env_s)
    except Exception:
        pass

    duration_s = float(duration_s or 0.0)
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

        chunk = 4096
        zero = struct.pack("<h", 0)
        left = nframes
        while left > 0:
            take = chunk if left > chunk else left
            wf.writeframes(zero * take)
            left -= take

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

        ordered = sorted(
            [dict(s or {}) for s in (scenes or []) if int((s or {}).get("index", 0) or 0) >= 1],
            key=lambda x: int(x.get("index", 0) or 0),
        )
        scene_duration_ms = 2500
        blocks: list[str] = []
        for pos, scene in enumerate(ordered):
            idx = int(scene.get("index", 0) or 0) or (pos + 1)
            start_ms = pos * scene_duration_ms
            end_ms = (pos + 1) * scene_duration_ms
            text = _sanitize_subtitle_text(str(scene.get("narration", "") or ""), idx)
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
        v0.3 manifest writer (bridge):
        - Mantiene artifacts + scenes legacy (compat)
        - Añade scenes_v03 + scene_builder_v03 (Scene Builder LIVE)
        - NO rompe export actual porque scenes_v03 referencia paths ya presentes en scenes[].artifacts
        """
        try:
            base_dir = os.path.abspath(self.work_dir or ".")

            def _abs_from_rel(relp: str) -> str:
                p = str(relp or "").strip()
                if not p:
                    return ""
                if os.path.isabs(p):
                    return p
                return os.path.abspath(os.path.join(base_dir, p))

            def _wav_ms(path_abs: str) -> int:
                try:
                    if not path_abs:
                        return 0
                    if not os.path.exists(path_abs):
                        return 0
                    with wave.open(path_abs, "rb") as wf:
                        fr = wf.getframerate()
                        if fr <= 0:
                            return 0
                        frames = wf.getnframes()
                        sec = frames / float(fr)
                        ms = int(round(sec * 1000.0))
                        return max(0, ms)
                except Exception:
                    return 0

            manifest: dict[str, Any] = {
                "version": "v0.3",
                "mode": "RUN",
                "work_dir": ".",
                "config_path": _rel_to_base(str(self._v03_config_path or ""), base_dir),
                "providers": {
                    "text": _provider_id(self.text),
                    "image": _provider_id(self.image),
                    "voice": _provider_id(self.voice),
                },
                "artifacts": {
                    "script": _rel_to_base(script_path, base_dir),
                    "image": _rel_to_base(img_path, base_dir),
                    "audio": _rel_to_base(aud_path, base_dir),
                },
            }

            sub_rel = _rel_to_base(str(subtitles_path or ""), base_dir)
            if sub_rel:
                manifest["artifacts"]["subtitles"] = sub_rel

            scenes_rel: list[dict] = []
            if scenes:
                for s in scenes:
                    row = dict(s or {})
                    arts = dict(row.get("artifacts") or {})
                    row["artifacts"] = {
                        "script": _rel_to_base(str(arts.get("script", "")), base_dir),
                        "image": _rel_to_base(str(arts.get("image", "")), base_dir),
                        "audio": _rel_to_base(str(arts.get("audio", "")), base_dir),
                    }
                    scenes_rel.append(row)
                manifest["scenes"] = scenes_rel

            # -----------------------------
            # Scene Builder v03 (LIVE) -> scenes_v03[]
            # -----------------------------
            scenes_v03: list[dict] = []
            total_ms = 0
            cursor = 0

            if scenes_rel:
                # Multi-scene: timeline = suma de duraciones de audios por escena
                for i, sc in enumerate(scenes_rel):
                    idx1 = int(sc.get("index") or (i + 1))
                    sid = f"s{idx1:02d}"

                    narration = str(sc.get("narration") or sc.get("audio_text") or "").strip()
                    onscreen = str(sc.get("onscreen") or "").strip()
                    q = str(sc.get("stock_query") or "").strip()
                    if not q:
                        q = narration or "concepto abstracto"

                    a_rel = str((sc.get("artifacts") or {}).get("audio") or "")
                    a_abs = _abs_from_rel(a_rel)
                    dur = _wav_ms(a_abs)

                    start_ms = int(cursor)
                    end_ms = int(cursor + dur) if dur > 0 else int(cursor)

                    scenes_v03.append(
                        {
                            "id": sid,
                            "index": i,
                            "start_ms": start_ms,
                            "end_ms": end_ms,
                            "duration_ms": int(max(0, end_ms - start_ms)),
                            "script_text": narration or onscreen or f"Escena {idx1:02d}",
                            "image_query": q,
                            "assets": {
                                # OJO: apuntamos a paths existentes en scenes legacy
                                "image": str((sc.get("artifacts") or {}).get("image") or ""),
                                "audio_clip": str((sc.get("artifacts") or {}).get("audio") or ""),
                                "image_meta": {
                                    "provider": "pixabay" if "pixabay" in str(_provider_id(self.image)).lower() else "image_provider",
                                    "cache_hit": False,
                                    "cache_key": "",
                                    "query": q,
                                },
                            },
                        }
                    )

                    cursor = end_ms
                total_ms = int(cursor)

            else:
                # Single scene: usa artifacts globales
                a_rel = str((manifest.get("artifacts") or {}).get("audio") or "")
                a_abs = _abs_from_rel(a_rel)
                total_ms = _wav_ms(a_abs)

                # intentamos leer el script global
                scr_rel = str((manifest.get("artifacts") or {}).get("script") or "")
                scr_abs = _abs_from_rel(scr_rel)
                script_txt = ""
                try:
                    if scr_abs and os.path.exists(scr_abs):
                        with open(scr_abs, "r", encoding="utf-8", errors="ignore") as f:
                            script_txt = (f.read() or "").strip()
                except Exception:
                    script_txt = ""

                if not script_txt:
                    script_txt = "Escena 01."

                scenes_v03 = [
                    {
                        "id": "s01",
                        "index": 0,
                        "start_ms": 0,
                        "end_ms": int(total_ms if total_ms > 0 else 0),
                        "duration_ms": int(total_ms if total_ms > 0 else 0),
                        "script_text": script_txt,
                        "image_query": "concepto abstracto",
                        "assets": {
                            "image": str((manifest.get("artifacts") or {}).get("image") or ""),
                            "audio_clip": str((manifest.get("artifacts") or {}).get("audio") or ""),
                            "image_meta": {
                                "provider": "pixabay" if "pixabay" in str(_provider_id(self.image)).lower() else "image_provider",
                                "cache_hit": False,
                                "cache_key": "",
                                "query": "concepto abstracto",
                            },
                        },
                    }
                ]

            # Validación mínima (no rompe)
            if isinstance(scenes_v03, list) and len(scenes_v03) >= 1:
                manifest["scenes_v03"] = scenes_v03
                manifest["scene_builder_v03"] = {
                    "max_scenes": int(getattr(self, "max_scenes", 1) or 1),
                    "total_audio_ms": int(total_ms or 0),
                    "note": "generated in LIVE by studio/pipeline.py; scenes legacy preserved",
                }

            outp = os.path.join(self.work_dir, "manifest_v03.json")
            with open(outp, "w", encoding="utf-8") as f:
                f.write(json.dumps(manifest, ensure_ascii=False, indent=2))
        except Exception:
            pass
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
                    aud = self._write_fallback_wav(ap)
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
                    first_aud = self._write_fallback_wav(first_aud)
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
        img = self.image.generate(final_script, image_path)
        curr += 1

        self._notify("audio", curr, total)
        aud = self.voice.synthesize(final_script, audio_path)
        curr += 1

        self._write_manifest(script_path=script_path, img_path=img, aud_path=aud, scenes=None)
        self._notify("listo", curr, total)
        return img, aud





