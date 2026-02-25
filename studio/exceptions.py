# -*- coding: utf-8 -*-

class StudioError(Exception):
    """Error base del núcleo STUDIO."""


class ProviderError(StudioError):
    """Errores relacionados a providers."""