# -*- coding: utf-8 -*-
"""Core de alto nivel.

Nota: en v0.3 el core provee un contenedor simple para el pipeline.
No importa CLI ni hace I/O de consola.
"""

from __future__ import annotations

from dataclasses import dataclass

from studio.pipeline import StudioPipeline


@dataclass
class StudioCore:
    pipeline: StudioPipeline

    def run(self, script: str) -> tuple[str, str]:
        return self.pipeline.run(script)