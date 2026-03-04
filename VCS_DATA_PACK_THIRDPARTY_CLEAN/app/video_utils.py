# -*- coding: utf-8 -*-
# app/video_utils.py  Funciones puras del pipeline de video (sin dependencias externas)
#
# Separadas de video_render.py para poder testearlas sin necesitar moviepy instalado.

import math
import json
import hashlib
from typing import Any, List, Optional, Sequence, Union


def stable_dumps(obj: Any) -> str:
    return json.dumps(obj, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256_hex(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def normalize_motion_profiles(
    motion_profile: Union[str, Sequence[str], None], n: int
) -> List[str]:
    """Normaliza motion_profile a una lista de longitud n."""
    if n <= 0:
        return []
    if motion_profile is None:
        return ["none"] * n
    if isinstance(motion_profile, (list, tuple)):
        profs = [str(p or "none") for p in motion_profile]
    else:
        profs = [str(motion_profile or "none")] * n

    if len(profs) < n:
        profs.extend([profs[-1]] * (n - len(profs)))
    return profs[:n]


def normalize_motion_strengths(
    motion_strength: Union[float, Sequence[float], None], n: int, default: float
) -> List[float]:
    """Normaliza motion_strength a una lista de floats de longitud n."""
    if n <= 0:
        return []
    if motion_strength is None:
        return [float(default)] * n

    if isinstance(motion_strength, (list, tuple)):
        arr: List[float] = []
        for x in motion_strength:
            try:
                arr.append(float(x))
            except Exception:
                arr.append(float(default))
        if not arr:
            arr = [float(default)]
        if len(arr) < n:
            arr.extend([arr[-1]] * (n - len(arr)))
        return arr[:n]

    try:
        v = float(motion_strength)
    except Exception:
        v = float(default)
    return [v] * n


def build_vf_filters(grain_amount: float, vignette: float, seed_int: int) -> str:
    """
    Construye el string -vf para FFmpeg:
    - grain: noise=alls=N:allf=t+u:all_seed=...
    - vignette: vignette=<angle>
    """
    vf: List[str] = []

    g = float(grain_amount) if grain_amount else 0.0
    if g > 0.0:
        alls = int(round(max(0.0, min(100.0, g * 1000.0))))
        vf.append(f"noise=alls={alls}:allf=t+u:all_seed={int(seed_int) & 0x7fffffff}")

    v = float(vignette) if vignette else 0.0
    if v > 0.0:
        angle = (math.pi / 5.0) + (v * (math.pi / 3.0))
        angle = max(0.0, min(math.pi / 2.0, angle))
        vf.append(f"vignette={angle:.6f}")

    return ",".join(vf)


# ---- Funciones de pipeline (sin dependencias externas) ----

import os
from typing import Dict


def project_root_from(file_path: str) -> str:
    """Devuelve la raíz del proyecto (carpeta que contiene 'app/')."""
    return os.path.abspath(os.path.join(os.path.dirname(file_path), ".."))


def abs_if_exists(path: str, base_dir: str = None) -> str:
    """Devuelve ruta absoluta si el archivo existe, si no devuelve str vacío."""
    p = (path or "").strip()
    if not p:
        return ""
    if not os.path.isabs(p) and base_dir:
        p = os.path.join(base_dir, p)
    p = os.path.abspath(p)
    return p if os.path.isfile(p) else ""


def ensure_dirs(run_dir: str) -> Dict[str, str]:
    """Crea y devuelve las carpetas de trabajo para un run."""
    render_dir = os.path.join(run_dir, "render")
    images_dir = os.path.join(render_dir, "images")
    audio_dir = os.path.join(render_dir, "audio")
    os.makedirs(images_dir, exist_ok=True)
    os.makedirs(audio_dir, exist_ok=True)
    return {"render_dir": render_dir, "images_dir": images_dir, "audio_dir": audio_dir}
