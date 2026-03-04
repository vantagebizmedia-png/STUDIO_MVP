# -*- coding: utf-8 -*-
# app/providers/_utils.py  Utilidades compartidas entre providers
#
# Este módulo centraliza funciones comunes que antes estaban duplicadas
# en image_provider.py y voice_provider.py.

import os
import re
import json
import hashlib
from typing import Any, Dict, Optional


def read_json(path: str) -> Any:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def write_json(path: str, obj: Any) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)
        f.write("\n")


def stable_dumps(obj: Any) -> str:
    return json.dumps(obj, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256_hex(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def sub_env(s: str) -> str:
    """Sustituye ${ENV:VAR} por el valor de la variable de entorno."""
    def repl(m: re.Match) -> str:
        return os.environ.get(m.group(1), "")
    return re.sub(r"\$\{ENV:([A-Z0-9_]+)\}", repl, str(s))


def find_project_root() -> str:
    """Sube desde el directorio actual buscando config/providers.json."""
    here = os.path.abspath(os.path.dirname(__file__))
    for _ in range(10):
        if os.path.exists(os.path.join(here, "config", "providers.json")):
            return here
        here = os.path.dirname(here)
    return os.getcwd()


def apply_template(obj: Any, ctx: Dict[str, Any]) -> Any:
    """Reemplaza {{key}} y ${ENV:VAR} en strings, dicts y listas recursivamente."""
    if isinstance(obj, str):
        s = sub_env(obj)
        for k, v in ctx.items():
            s = s.replace("{{" + k + "}}", str(v))
        return s
    if isinstance(obj, dict):
        return {k: apply_template(v, ctx) for k, v in obj.items()}
    if isinstance(obj, list):
        return [apply_template(x, ctx) for x in obj]
    return obj


def extract_path(obj: Any, path: str) -> Optional[Any]:
    """Navega un objeto anidado usando una ruta tipo 'data.0.b64_json'."""
    cur = obj
    for part in path.split("."):
        if isinstance(cur, dict):
            if part not in cur:
                return None
            cur = cur[part]
        elif isinstance(cur, list):
            try:
                cur = cur[int(part)]
            except (ValueError, IndexError):
                return None
        else:
            return None
    return cur
