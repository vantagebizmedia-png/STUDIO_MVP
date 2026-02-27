import argparse
import hashlib
import json
import os
import sys
import urllib.parse
import shutil
import urllib.request
from pathlib import Path


API_URL = "https://pixabay.com/api/"


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def choose_best_hit(hits: list[dict], target_ratio: float = 9.0 / 16.0) -> dict:
    if not hits:
        raise SystemExit("Pixabay no devolvió resultados")

    scored = []
    for hit in hits:
        w = int(hit.get("imageWidth") or hit.get("webformatWidth") or 0)
        h = int(hit.get("imageHeight") or hit.get("webformatHeight") or 0)
        downloads = int(hit.get("downloads") or 0)
        likes = int(hit.get("likes") or 0)
        views = int(hit.get("views") or 0)

        ratio = (w / h) if w > 0 and h > 0 else 1.0
        ratio_penalty = abs(ratio - target_ratio)

        size_score = w * h
        popularity_score = downloads * 5 + likes * 20 + views

        score = (
            size_score
            + popularity_score
            - int(ratio_penalty * 10_000_000)
        )

        scored.append((score, hit))

    scored.sort(key=lambda x: (-x[0], int(x[1].get("id", 0))))
    return scored[0][1]


def ext_from_url(url: str) -> str:
    lower = url.lower()
    for ext in [".jpg", ".jpeg", ".png", ".webp"]:
        if ext in lower:
            return ext
    return ".jpg"


def http_get_json(url: str) -> dict:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "STUDIO_MVP/0.3 deterministic pixabay resolver"
        },
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode("utf-8"))


def http_download(url: str, dest: Path) -> None:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "STUDIO_MVP/0.3 deterministic pixabay resolver"
        },
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        data = resp.read()
    dest.write_bytes(data)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--query", required=True)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--out-file", default="")  # si se define, guarda solo 1 imagen aquí
    ap.add_argument("--api-key", default=os.environ.get("PIXABAY_API_KEY", ""))
    ap.add_argument("--per-page", type=int, default=10)
    ap.add_argument("--image-type", default="photo")
    ap.add_argument("--orientation", default="vertical")
    ap.add_argument("--safesearch", default="true")
    args = ap.parse_args()

    api_key = (args.api_key or "").strip()
    if not api_key:
        raise SystemExit("Falta PIXABAY_API_KEY")

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    params = {
        "key": api_key,
        "q": args.query,
        "image_type": args.image_type,
        "orientation": args.orientation,
        "safesearch": args.safesearch,
        "per_page": str(args.per_page),
        "page": "1",
    }

    url = API_URL + "?" + urllib.parse.urlencode(params)
    payload = http_get_json(url)

    hits = payload.get("hits", [])
    if not hits:
        raise SystemExit("Sin resultados en Pixabay para la query dada")

    best = choose_best_hit(hits)

    asset_id = str(best.get("id"))
    download_url = (
        best.get("largeImageURL")
        or best.get("webformatURL")
        or best.get("previewURL")
        or ""
    )
    if not download_url:
        raise SystemExit("El resultado elegido no trajo URL descargable")

    ext = ext_from_url(download_url)
    asset_path = out_dir / f"pixabay_{asset_id}{ext}"
    meta_path = out_dir / f"pixabay_{asset_id}.json"

    http_download(download_url, asset_path)
    file_hash = sha256_file(asset_path)

    meta = {
        "provider": "pixabay_image",
        "query": args.query,
        "asset_id": asset_id,
        "selected_from_total_hits": int(payload.get("totalHits", 0)),
        "page_url": best.get("pageURL", ""),
        "download_url": download_url,
        "local_path": str(asset_path),
        "sha256": file_hash,
        "width": int(best.get("imageWidth") or best.get("webformatWidth") or 0),
        "height": int(best.get("imageHeight") or best.get("webformatHeight") or 0),
        "tags": best.get("tags", ""),
        "user": best.get("user", ""),
        "likes": int(best.get("likes") or 0),
        "downloads": int(best.get("downloads") or 0),
        "views": int(best.get("views") or 0),
        "image_type": args.image_type,
        "orientation": args.orientation,
        "safesearch": args.safesearch,
        "api_search_url": url,
        "license_note": "Pixabay asset descargado localmente para uso determinista; revisar licencia y atribucion si aplica.",
    }

    meta_path.write_text(json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8")

    print("OK")
    print("QUERY      :", args.query)
    print("ASSET_ID   :", asset_id)
    print("IMAGE_PATH :", asset_path)
    out_file = str(getattr(args, "out_file", "") or "").strip()
    if out_file:
        dst = Path(out_file).expanduser().resolve()
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(str(asset_path), str(dst))
        print("OUT_FILE   :", str(dst))
    print("META_PATH  :", meta_path)
    print("SHA256     :", file_hash)
    print("SIZE       :", f'{meta["width"]}x{meta["height"]}')
    print("USER       :", meta["user"])
    print("TAGS       :", meta["tags"])

    return 0


if __name__ == "__main__":
    raise SystemExit(main())



