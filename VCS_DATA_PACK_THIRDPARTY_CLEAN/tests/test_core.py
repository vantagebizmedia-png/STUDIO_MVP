# -*- coding: utf-8 -*-

import os
import sys
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))


class TestCoreImports(unittest.TestCase):
    def test_imports_basicos(self):
        import studio
        from studio.core import StudioCore
        from studio.pipeline import StudioPipeline

        self.assertTrue(hasattr(studio, "__version__"))
        self.assertTrue(callable(StudioCore))
        self.assertTrue(callable(StudioPipeline))


if __name__ == "__main__":
    unittest.main(verbosity=2)