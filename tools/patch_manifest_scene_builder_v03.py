import argparse
import json
import wave
from pathlib import Path


def _find_manifest(pack_dir: Path) -> Path:
    cand1 = pack_dir / "manifest_v03.json"
    if cand1.exists():
        return cand1
    cand2 = pack_dir / "artifacts" / "manifest_v03.json"
    if cand2.exists():
        return cand2
    raise SystemExit(f"No existe manifest_v03.json en: {pack_dir}")


def _wav_ms(path: Path) -> int:
    try:
        with wave.open(str(path), "rb") as wf:
            frames = wf.getnframes()
            sr = wf.getframerate() or 1
            ms = int(round((frames / float(sr)) * 1000.0))
            return max(ms, 1)
    except Exception:
        return 0


def _resolve_audio_path(pack_dir: Path, obj: dict) -> Path | None:
    art = obj.get("artifacts") or {}
    audio_rel = None
    for k in ("audio", "audio_path", "aud", "voice", "narration_audio"):
        v = art.get(k)
        if isinstance(v, str) and v.strip():
            audio_rel = v.strip()
            break

    if audio_rel:
        p = (pack_dir / audio_rel).resolve()
        if p.exists():
            return p
        p2 = (pack_dir / "artifacts" / audio_rel).resolve()
        if p2.exists():
            return p2

    wavs = list(pack_dir.glob("*.wav"))
    if not wavs:
        wavs = list((pack_dir / "artifacts").glob("*.wav"))
    if wavs:
        wavs.sort(key=lambda x: x.stat().st_size, reverse=True)
        return wavs[0].resolve()

    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack-dir", required=True)
    ap.add_argument("--max-scenes", type=int, default=6)
    args = ap.parse_args()

    pack_dir = Path(args.pack_dir).expanduser().resolve()
    if not pack_dir.exists():
        raise SystemExit(f"No existe pack-dir: {pack_dir}")

    manifest_path = _find_manifest(pack_dir)
    obj = json.loads(manifest_path.read_text(encoding="utf-8"))

    apath = _resolve_audio_path(pack_dir, obj)
    total_ms = _wav_ms(apath) if apath else 0
    if total_ms <= 0:
        total_ms = 1000  # compat

    max_scenes = int(args.max_scenes or 1)
    if max_scenes < 1:
        max_scenes = 1

    sb = obj.get("scene_builder_v03") or {}
    if not isinstance(sb, dict):
        sb = {}
    sb["max_scenes"] = max_scenes
    sb["total_audio_ms"] = int(total_ms)
    sb["note"] = "patched total_audio_ms from wav; did NOT modify scenes_v03"
    obj["scene_builder_v03"] = sb

    manifest_path.write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"OK patch_scene_builder_v03: total_ms={total_ms} wav={apath}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
