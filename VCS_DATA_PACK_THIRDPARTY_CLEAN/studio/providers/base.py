# -*- coding: utf-8 -*-
"""Interfaces base para todos los providers de STUDIO.

Un provider encapsula el acceso a un servicio externo (API remota, modelo
local, etc.) y expone una interfaz uniforme al pipeline.

Todos los providers concretos deben heredar de la clase base correspondiente
e implementar todos los métodos abstractos.
"""

from __future__ import annotations

from abc import ABC, abstractmethod


class BaseProvider(ABC):
    """Interfaz base para todos los providers de STUDIO.

    Define el contrato mínimo que debe cumplir cualquier provider:
    un método validate() que comprueba la disponibilidad del servicio
    sin hacer operaciones costosas (sin generar audio, imágenes, etc.).

    Example::

        class MyProvider(BaseProvider):
            def validate(self) -> None:
                if not shutil.which("my_tool"):
                    raise ProviderError("my_tool no está en PATH")
    """

    @abstractmethod
    def validate(self) -> None:
        """Verifica que el provider está listo para operar.

        Comprueba: dependencias instaladas, variables de entorno requeridas,
        conectividad básica. No debe hacer llamadas costosas (no genera
        imágenes, audio, ni consume créditos).

        Raises:
            ProviderError: Si el provider no está correctamente configurado
                o si falta alguna dependencia requerida.
        """
