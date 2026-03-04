import json
import os
import re
import subprocess
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Optional, Tuple


@dataclass
class PixabayHit:
    id: int
    page_url: str
    video_url: str
    width: int
    height: int
    size: int


def _repo_root() -> Path:
    # studio/ -> repo root
    return Path(__file__).resolve().parents[1]


def _load_pixabay_key() -> str:
    repo = _repo_root()
    cfg = repo / "config" / "providers.local.json"
    if not cfg.exists():
        raise RuntimeError(f"Falta config local: {cfg} (crea providers.local.json con pixabay.api_key)")
    obj = json.loads(cfg.read_text(encoding="utf-8"))
    key = (((obj.get("pixabay") or {}).get("api_key") or "").strip())
    if not key or key == "PON_AQUI_TU_PIXABAY_KEY":
        raise RuntimeError("Pixabay api_key no configurada en config/providers.local.json")
    return key


def _http_get_json(url: str, timeout: int = 30) -> Dict[str, Any]:
    req = urllib.request.Request(url, headers={"User-Agent": "STUDIO_MVP/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        data = r.read()
    return json.loads(data.decode("utf-8", errors="replace"))


def _sanitize_query(q: str) -> str:
    q = (q or "").strip()
    q = re.sub(r"\s+", " ", q)
    return q[:120]


def _pick_best_video(hit: Dict[str, Any]) -> Optional[PixabayHit]:
    # Pixabay videos: hit["videos"] has qualities: large, medium, small, tiny (varía)
    vids = hit.get("videos") or {}
    candidates = []
    for k, v in vids.items():
        if not isinstance(v, dict):
            continue
        url = (v.get("url") or "").strip()
        w = int(v.get("width") or 0)
        h = int(v.get("height") or 0)
        size = int(v.get("size") or 0)
        if not url or w <= 0 or h <= 0:
            continue
        # filtro: no bajar >1080p (por performance/costo de IO)
        if max(w, h) > 1920 or min(w, h) > 1080:
            continue
        candidates.append((max(w, h), size, PixabayHit(
            id=int(hit.get("id") or 0),
            page_url=str(hit.get("pageURL") or ""),
            video_url=url,
            width=w,
            height=h,
            size=size,
        )))
    if not candidates:
        return None
    # mejor: mayor resolución, luego mayor size (proxy de bitrate/calidad)
    candidates.sort(key=lambda t: (t[0], t[1]), reverse=True)
    return candidates[0][2]


def search_video(query: str, *, per_page: int = 10) -> Optional[PixabayHit]:
    key = _load_pixabay_key()
    q = _sanitize_query(query)
    if not q:
        return None

    params = {
        "key": key,
        "q": q,
        "video_type": "film",
        "safesearch": "true",
        "per_page": str(max(3, min(int(per_page), 50))),
        "page": "1",
    }
    url = "https://pixabay.com/api/videos/?" + urllib.parse.urlencode(params)
    obj = _http_get_json(url)
    hits = obj.get("hits") or []
    if not isinstance(hits, list) or not hits:
        return None

    for h in hits:
        if isinstance(h, dict):
            best = _pick_best_video(h)
            if best:
                return best
    return None


def download(url: str, out_path: Path, *, timeout: int = 120) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": "STUDIO_MVP/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        data = r.read()
    out_path.write_bytes(data)


def _ffmpeg() -> str:
    # asume ffmpeg en PATH
    return "ffmpeg"


def normalize_to_9x16(in_path: Path, out_path: Path) -> None:
    """
    Normaliza a 1080x1920, 30fps, yuv420p, audio AAC si existe.
    Si es horizontal, crop centrado. Si es vertical, scale+pad/crop según.
    """
    out_path.parent.mkdir(parents=True, exist_ok=True)

    vf = (
        "scale=1080:1920:force_original_aspect_ratio=increase,"
        "crop=1080:1920"
    )

    cmd = [
        _ffmpeg(),
        "-y",
        "-hide_banner",
        "-loglevel", "error",
        "-i", str(in_path),
        "-vf", vf,
        "-r", "30",
        "-c:v", "libx264",
        "-crf", "23",
        "-pix_fmt", "yuv420p",
        "-movflags", "+faststart",
        "-c:a", "aac",
        "-b:a", "192k",
        str(out_path),
    ]
    subprocess.check_call(cmd)


def fetch_and_normalize(query: str, *, out_dir: Path) -> Tuple[Path, Optional[PixabayHit]]:
    """
    Devuelve path del mp4 normalizado y el hit (para metadata).
    """
    out_dir.mkdir(parents=True, exist_ok=True)

    hit = search_video(query)
    if not hit:
        raise RuntimeError(f"No se encontró video en Pixabay para query='{query}'")

    raw = out_dir / f"pixabay_{hit.id}_raw.mp4"
    norm = out_dir / f"pixabay_{hit.id}_9x16.mp4"

    if not raw.exists():
        download(hit.video_url, raw)
    if not norm.exists():
        normalize_to_9x16(raw, norm)

    return norm, hit
