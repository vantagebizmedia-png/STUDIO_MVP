# -*- coding: utf-8 -*-

import os
import tempfile
import unittest

from studio.builders import build_demo_pipeline, build_legacy_pipeline, write_demo_providers_json


class TestBuilders(unittest.TestCase):
    def test_demo_builder(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = build_demo_pipeline(work_dir=tmp)
            img, aud = p.run("hola")
            self.assertTrue(os.path.isfile(img))
            self.assertTrue(os.path.isfile(aud))

    def test_legacy_builder_dry(self):
        # requiere que exista app/ en el repo
        if not os.path.isdir("app"):
            self.skipTest("no hay app/ en este entorno")

        with tempfile.TemporaryDirectory() as tmp:
            root = os.path.join(tmp, "legacy")
            ws = os.path.join(root, "workspace")
            cfg = os.path.join(root, "providers_demo.json")
            out = os.path.join(root, "artifacts")

            write_demo_providers_json(cfg)
            p = build_legacy_pipeline(work_dir=out, providers_json=cfg, workspace=ws)
            img, aud = p.run("hola")
            self.assertTrue(os.path.isfile(img))
            self.assertTrue(os.path.isfile(aud))


if __name__ == "__main__":
    unittest.main(verbosity=2)