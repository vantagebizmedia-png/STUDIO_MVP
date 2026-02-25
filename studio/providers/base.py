# -*- coding: utf-8 -*-

class BaseProvider:
    """Interfaz base opcional para providers."""

    def validate(self) -> None:
        """Levanta excepción si el provider no está listo para usar."""
        raise NotImplementedError