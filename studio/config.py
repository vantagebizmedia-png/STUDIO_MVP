# -*- coding: utf-8 -*-
"""Config del core de STUDIO.

StudioConfig es el objeto canónico de configuración que se puede:
- Crear a mano (via código)
- Cargar desde un dict / JSON
- Pasar a build_pipeline_from_config() para construir un StudioPipeline listo.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass
from typing import Any, Optional


@dataclass(frozen=True)
class ProviderSpec:
    """Identifica un provider y su configuración opcional.

    Attributes:
        name: ID del provider en el Registry (ej: 'edge_voice', 'hf_image').
        config: Diccionario de parámetros específicos del provider (opcional).
    """

    name: str
    config: Optional[dict] = None


@dataclass(frozen=True)
class StudioConfig:
    """Config de alto nivel para construir el pipeline.

    Contiene la especificación de los tres providers (voz, imagen, texto opcional)
    más el directorio de trabajo.

    Attributes:
        voice: Especificación del provider de voz/TTS.
        image: Especificación del provider de imagen.
        text: Especificación del provider de texto/LLM (opcional).
        work_dir: Directorio donde se guardarán los artefactos generados.

    Example::

        cfg = StudioConfig(
            voice=ProviderSpec("edge_voice", {"voice": "es-ES-AlvaroNeural"}),
            image=ProviderSpec("hf_image", {"model": "black-forest-labs/FLUX.1-schnell"}),
            work_dir="_output/artifacts",
        )
        pipeline = build_pipeline_from_config(cfg)
        img, aud = pipeline.run("La disciplina es el camino al exito")
    """

    voice: ProviderSpec
    image: ProviderSpec
    text: Optional[ProviderSpec] = None
    work_dir: str = "_studio_out/artifacts"

    @classmethod
    def from_dict(cls, obj: dict) -> "StudioConfig":
        """Construye un StudioConfig desde un diccionario (como el JSON v0.3).

        Args:
            obj: Diccionario con claves 'voice', 'image', 'text' (opcional),
                 y 'work_dir' (opcional).

        Returns:
            StudioConfig listo para usar.

        Raises:
            ValueError: Si falta 'voice' o 'image'.
        """

        def _spec(key: str) -> Optional[ProviderSpec]:
            d = obj.get(key)
            if not d:
                return None
            if isinstance(d, str):
                return ProviderSpec(name=d)
            return ProviderSpec(
                name=str(d.get("provider", "") or d.get("name", "")),
                config=d.get("config") or None,
            )

        v = _spec("voice")
        i = _spec("image")
        if not v or not v.name:
            raise ValueError("StudioConfig.from_dict: falta 'voice.provider'")
        if not i or not i.name:
            raise ValueError("StudioConfig.from_dict: falta 'image.provider'")

        return cls(
            voice=v,
            image=i,
            text=_spec("text"),
            work_dir=str(obj.get("work_dir") or "_studio_out/artifacts"),
        )

    @classmethod
    def from_json(cls, path: str) -> "StudioConfig":
        """Carga un StudioConfig desde un archivo JSON v0.3.

        Args:
            path: Ruta al archivo JSON de configuración.

        Returns:
            StudioConfig listo para usar.

        Raises:
            FileNotFoundError: Si el archivo no existe.
            ValueError: Si el JSON tiene formato inválido.
        """
        path = os.path.abspath(path)
        with open(path, "r", encoding="utf-8-sig") as f:
            obj = json.load(f)
        return cls.from_dict(obj)


def build_pipeline_from_config(cfg: StudioConfig):
    """Construye un StudioPipeline desde un StudioConfig.

    Usa el Registry para instanciar los providers y valida cada uno
    antes de retornar el pipeline.

    Args:
        cfg: Configuración del pipeline.

    Returns:
        StudioPipeline listo para llamar a .run().

    Raises:
        StudioError: Si algún provider no está registrado o no pasa validate().
    """
    from studio.registry import build_provider
    from studio.pipeline import StudioPipeline

    voice = build_provider(cfg.voice.name, cfg.voice.config or {})
    image = build_provider(cfg.image.name, cfg.image.config or {})

    if hasattr(voice, "validate"):
        voice.validate()
    if hasattr(image, "validate"):
        image.validate()

    return StudioPipeline(
        voice=voice,
        image=image,
        work_dir=cfg.work_dir,
    )
