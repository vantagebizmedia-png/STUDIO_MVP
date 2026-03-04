import os
import wave
import struct


class DemoVoiceProvider:
    """
    Provider determinista de voz para DEMO/SMOKE:
    - Escribe un WAV PCM mono 16-bit con SILENCIO.
    - Duración configurable por env var STUDIO_DEMO_VOICE_S (float).
      Default: 20.0s.
    - Sample rate configurable por STUDIO_DEMO_VOICE_SR (int). Default: 22050.
    """

    def __init__(self) -> None:
        pass

    def synthesize(self, text: str, out_path: str) -> str:
        duration_s = 20.0
        sr = 22050

        try:
            v = os.environ.get("STUDIO_DEMO_VOICE_S", "").strip()
            if v:
                duration_s = float(v)
        except Exception:
            pass

        try:
            v = os.environ.get("STUDIO_DEMO_VOICE_SR", "").strip()
            if v:
                sr = int(float(v))
        except Exception:
            pass

        if duration_s < 0.2:
            duration_s = 0.2
        if sr < 8000:
            sr = 8000

        nframes = int(round(duration_s * sr))
        if nframes < 1:
            nframes = 1

        os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)

        with wave.open(out_path, "wb") as wf:
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

        return out_path
