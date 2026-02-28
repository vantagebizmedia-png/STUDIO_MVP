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
import time
from dataclasses import dataclass, field
from typing import Callable, Optional, Any

from studio.providers.voice.base_voice import BaseVoiceProvider
from studio.providers.image.base_image import BaseImageProvider
from studio.providers.text.base_text import BaseTextProvider

from studio.scene_builder import build_scenes


def _provider_id(p: Any) -> str:
    if p is None:
        return ""
    return str(getattr(p, "_provider_name", p.__class__.__name__))


def _sha8(text: str) -> str:
    h = hashlib.sha256(text.encode("utf-8")).hexdigest()
    return h[:8]


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

        out = self.text.generate(prompt)
        if cache_on:
            try:
                payload = {
                    "version": "v0.3",
                    "provider": provider_name,
                    "config": tcfg,
                    "prompt": prompt,
                    "output": out,
                    "created_at_unix": int(time.time()),
                }
                with open(cache_path, "w", encoding="utf-8") as f:
                    f.write(json.dumps(payload, ensure_ascii=False, indent=2))
            except Exception:
                pass

        return str(out or "").strip()

    def _write_manifest(self, *, script_path: str, img_path: str, aud_path: str, scenes: list[dict] | None = None) -> None:
        try:
            manifest = {
                "version": "v0.3",
                "mode": "RUN",
                "work_dir": os.path.abspath(self.work_dir),
                "config_path": str(self._v03_config_path or ""),
                "providers": {
                    "text": _provider_id(self.text),
                    "image": _provider_id(self.image),
                    "voice": _provider_id(self.voice),
                },
                "artifacts": {
                    "script": os.path.abspath(script_path),
                    "image": os.path.abspath(img_path),
                    "audio": os.path.abspath(aud_path),
                },
            }
            if scenes:
                manifest["scenes"] = scenes
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

        tag = _sha8(final_script)

        # script "global" siempre
        script_path = os.path.join(self.work_dir, f"script_{tag}.txt")
        with open(script_path, "w", encoding="utf-8") as f:
            f.write(final_script)

        # Multi-scene (si aplica)
        if bool(getattr(self, "multiscene", False)) and int(getattr(self, "max_scenes", 1) or 1) > 1:
            scene_specs = build_scenes(final_script, max_scenes=int(self.max_scenes), split_mode=str(self.scene_split), base_tag=tag)
            if not scene_specs:
                scene_specs = build_scenes(final_script, max_scenes=1, split_mode="auto", base_tag=tag)

            scenes_meta: list[dict] = []
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

                # Guardamos un script por escena (estructurado) para trazabilidad
                sp = os.path.join(self.work_dir, f"script_{stag}.txt")
                with open(sp, "w", encoding="utf-8") as f:
                    if narration:
                        f.write(f"NARRACION: {narration}\n")
                    if onscreen:
                        f.write(f"ONSCREEN: {onscreen}\n")
                    if stock_query:
                        f.write(f"STOCK_QUERY: {stock_query}\n")

                ip = os.path.join(self.work_dir, f"image_{stag}.png")
                ap = os.path.join(self.work_dir, f"audio_{stag}.wav")

                image_prompt = stock_query or narration
                audio_text = narration or stock_query

                self._notify(f"imagen_s{idx:02d}", curr_ms, total_ms)
                img = self.image.generate(image_prompt, ip)
                curr_ms += 1

                self._notify(f"audio_s{idx:02d}", curr_ms, total_ms)
                aud = self.voice.synthesize(audio_text, ap)
                curr_ms += 1

                if idx == 1:
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
                        "script": os.path.abspath(sp),
                        "image": os.path.abspath(img),
                        "audio": os.path.abspath(aud),
                    }
                })
            if not first_img:
                # fallback si por algún motivo no generó escena 1
                first_img = os.path.join(self.work_dir, f"image_{tag}.png")
                first_aud = os.path.join(self.work_dir, f"audio_{tag}.wav")
                first_img = self.image.generate(final_script, first_img)
                first_aud = self.voice.synthesize(final_script, first_aud)

            # artifacts apuntan a escena 1 (compat), script "global" se mantiene
            self._write_manifest(script_path=script_path, img_path=first_img, aud_path=first_aud, scenes=scenes_meta)
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
