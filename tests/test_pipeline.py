# -*- coding: utf-8 -*-

import os
import sys
import tempfile
import unittest

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


class TestStudioPipeline(unittest.TestCase):
    def test_run_crea_archivos_y_retorna_paths(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = StudioPipeline(voice=_DummyVoice(), image=_DummyImage(), work_dir=tmp)
            img, aud = p.run("hola")
            self.assertTrue(os.path.isfile(img))
            self.assertTrue(os.path.isfile(aud))
            self.assertIn("image_", os.path.basename(img))
            self.assertIn("audio_", os.path.basename(aud))


if __name__ == "__main__":
    unittest.main(verbosity=2)