# -*- coding: utf-8 -*-

import os
import sys
import tempfile
import unittest
import json
import re
from pathlib import Path

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from studio.pipeline import StudioPipeline
from studio.providers.voice.base_voice import BaseVoiceProvider
from studio.providers.image.base_image import BaseImageProvider


class _DummyVoice(BaseVoiceProvider):
    def validate(self) -> None:
        return

    def synthesize(self, text: str, output_path: str) -> str:
        with open(output_path, "wb") as f:
            f.write(b"dummy")
        return output_path


class _DummyImage(BaseImageProvider):
    def validate(self) -> None:
        return

    def generate(self, prompt: str, output_path: str) -> str:
        with open(output_path, "wb") as f:
            f.write(b"dummy")
        return output_path


class _FailVoice(BaseVoiceProvider):
    def validate(self) -> None:
        return

    def synthesize(self, text: str, output_path: str) -> str:
        raise RuntimeError("forced voice failure")


class _FailImage(BaseImageProvider):
    def validate(self) -> None:
        return

    def generate(self, prompt: str, output_path: str) -> str:
        raise RuntimeError("forced image failure")


class TestStudioPipeline(unittest.TestCase):
    @staticmethod
    def _count_sentences(text: str) -> int:
        parts = [s.strip() for s in re.split(r"(?<=[\.\!\?])\s+", str(text or "").strip()) if s.strip()]
        if parts:
            return len(parts)
        return 1 if str(text or "").strip() else 0

    def test_run_crea_archivos_y_retorna_paths(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = StudioPipeline(voice=_DummyVoice(), image=_DummyImage(), work_dir=tmp)
            img, aud = p.run("hola")
            self.assertTrue(os.path.isfile(img))
            self.assertTrue(os.path.isfile(aud))
            self.assertIn("image_", os.path.basename(img))
            self.assertIn("audio_", os.path.basename(aud))

    def test_multiscene_keeps_legacy_and_creates_stable_aliases(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = StudioPipeline(
                voice=_DummyVoice(),
                image=_DummyImage(),
                work_dir=tmp,
                multiscene=True,
                max_scenes=3,
                scene_split="dash",
            )
            p.run("NARRACION: uno\n---\nNARRACION: dos\n---\nNARRACION: tres")

            wd = Path(tmp)
            for idx in (1, 2, 3):
                legacy_script = list(wd.glob(f"script_*_s{idx:02d}.txt"))
                legacy_image = list(wd.glob(f"image_*_s{idx:02d}.png"))
                legacy_audio = list(wd.glob(f"audio_*_s{idx:02d}.wav"))
                self.assertTrue(legacy_script, f"falta script legacy escena {idx}")
                self.assertTrue(legacy_image, f"falta image legacy escena {idx}")
                self.assertTrue(legacy_audio, f"falta audio legacy escena {idx}")

                alias_dir = wd / "artifacts" / "scenes" / f"scene_{idx:02d}"
                self.assertTrue((alias_dir / "script.txt").exists())
                self.assertTrue((alias_dir / "image.png").exists())
                self.assertTrue((alias_dir / "audio.wav").exists())
                self.assertGreater((alias_dir / "script.txt").stat().st_size, 0)
                self.assertGreater((alias_dir / "image.png").stat().st_size, 0)
                self.assertGreater((alias_dir / "audio.wav").stat().st_size, 0)
                script_txt = (alias_dir / "script.txt").read_text(encoding="utf-8")
                self.assertIn("NARRACION:", script_txt)
                self.assertIn("ONSCREEN:", script_txt)
                self.assertIn("STOCK_QUERY:", script_txt)

            manifest = json.loads((wd / "manifest_v03.json").read_text(encoding="utf-8"))
            for scene in manifest.get("scenes") or []:
                self.assertIn("narration", scene)
                self.assertIn("onscreen", scene)
                self.assertIn("stock_query", scene)
                self.assertLessEqual(self._count_sentences(scene.get("narration", "")), 3)
                self.assertLessEqual(len(str(scene.get("onscreen", "")).split()), 10)
                sq = str(scene.get("stock_query", ""))
                self.assertLessEqual(len(sq.split()), 6)
                self.assertRegex(sq, r"^[a-z0-9áéíóúüñ ]+$")
                arts = scene.get("artifacts") or {}
                for k in ("script", "image", "audio"):
                    raw = str(arts.get(k) or "")
                    self.assertTrue(raw)
                    self.assertFalse(Path(raw).is_absolute())

    def test_multiscene_provider_error_uses_deterministic_fallback(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = StudioPipeline(
                voice=_FailVoice(),
                image=_FailImage(),
                work_dir=tmp,
                multiscene=True,
                max_scenes=2,
                scene_split="dash",
            )
            img, aud = p.run("NARRACION: uno\n---\nNARRACION: dos")
            self.assertTrue(Path(img).exists())
            self.assertTrue(Path(aud).exists())

            wd = Path(tmp)
            for idx in (1, 2):
                alias_dir = wd / "artifacts" / "scenes" / f"scene_{idx:02d}"
                self.assertTrue((alias_dir / "image.png").exists())
                self.assertTrue((alias_dir / "audio.wav").exists())
                self.assertGreater((alias_dir / "image.png").stat().st_size, 0)
                self.assertGreater((alias_dir / "audio.wav").stat().st_size, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
