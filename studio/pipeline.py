# -*- coding: utf-8 -*-
"""Pipeline puro de STUDIO — sin prints, sin CLI, sin I/O de consola.

El pipeline es la pieza central del sistema: recibe un texto base
(prompt/idea) y produce una imagen + un audio, delegando la generación a los
providers correspondientes.

F1.1: Si hay text provider, primero genera un "script final" desde el prompt
y usa ese script para imagen/voz. Además escribe script_<sha>.txt en work_dir.

Soporta callbacks de progreso opcionales para integración con GUIs.
"""

from __future__ import annotations


import json
import hashlib
import os
from dataclasses import dataclass, field
from typing import Callable, Optional

from studio.providers.voice.base_voice import BaseVoiceProvider
from studio.providers.image.base_image import BaseImageProvider
from studio.providers.text.base_text import BaseTextProvider


def _provider_id(p) -> str:
    if p is None:
        return ""
    return str(getattr(p, "_provider_name", p.__class__.__name__))

def _sha8(text: str) -> str:
    """Primeros 8 caracteres del SHA-256 del texto."""
    h = hashlib.sha256(text.encode("utf-8")).hexdigest()
    return h[:8]


@dataclass
class StudioPipeline:
    """Pipeline de generación multimedia.

    Si text != None, el argumento `script` de run() se interpreta como prompt,
    y el pipeline genera un script final (LLM) antes de imagen/voz.
    """

    voice: BaseVoiceProvider
    image: BaseImageProvider
    text: Optional[BaseTextProvider] = None

    work_dir: str = "."
    on_progress: Optional[Callable[[str, int, int], None]] = field(default=None, repr=False)

    def _notify(self, step: str, curr: int, total: int) -> None:
        if self.on_progress is not None:
            try:
                self.on_progress(step, curr, total)
            except Exception:
                pass

    def run(self, script: str) -> tuple[str, str]:
        """Ejecuta: (opcional) texto -> imagen -> audio.

        Args:
            script: prompt o guion base (si hay text provider, se usa como prompt).

        Returns:
            (image_path, audio_path)
        """
        prompt = str(script or "").strip()
        if not prompt:
            raise ValueError("script/prompt no puede estar vacío")

        os.makedirs(self.work_dir, exist_ok=True)

        # total pasos (para progress)
        total = 3 if self.text is not None else 2
        curr = 0

        # 1) Texto (opcional)
        final_script = prompt
        if self.text is not None:
            self._notify("texto", curr, total)
            # Nota: el provider puede tener system por defecto configurado internamente
            final_script = self.text.generate(prompt)
            curr += 1

        final_script = str(final_script or "").strip()
        if not final_script:
            raise ValueError("text provider devolvió texto vacío")

        # Hash basado en el script final (determinista)
        tag = _sha8(final_script)

        # Guardar script para puente a content_pack
        script_path = os.path.join(self.work_dir, f"script_{tag}.txt")
        with open(script_path, "w", encoding="utf-8") as f:
            f.write(final_script)

        image_path = os.path.join(self.work_dir, f"image_{tag}.png")
        audio_path = os.path.join(self.work_dir, f"audio_{tag}.wav")

        # 2) Imagen
        self._notify("imagen", curr, total)
        img = self.image.generate(final_script, image_path)
        curr += 1

        # 3) Audio
        self._notify("audio", curr, total)
        aud = self.voice.synthesize(final_script, audio_path)
        curr += 1

        # F1.2: manifest mínimo para bridge v0.3
        try:
            cfgp = str(getattr(self, "_v03_config_path", ""))
            manifest = {
                "version": "v0.3",
                "mode": "RUN",
                "work_dir": os.path.abspath(self.work_dir),
                "config_path": cfgp,
                "providers": {
                    "text": _provider_id(self.text),
                    "image": _provider_id(self.image),
                    "voice": _provider_id(self.voice),
                },
                "artifacts": {
                    "script": os.path.abspath(script_path),
                    "image": os.path.abspath(img),
                    "audio": os.path.abspath(aud),
                },
            }
            with open(os.path.join(self.work_dir, "manifest_v03.json"), "w", encoding="utf-8") as f:
                f.write(json.dumps(manifest, ensure_ascii=False, indent=2))
        except Exception:
            pass

        self._notify("listo", curr, total)
        return img, aud
