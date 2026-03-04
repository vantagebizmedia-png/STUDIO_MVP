import argparse
import json
import sys
import wave
from pathlib import Path

# --- Asegura imports del repo aunque se ejecute fuera del cwd del repo ---
_THIS = Path(__file__).resolve()
_REPO = _THIS.parents[1]  # .../tools/ -> repo root
if str(_REPO) not in sys.path:
    sys.path.insert(0, str(_REPO))

from studio.scene_builder_v03 import build_scenes_v03
from studio.stock_query_pixabay_v03 import resolve_image_for_scene
from studio.audio_clip_v03 import clip_wav_segment, safe_copy_master_as_clip


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
    # 1) intenta desde artifacts del manifest (si existen)
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

    # 2) fallback: WAV más grande
    wavs = list(pack_dir.glob("*.wav"))
    if not wavs:
        wavs = list((pack_dir / "artifacts").glob("*.wav"))
    if wavs:
        wavs.sort(key=lambda x: x.stat().st_size, reverse=True)
        return wavs[0].resolve()

    return None


def _extract_script_text(obj: dict) -> str:
    # 1) claves top-level típicas
    for k in (
        "script",
        "script_text",
        "text",
        "final_script",
        "final_text",
        "narration",
        "voice_text",
        "prompt",
    ):
        v = obj.get(k)
        if isinstance(v, str) and v.strip():
            return v.strip()

    # 2) text_generation (si existe)
    tg = obj.get("text_generation")
    if isinstance(tg, dict):
        for k in ("text", "script", "output", "result", "final"):
            v = tg.get(k)
            if isinstance(v, str) and v.strip():
                return v.strip()

    # 3) si hay scenes_v03 viejo, intenta concatenar script_text
    sv = obj.get("scenes_v03")
    if isinstance(sv, list) and sv:
        parts = []
        for s in sv:
            if isinstance(s, dict):
                v = s.get("script_text")
                if isinstance(v, str) and v.strip():
                    parts.append(v.strip())
        if parts:
            return " ".join(parts).strip()

    return ""


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

    max_scenes = int(args.max_scenes or 1)
    if max_scenes < 1:
        max_scenes = 1

    script_text = _extract_script_text(obj)

    apath = _resolve_audio_path(pack_dir, obj)
    total_ms = _wav_ms(apath) if apath else 0
    if total_ms <= 0:
        total_ms = 1000

    # reconstruye escenas SIEMPRE
    scenes_v03 = build_scenes_v03(
        script_text=str(script_text or ""),
        max_scenes=max_scenes,
        total_audio_ms=int(total_ms),
    )

    # cache determinista
    stock_cache = obj.get("stock_cache")
    if not isinstance(stock_cache, dict):
        stock_cache = {}
        obj["stock_cache"] = stock_cache

    seed = int(obj.get("seed") or 0)
    replay_strict = bool(obj.get("replay_strict") or False)
    tg = obj.get("text_generation")
    if isinstance(tg, dict) and "replay_strict" in tg:
        replay_strict = bool(tg.get("replay_strict"))

    # WAV master (abs) + rel (debug/compat)
    master_wav_abs = apath.resolve() if apath else None
    master_wav_rel = None
    if master_wav_abs:
        try:
            master_wav_rel = str(master_wav_abs.relative_to(pack_dir))
        except Exception:
            master_wav_rel = str(master_wav_abs)

    # --- RECORTE REAL por escena: artifacts/audio_sXX.wav ---
    # (si falla recorte por cualquier razón, fallback determinista: copiar master)
    if master_wav_abs:
        art_dir = (pack_dir / "artifacts")
        art_dir.mkdir(parents=True, exist_ok=True)

        for i, sc in enumerate(scenes_v03, start=1):
            st = int(sc.get("start_ms") or 0)
            en = int(sc.get("end_ms") or 0)
            out_rel = f"artifacts/audio_s{i:02d}.wav"
            out_abs = (pack_dir / out_rel).resolve()
            try:
                clip_wav_segment(str(master_wav_abs), str(out_abs), st, en)
            except Exception:
                safe_copy_master_as_clip(str(master_wav_abs), str(out_abs))

            # setea audio_clip a ESTE clip
            sc["assets"]["audio_clip"] = out_rel

    # resuelve imagen por escena (mantiene comportamiento previo)
    for sc in scenes_v03:
        q = sc.get("image_query") or ""
        r = resolve_image_for_scene(
            pack_dir=str(pack_dir),
            query=q,
            seed=seed,
            replay_strict=replay_strict,
            cache=stock_cache,
            placeholder_path=None,
        )
        sc["assets"]["image"] = r["path"]
        sc["assets"]["image_meta"] = {
            "provider": r["provider"],
            "cache_hit": r["cache_hit"],
            "cache_key": r["cache_key"],
            "query": q,
        }

        # compat: si por alguna razón no hubo master_wav_abs, deja master como audio_clip (placeholder)
        if (not master_wav_abs) and master_wav_rel:
            sc["assets"]["audio_clip"] = master_wav_rel

    # meta
    sb = obj.get("scene_builder_v03") or {}
    if not isinstance(sb, dict):
        sb = {}
    sb["max_scenes"] = int(max_scenes)
    sb["total_audio_ms"] = int(total_ms)
    sb["note"] = "patched total_audio_ms from wav; rebuilt scenes_v03 from script_text (resolved images + audio_clip=per-scene clips when master wav exists)"
    obj["scene_builder_v03"] = sb

    obj["scenes_v03"] = scenes_v03

    # legacy: solo si no existe o está vacío
    if ("scenes" not in obj) or (not isinstance(obj.get("scenes"), list)) or (len(obj.get("scenes") or []) == 0):
        obj["scenes"] = scenes_v03

    manifest_path.write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"OK patch_scene_builder_v03: total_ms={total_ms} scenes={len(scenes_v03)} script_len={len(script_text)} wav={apath}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
