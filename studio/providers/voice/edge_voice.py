# -*- coding: utf-8 -*-
from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import asyncio

from studio.exceptions import ProviderError
from studio.providers.voice.base_voice import BaseVoiceProvider


class EdgeVoiceProvider(BaseVoiceProvider):
    """TTS gratuito via edge-tts (requiere: pip install edge-tts) + ffmpeg para WAV.

    - Genera MP3 con edge-tts.
    - Si output_path termina en .wav, convierte con ffmpeg.
    """

    def __init__(
        self,
        voice: str = "en-US-JennyNeural",
        rate: str = "+0%",
        volume: str = "+0%",
        sample_rate: int = 24000,
    ) -> None:
        self.voice = voice
        self.rate = rate
        self.volume = volume
        self.sample_rate = int(sample_rate)

    def validate(self) -> None:
        try:
            import edge_tts  # noqa: F401
        except Exception as e:
            raise ProviderError("EdgeVoiceProvider requiere 'edge-tts'. Instala: pip install edge-tts") from e

        # Para WAV necesitamos ffmpeg
        if shutil.which("ffmpeg") is None:
            raise ProviderError("EdgeVoiceProvider requiere ffmpeg en PATH para convertir a WAV.")

    def synthesize(self, text: str, output_path: str) -> str:
        text = str(text or "").strip()
        if not text:
            raise ValueError("text vacío")

        want_wav = os.path.splitext(output_path)[1].lower() == ".wav"

        # Lazy import
        import edge_tts  # type: ignore

        tmp_dir = tempfile.mkdtemp(prefix="studio_edge_tts_")
        tmp_mp3 = os.path.join(tmp_dir, "tmp.mp3")

        async def _run() -> None:
            comm = edge_tts.Communicate(text=text, voice=self.voice, rate=self.rate, volume=self.volume)
            await comm.save(tmp_mp3)

        try:
            asyncio.run(_run())
            os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)

            if want_wav:
                ff = shutil.which("ffmpeg")
                if not ff:
                    raise ProviderError("ffmpeg no encontrado en PATH (necesario para WAV).")

                cmd = [
                    ff, "-y",
                    "-i", tmp_mp3,
                    "-ac", "1",
                    "-ar", str(self.sample_rate),
                    output_path,
                ]
                p = subprocess.run(cmd, capture_output=True, text=True)
                if p.returncode != 0:
                    raise ProviderError(f"ffmpeg falló: {p.stderr[:400]}")
            else:
                shutil.copyfile(tmp_mp3, output_path)

            return output_path
        finally:
            shutil.rmtree(tmp_dir, ignore_errors=True)