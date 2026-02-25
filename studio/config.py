# -*- coding: utf-8 -*-
"""Config mínima del core.

En v0.3 el core NO depende de archivos externos.
La carga desde JSON/ENV se añadirá en una fase posterior, sin tocar el pipeline.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional


@dataclass(frozen=True)
class ProviderSpec:
    """Identifica un provider y su configuración (si aplica)."""

    name: str
    config: Optional[dict] = None


@dataclass(frozen=True)
class StudioConfig:
    """Config de alto nivel para construir el pipeline."""

    voice: ProviderSpec
    image: ProviderSpec