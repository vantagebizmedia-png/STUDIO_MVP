# tools/patch_manifest_scene_builder_v03.py
# Patch manifest_v03.json:
# - NO depende de import "studio"
# - NO pisa scenes legacy
# - Escribe/actualiza scenes_v03[] (start/end + imagen)
# - Descubre WAV y calcula duración
# - Genera 1 WAV clip por escena en assets/audio_clips/

from __future__ import annotations

import json
import argparse
from pathlib import Path
import importlib.util
import sys
import wave


def _load(mod_name: str, path: Path):
    spec = importlib.util.spec_from_file_location(mod_name, str(path))
    if spec is None or spec.loader is None:
        raise SystemExit(f"No pude cargar spec para: {path}")
    mod = importlib.util.module_from_spec(spec)
    sys.modules[mod_name] = mod
    spec.loader.exec_module(mod)  # type: ignore[attr-defined]
    return mod


def _read_text_if_exists(p: Path) -> str:
    try:
        if p.exists() and p.is_file():
            return p.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        return ""
    return ""


def _wav_duration_ms(p: Path) -> int:
    try:
        if not p.exists() or not p.is_file():
            return 0
        with wave.open(str(p), "rb") as wf:
            frames = wf.getnframes()
            rate = wf.getframerate()
            if rate <= 0:
                return 0
            sec = frames / float(rate)
            ms = int(round(sec * 1000.0))
            return max(0, ms)
    except Exception:
        return 0


def _discover_wav(pack: Path) -> Path | None:
    candidates = []
    candidates += list(pack.glob("artifacts/**/*.wav"))
    candidates += list(pack.glob("**/*.wav"))

    uniq = []
    seen = set()
    for p in candidates:
        try:
            rp = str(p.resolve())
        except Exception:
            rp = str(p)
        if rp not in seen:
            seen.add(rp)
            uniq.append(p)

    uniq_sorted = sorted(uniq, key=lambda x: str(x).replace("\\", "/").lower())
    return uniq_sorted[0] if uniq_sorted else None


def _write_wav_clip(src_wav: Path, dst_wav: Path, start_ms: int, end_ms: int) -> None:
    # Corto determinista en límites de frames (sin resample)
    start_ms = max(0, int(start_ms))
    end_ms = max(0, int(end_ms))
    if end_ms <= start_ms:
        # clip vacío determinista
        dst_wav.parent.mkdir(parents=True, exist_ok=True)
        with wave.open(str(dst_wav), "wb") as out:
            out.setnchannels(1)
            out.setsampwidth(2)
            out.setframerate(44100)
            out.writeframes(b"")
        return

    with wave.open(str(src_wav), "rb") as wf:
        nch = wf.getnchannels()
        sw = wf.getsampwidth()
        fr = wf.getframerate()
        nframes = wf.getnframes()

        start_f = int(round((start_ms / 1000.0) * fr))
        end_f = int(round((end_ms / 1000.0) * fr))
        start_f = max(0, min(nframes, start_f))
        end_f = max(0, min(nframes, end_f))
        if end_f <= start_f:
            frames = b""
        else:
            wf.setpos(start_f)
            frames = wf.readframes(end_f - start_f)

        dst_wav.parent.mkdir(parents=True, exist_ok=True)
        with wave.open(str(dst_wav), "wb") as out:
            out.setnchannels(nch)
            out.setsampwidth(sw)
            out.setframerate(fr)
            out.writeframes(frames)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack-dir", required=True)
    ap.add_argument("--max-scenes", type=int, default=6)
    args = ap.parse_args()

    pack = Path(args.pack_dir)
    manifest_path = pack / "manifest_v03.json"
    if not manifest_path.exists():
        raise SystemExit(f"manifest_v03.json no existe en: {pack}")

    repo = Path(__file__).resolve().parent.parent
    sb = _load("_scene_builder_v03", repo / "studio" / "scene_builder_v03.py")
    sq = _load("_stock_query_pixabay_v03", repo / "studio" / "stock_query_pixabay_v03.py")

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

    # ---- Script text
    script_text = (
        manifest.get("script")
        or manifest.get("script_text")
        or manifest.get("text")
        or ""
    )

    if not str(script_text).strip():
        artifacts = manifest.get("artifacts")
        if isinstance(artifacts, dict) and isinstance(artifacts.get("script"), str):
            rel = artifacts["script"].replace("\\", "/")
            script_text = _read_text_if_exists(pack / rel)

    if not str(script_text).strip():
        legacy = manifest.get("scenes")
        if isinstance(legacy, list):
            narr = []
            for scn in legacy:
                if isinstance(scn, dict):
                    t = scn.get("narration") or scn.get("audio_text") or ""
                    if isinstance(t, str) and t.strip():
                        narr.append(t.strip())
            script_text = "\n\n".join(narr)

    # ---- total_ms + wav source
    total_ms = 0
    audio_obj = manifest.get("audio")
    if isinstance(audio_obj, dict) and "duration_ms" in audio_obj:
        total_ms = int(audio_obj.get("duration_ms") or 0)
    total_ms = int(manifest.get("audio_duration_ms") or total_ms or 0)

    audio_source = ""
    wav_path = None

    if total_ms <= 0:
        artifacts = manifest.get("artifacts")
        if isinstance(artifacts, dict) and isinstance(artifacts.get("audio"), str):
            rel = artifacts["audio"].replace("\\", "/")
            cand = pack / rel
            if cand.exists() and cand.is_file():
                wav_path = cand

        if wav_path is None:
            wav_path = _discover_wav(pack)

        if wav_path is not None:
            total_ms = _wav_duration_ms(wav_path)
            try:
                audio_source = str(wav_path.relative_to(pack)).replace("\\", "/")
            except Exception:
                audio_source = str(wav_path).replace("\\", "/")
        else:
            total_ms = 0
            audio_source = ""

    # Si total_ms ya venía, igual intentamos ubicar wav para clips (si podemos)
    if wav_path is None:
        # preferir artifacts.audio si existe
        artifacts = manifest.get("artifacts")
        if isinstance(artifacts, dict) and isinstance(artifacts.get("audio"), str):
            rel = artifacts["audio"].replace("\\", "/")
            cand = pack / rel
            if cand.exists() and cand.is_file():
                wav_path = cand
        if wav_path is None:
            wav_path = _discover_wav(pack)
        if wav_path is not None and not audio_source:
            try:
                audio_source = str(wav_path.relative_to(pack)).replace("\\", "/")
            except Exception:
                audio_source = str(wav_path).replace("\\", "/")

    seed = int(manifest.get("seed") or 0)
    replay_strict = bool(manifest.get("replay_strict") or False)

    stock_cache = manifest.get("stock_cache")
    if not isinstance(stock_cache, dict):
        stock_cache = {}
        manifest["stock_cache"] = stock_cache

    scenes_v03 = sb.build_scenes_v03(
        script_text=str(script_text),
        max_scenes=int(args.max_scenes),
        total_audio_ms=int(total_ms),
    )

    # imagen + audio_clip
    clips_dir = pack / "assets" / "audio_clips"

    for scn in scenes_v03:
        q = scn.get("image_query") or ""
        r = sq.resolve_image_for_scene(
            pack_dir=str(pack),
            query=str(q),
            seed=seed,
            replay_strict=replay_strict,
            cache=stock_cache,
            placeholder_path=None,
        )
        scn["assets"]["image"] = r["path"]
        scn["assets"]["image_meta"] = {
            "provider": r["provider"],
            "cache_hit": r["cache_hit"],
            "cache_key": r["cache_key"],
            "query": q,
        }

        # audio clip
        scn["assets"]["audio_clip"] = None
        if wav_path is not None and total_ms > 0:
            sid = str(scn.get("id") or "s00")
            dst = clips_dir / f"{sid}.wav"
            _write_wav_clip(
                src_wav=wav_path,
                dst_wav=dst,
                start_ms=int(scn.get("start_ms") or 0),
                end_ms=int(scn.get("end_ms") or 0),
            )
            try:
                scn["assets"]["audio_clip"] = str(dst.relative_to(pack)).replace("\\", "/")
            except Exception:
                scn["assets"]["audio_clip"] = str(dst).replace("\\", "/")

    manifest["scenes_v03"] = scenes_v03
    manifest["scene_builder_v03"] = {
        "max_scenes": int(args.max_scenes),
        "total_audio_ms": int(total_ms),
        "audio_source_path": audio_source,
        "note": "scenes legacy preserved; new scenes in scenes_v03",
    }

    if not isinstance(manifest.get("scenes_v03"), list) or len(manifest["scenes_v03"]) < 1:
        raise SystemExit("Patch no produjo scenes_v03[] válido.")
    first = manifest["scenes_v03"][0]
    if not isinstance(first, dict) or "start_ms" not in first or "end_ms" not in first:
        raise SystemExit("scenes_v03[0] sin start_ms/end_ms.")

    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
