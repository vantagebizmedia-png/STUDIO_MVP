# -*- coding: utf-8 -*-
"""
Export v0.3 Content Pack desde manifest_v03.json.

Si manifest trae scenes[]:
- copia artifacts/script.txt (script global)
- copia artifacts/image.png / audio.wav (escena 1 por compat)
- además copia todas las escenas a:
  artifacts/scenes/scene_01/{script.txt,image.png,audio.wav}
  artifacts/scenes/scene_02/...
y escribe pack.json con sección scenes[] (paths relativos)
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
from pathlib import Path

def read_json(p: Path) -> dict:
    return json.loads(p.read_text(encoding="utf-8"))

def read_json_sig(p: Path) -> dict:
    return json.loads(p.read_text(encoding="utf-8-sig"))

def safe_copy(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(str(src), str(dst))

def _rel_to_base(path: str, base_dir: Path) -> str:
    p = str(path or "").strip()
    if not p:
        return ""
    base_abs = base_dir.resolve()
    src = Path(p)
    if not src.is_absolute():
        src = (base_abs / src).resolve()
    return os.path.relpath(str(src), start=str(base_abs)).replace("\\", "/")


def _resolve_scene_sources(work_dir: Path, idx: int, arts: dict) -> tuple[Path, Path, Path]:
    stable_dir = work_dir / "artifacts" / "scenes" / f"scene_{idx:02d}"
    stable_script = stable_dir / "script.txt"
    stable_image = stable_dir / "image.png"
    stable_audio = stable_dir / "audio.wav"
    if stable_script.exists() and stable_image.exists() and stable_audio.exists():
        return stable_script, stable_image, stable_audio

    sp = Path(arts.get("script") or "")
    ip = Path(arts.get("image") or "")
    ap = Path(arts.get("audio") or "")
    if sp and not sp.is_absolute():
        sp = work_dir / sp
    if ip and not ip.is_absolute():
        ip = work_dir / ip
    if ap and not ap.is_absolute():
        ap = work_dir / ap
    return sp, ip, ap


def _scene_index(row: dict) -> int:
    try:
        return int(row.get("index", 0) or 0)
    except Exception:
        return 0

def _compact_music_strategy_text(*parts: object) -> str:
    vals = []
    for p in parts:
        s = str(p or "").strip().lower()
        if s:
            vals.append(s)
    return " ".join(vals)

def _pick_auto_music_strategy(script_text: str, manifest: dict) -> dict:
    text = _compact_music_strategy_text(script_text)

    providers = manifest.get("providers") or {}
    provider_name = str((providers.get("music") or "local_music")).strip()

    rules = [
        (["motivación", "motivacion", "disciplina", "productividad", "hábito", "habito", "hábitos", "habitos", "enfoque", "energía", "energia"],
         "motivational upbeat corporate background",
         "high",
         "matched_keywords_productivity"),
        (["meditación", "meditacion", "calma", "relax", "relajación", "relajacion", "suave"],
         "calm ambient background",
         "low",
         "matched_keywords_calm"),
        (["noticias", "explicación", "explicacion", "tutorial", "guía", "guia", "documental"],
         "clean modern documentary background",
         "medium",
         "matched_keywords_explainer"),
    ]

    for keywords, query, energy, reason in rules:
        if any(k in text for k in keywords):
            return {
                "music_source_mode": "local",
                "music_provider_override": provider_name,
                "music_query": query,
                "music_strategy_reason": reason,
                "music_energy": energy,
            }

    return {
        "music_source_mode": "local",
        "music_provider_override": provider_name,
        "music_query": "motivational background instrumental",
        "music_strategy_reason": "default_export_v03_from_script",
        "music_energy": "medium",
    }

def derive_tag(manifest: dict) -> str:
    sp = (manifest.get("artifacts") or {}).get("script") or ""
    name = Path(sp).name
    if name.startswith("script_") and name.endswith(".txt"):
        return name[len("script_"):-len(".txt")]
    ip = (manifest.get("artifacts") or {}).get("image") or ""
    iname = Path(ip).name
    if iname.startswith("image_") and iname.endswith(".png"):
        return iname[len("image_"):-len(".png")]
    stable_blob = {
        "artifacts": manifest.get("artifacts") or {},
        "scenes": manifest.get("scenes") or [],
    }
    raw = json.dumps(stable_blob, sort_keys=True, ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()[:8]

def pick_default_out_root(manifest: dict) -> Path:
    cfgp = (manifest.get("config_path") or "").strip()
    if cfgp:
        p = Path(cfgp).expanduser()
        if p.exists():
            try:
                cfg = read_json_sig(p.resolve())
                ws = (cfg.get("workspace") or "").strip()
                if ws:
                    ws_p = Path(ws)
                    if not ws_p.is_absolute():
                        ws_p = (Path.cwd() / ws_p).resolve()
                    return (ws_p / "exports").resolve()
            except Exception:
                pass
    env_ws = os.environ.get("STUDIO_WORKSPACE", "").strip()
    if env_ws:
        return (Path(env_ws).expanduser().resolve() / "exports").resolve()
    return (Path("workspace").resolve() / "exports").resolve()

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", required=True, help="Path a manifest_v03.json")
    ap.add_argument("--out-root", default="", help="Root de export (default: workspace del config)")
    ap.add_argument("--overwrite", action="store_true", help="Si existe el pack dir, lo reemplaza.")
    args = ap.parse_args()

    mpath = Path(args.manifest).expanduser().resolve()
    if not mpath.exists():
        raise SystemExit(f"ERROR: manifest no existe: {mpath}")

    manifest = read_json(mpath)

    manifest_dir = mpath.parent.resolve()
    work_dir = manifest_dir
    manifest_work_dir = str(manifest.get("work_dir") or "").strip()
    if manifest_work_dir:
        wd = Path(manifest_work_dir)
        if not wd.is_absolute():
            wd = (manifest_dir / wd)
        work_dir = wd.resolve()

    artifacts = manifest.get("artifacts") or {}

    def _resolve_optional_work_file_local(raw: object):
        s = str(raw or "").strip()
        if not s:
            return None
        p = Path(s).expanduser()
        if not p.is_absolute():
            p = (work_dir / p).resolve()
        return p

    def _is_existing_file_local(path_obj: object) -> bool:
        try:
            return path_obj is not None and Path(path_obj).exists() and Path(path_obj).is_file()
        except Exception:
            return False

    top_script_p = _resolve_optional_work_file_local(artifacts.get("script"))
    top_image_p = _resolve_optional_work_file_local(artifacts.get("image"))
    top_audio_p = _resolve_optional_work_file_local(artifacts.get("audio"))

    script_p = top_script_p
    image_p = top_image_p
    audio_p = top_audio_p

    out_root = args.out_root.strip()
    out_root_p = Path(out_root).resolve() if out_root else pick_default_out_root(manifest)
    out_root_p.mkdir(parents=True, exist_ok=True)

    tag = derive_tag(manifest)
    pack_dir = out_root_p / f"pack_v03_{tag}"
    if pack_dir.exists():
        if args.overwrite:
            shutil.rmtree(pack_dir)
        else:
            n = 2
            while (out_root_p / f"pack_v03_{tag}_{n}").exists():
                n += 1
            pack_dir = out_root_p / f"pack_v03_{tag}_{n}"

    (pack_dir / "artifacts").mkdir(parents=True, exist_ok=True)

    script_txt = ""
    if _is_existing_file_local(top_script_p):
        script_txt = Path(top_script_p).read_text(encoding="utf-8")
    else:
        script_txt = str(manifest.get("script") or "").strip()
        if not script_txt:
            source_scenes_for_script = manifest.get("scenes_v03") or manifest.get("scenes") or []
            if isinstance(source_scenes_for_script, list):
                parts = []
                for raw_scene in source_scenes_for_script:
                    if not isinstance(raw_scene, dict):
                        continue
                    part = str(
                        raw_scene.get("narration")
                        or raw_scene.get("audio_text")
                        or raw_scene.get("text")
                        or raw_scene.get("onscreen")
                        or ""
                    ).strip()
                    if part:
                        parts.append(part)
                script_txt = "\n".join(parts).strip()
    # FIX: preservar music_strategy.json si ya existe (evita sobreescribir estrategias ricas)
    _existing_ms = None
    for _ms_candidate in [
        work_dir / "music_strategy.json",
        mpath.parent / "music_strategy.json",
    ]:
        if _ms_candidate.exists():
            try:
                _existing_ms = json.loads(_ms_candidate.read_text(encoding="utf-8"))
                break
            except Exception:
                pass

    if _existing_ms is not None:
        music_strategy = _existing_ms
    else:
        music_strategy = _pick_auto_music_strategy(script_txt, manifest)
    (pack_dir / "music_strategy.json").write_text(
        json.dumps(music_strategy, ensure_ascii=False, indent=2),
        encoding="utf-8"
    )

    scenes_rel = []
    manifest_scenes_v03 = manifest.get("scenes_v03") or []
    manifest_scenes_legacy = manifest.get("scenes") or []

    def _safe_int_local(value: object, default: int = 0) -> int:
        try:
            return int(value or 0)
        except Exception:
            return default

    def _asset_value_local(value: object) -> str:
        if isinstance(value, str):
            return value.strip()
        if isinstance(value, dict):
            for key in ("path", "file", "value", "relpath"):
                raw = str(value.get(key) or "").strip()
                if raw:
                    return raw
        return ""

    def _resolve_candidate_local(raw: object):
        s = str(raw or "").strip()
        if not s:
            return None
        p = Path(s).expanduser()
        if not p.is_absolute():
            p = (work_dir / p).resolve()
        return p

    def _first_existing_local(candidates: list[object]):
        for p in candidates:
            try:
                if p is not None and p.exists() and p.is_file():
                    return p
            except Exception:
                pass
        return None

    def _scene_index_local(row: dict, ordinal: int) -> int:
        sid = str(row.get("id") or "").strip().lower()

        if sid.startswith("scene_"):
            tail = sid.split("_")[-1]
            if tail.isdigit():
                parsed = int(tail)
                if parsed > 0:
                    return parsed

        if sid.startswith("s"):
            tail = sid[1:]
            if tail.isdigit():
                parsed = int(tail)
                if parsed > 0:
                    return parsed

        idx = _safe_int_local(row.get("index"), 0)
        if idx > 0:
            return idx

        if ordinal > 0:
            return ordinal

        return 0

    def _normalize_visual_kind_local(value: object, has_image: bool, has_video: bool) -> str:
        raw = str(value or "").strip().lower()
        if raw in ("image", "video"):
            return raw
        if has_video and not has_image:
            return "video"
        if has_image and not has_video:
            return "image"
        if has_video:
            return "video"
        return "image"

    def _scene_manifest_row_local(row: dict, exported_scene: dict) -> dict:
        out = dict(row or {})
        out["id"] = exported_scene["id"]
        out["index"] = exported_scene["index"]
        out["text"] = exported_scene["text"]
        out["narration"] = exported_scene["narration"]
        out["onscreen"] = exported_scene["onscreen"]
        out["audio_text"] = exported_scene["audio_text"]
        out["requested_media_type"] = exported_scene["requested_media_type"]
        out["visual_request_kind"] = exported_scene["visual_request_kind"]
        out["visual_kind"] = exported_scene["visual_kind"]
        out["visual_source_kind"] = exported_scene["visual_source_kind"]
        out["visual_capability"] = exported_scene["visual_capability"]
        out["start_ms"] = exported_scene["start_ms"]
        out["end_ms"] = exported_scene["end_ms"]
        out["duration_ms"] = exported_scene["duration_ms"]
        out["assets"] = {
            "image": exported_scene["image"],
            "video": exported_scene["video"],
            "audio_clip": exported_scene["audio"],
        }
        out["artifacts"] = {
            "script": exported_scene["script"],
            "image": exported_scene["image"],
            "video": exported_scene["video"],
            "audio": exported_scene["audio"],
        }
        return out

    def _scene_export_local(raw_row: dict, ordinal: int):
        row = dict(raw_row or {})
        idx = _scene_index_local(row, ordinal)
        if idx <= 0:
            return None, None

        source_scene_dir = work_dir / "artifacts" / "scenes" / f"scene_{idx:02d}"
        assets = dict(row.get("assets") or {})
        artifacts_row = dict(row.get("artifacts") or {})

        source_script = _first_existing_local([
            _resolve_candidate_local(artifacts_row.get("script")),
            _resolve_candidate_local(source_scene_dir / "script.txt"),
            top_script_p if _is_existing_file_local(top_script_p) else None,
        ])

        scene_text = str(row.get("text") or row.get("narration") or row.get("audio_text") or "").strip()
        narration = str(row.get("narration") or scene_text).strip()
        onscreen = str(row.get("onscreen") or row.get("text") or narration or scene_text).strip()
        audio_text = str(row.get("audio_text") or narration or scene_text).strip()
        scene_script_text = str(narration or audio_text or onscreen or scene_text).strip()

        source_image = _first_existing_local([
            _resolve_candidate_local(_asset_value_local(assets.get("image"))),
            _resolve_candidate_local(row.get("image")),
            _resolve_candidate_local(artifacts_row.get("image")),
            _resolve_candidate_local(source_scene_dir / "image.png"),
        ])
        source_video = _first_existing_local([
            _resolve_candidate_local(_asset_value_local(assets.get("video"))),
            _resolve_candidate_local(row.get("video")),
            _resolve_candidate_local(artifacts_row.get("video")),
            _resolve_candidate_local(source_scene_dir / "video.mp4"),
        ])
        source_audio = _first_existing_local([
            _resolve_candidate_local(_asset_value_local(assets.get("audio_clip"))),
            _resolve_candidate_local(row.get("audio")),
            _resolve_candidate_local(artifacts_row.get("audio")),
            _resolve_candidate_local(source_scene_dir / "audio.wav"),
            _resolve_candidate_local(work_dir / "assets" / "audio_clips" / f"s{idx:02d}.wav"),
        ])
        if source_audio is None:
            return None, None

        has_image = source_image is not None and source_image.exists()
        has_video = source_video is not None and source_video.exists()

        visual_kind = _normalize_visual_kind_local(row.get("visual_kind"), has_image, has_video)
        if visual_kind == "video" and not has_video and has_image:
            visual_kind = "image"
        if visual_kind == "image" and not has_image and has_video:
            visual_kind = "video"
        if visual_kind == "video" and not has_video:
            return None, None
        if visual_kind == "image" and not has_image:
            return None, None

        sdir = pack_dir / "artifacts" / "scenes" / f"scene_{idx:02d}"
        sdir.mkdir(parents=True, exist_ok=True)

        if source_script is not None and source_script.exists():
            safe_copy(source_script, sdir / "script.txt")
        else:
            if not scene_script_text:
                scene_script_text = f"scene_{idx:02d}"
            (sdir / "script.txt").write_text(scene_script_text, encoding="utf-8")

        safe_copy(source_audio, sdir / "audio.wav")

        image_rel = ""
        video_rel = ""
        if visual_kind == "video":
            safe_copy(source_video, sdir / "video.mp4")
            video_rel = f"artifacts/scenes/scene_{idx:02d}/video.mp4"
        else:
            safe_copy(source_image, sdir / "image.png")
            image_rel = f"artifacts/scenes/scene_{idx:02d}/image.png"

        start_ms = _safe_int_local(row.get("start_ms"), 0)
        end_ms = _safe_int_local(row.get("end_ms"), 0)
        duration_ms = _safe_int_local(row.get("duration_ms"), 0)
        if duration_ms <= 0 and end_ms > start_ms:
            duration_ms = end_ms - start_ms
        if duration_ms > 0 and end_ms <= start_ms:
            end_ms = start_ms + duration_ms

        requested_media_type = str(row.get("requested_media_type") or row.get("visual_request_kind") or visual_kind).strip().lower()
        visual_request_kind = str(row.get("visual_request_kind") or row.get("requested_media_type") or requested_media_type or visual_kind).strip().lower()

        visual_source_kind_raw = str(
            row.get("visual_source_kind") or ("stock_video" if visual_kind == "video" else "stock_image")
        ).strip().lower()
        if visual_source_kind_raw in ("fallback_image", "stock_image"):
            visual_source_kind = "stock_image"
        elif visual_source_kind_raw in ("fallback_video", "stock_video"):
            visual_source_kind = "stock_video"
        else:
            visual_source_kind = "stock_video" if visual_kind == "video" else "stock_image"

        visual_capability_raw = str(
            row.get("visual_capability") or ("stock_video" if visual_kind == "video" else "stock_image")
        ).strip().lower()
        if visual_capability_raw in ("fallback_image", "stock_image"):
            visual_capability = "stock_image"
        elif visual_capability_raw in ("fallback_video", "stock_video"):
            visual_capability = "stock_video"
        else:
            visual_capability = "stock_video" if visual_kind == "video" else "stock_image"

        exported_scene = {
            "id": str(row.get("id") or f"scene_{idx:03d}"),
            "index": idx,
            "text": scene_text,
            "tag": str(row.get("tag") or ""),
            "narration": narration,
            "onscreen": onscreen,
            "stock_query": str(row.get("stock_query") or ""),
            "image_prompt": str(row.get("image_prompt") or ""),
            "audio_text": audio_text,
            "requested_media_type": requested_media_type,
            "visual_request_kind": visual_request_kind,
            "visual_kind": visual_kind,
            "visual_source_kind": visual_source_kind,
            "visual_capability": visual_capability,
            "script": f"artifacts/scenes/scene_{idx:02d}/script.txt",
            "image": image_rel,
            "video": video_rel,
            "audio": f"artifacts/scenes/scene_{idx:02d}/audio.wav",
            "start_ms": start_ms,
            "end_ms": end_ms,
            "duration_ms": duration_ms,
        }

        return exported_scene, _scene_manifest_row_local(row, exported_scene)

    source_scenes = manifest_scenes_v03 if isinstance(manifest_scenes_v03, list) and manifest_scenes_v03 else manifest_scenes_legacy
    manifest_scenes_export = []
    if isinstance(source_scenes, list) and source_scenes:
        scenes_sorted = sorted(
            [dict(s or {}) for s in source_scenes if isinstance(s, dict)],
            key=lambda row: _scene_index_local(dict(row or {}), 0),
        )
        for ordinal, s in enumerate(scenes_sorted, start=1):
            exported_scene, manifest_scene = _scene_export_local(s, ordinal)
            if exported_scene is None or manifest_scene is None:
                continue
            scenes_rel.append(exported_scene)
            manifest_scenes_export.append(manifest_scene)

    base_script_src = top_script_p if _is_existing_file_local(top_script_p) else None
    base_image_src = top_image_p if _is_existing_file_local(top_image_p) else None
    base_audio_src = top_audio_p if _is_existing_file_local(top_audio_p) else None

    def _resolve_optional_pack_file_local(raw: object):
        s = str(raw or "").strip()
        if not s:
            return None
        p = Path(s).expanduser()
        if not p.is_absolute():
            p = (pack_dir / p).resolve()
        return p

    if scenes_rel:
        first_scene = scenes_rel[0]

        if base_script_src is None:
            first_script_p = _resolve_optional_pack_file_local(first_scene.get("script"))
            if _is_existing_file_local(first_script_p):
                base_script_src = first_script_p

        if base_image_src is None:
            first_image_p = _resolve_optional_pack_file_local(first_scene.get("image"))
            if _is_existing_file_local(first_image_p):
                base_image_src = first_image_p

        if base_audio_src is None:
            first_audio_p = _resolve_optional_pack_file_local(first_scene.get("audio"))
            if _is_existing_file_local(first_audio_p):
                base_audio_src = first_audio_p

    if base_script_src is None and script_txt.strip():
        (pack_dir / "artifacts" / "script.txt").write_text(script_txt, encoding="utf-8")
    elif _is_existing_file_local(base_script_src):
        safe_copy(Path(base_script_src), pack_dir / "artifacts" / "script.txt")

    if _is_existing_file_local(base_image_src):
        safe_copy(Path(base_image_src), pack_dir / "artifacts" / "image.png")

    if _is_existing_file_local(base_audio_src):
        safe_copy(Path(base_audio_src), pack_dir / "artifacts" / "audio.wav")

    missing_base = []
    for label, fp in [
        ("script", pack_dir / "artifacts" / "script.txt"),
        ("image", pack_dir / "artifacts" / "image.png"),
        ("audio", pack_dir / "artifacts" / "audio.wav"),
    ]:
        if not fp.exists() or not fp.is_file():
            missing_base.append(label)
    if missing_base:
        raise SystemExit(f"ERROR: no pude materializar artifacts base del pack: {missing_base}")

    manifest_export = dict(manifest)
    manifest_export["work_dir"] = "."
    manifest_export["config_path"] = _rel_to_base(str(manifest.get("config_path", "")), manifest_dir)
    manifest_export["artifacts"] = {
        "script": "artifacts/script.txt",
        "image": "artifacts/image.png",
        "audio": "artifacts/audio.wav",
    }
    if scenes_rel:
        manifest_export["scenes_v03"] = manifest_scenes_export
        manifest_export["scenes"] = [
            {
                "id": sc["id"],
                "index": sc["index"],
                "text": sc["text"],
                "narration": sc["narration"],
                "onscreen": sc["onscreen"],
                "audio_text": sc["audio_text"],
                "requested_media_type": sc["requested_media_type"],
                "visual_request_kind": sc["visual_request_kind"],
                "visual_kind": sc["visual_kind"],
                "visual_source_kind": sc["visual_source_kind"],
                "visual_capability": sc["visual_capability"],
                "start_ms": sc["start_ms"],
                "end_ms": sc["end_ms"],
                "duration_ms": sc["duration_ms"],
                "artifacts": {
                    "script": sc["script"],
                    "image": sc["image"],
                    "video": sc["video"],
                    "audio": sc["audio"],
                },
            }
            for sc in scenes_rel
        ]
    (pack_dir / "manifest_v03.json").write_text(json.dumps(manifest_export, ensure_ascii=False, indent=2), encoding="utf-8")

    total_audio_ms = 0
    try:
        total_audio_ms = int((manifest.get("scene_builder_v03") or {}).get("total_audio_ms") or 0)
    except Exception:
        total_audio_ms = 0
    if total_audio_ms <= 0:
        try:
            total_audio_ms = int(manifest.get("total_audio_ms") or 0)
        except Exception:
            total_audio_ms = 0
    if total_audio_ms <= 0:
        for sc in scenes_rel:
            total_audio_ms = max(total_audio_ms, _safe_int_local(sc.get("end_ms"), 0))

    scene_builder_meta = dict(manifest.get("scene_builder_v03") or {})
    if total_audio_ms > 0:
        scene_builder_meta["total_audio_ms"] = total_audio_ms

    pack_meta = {
        "pack_version": "v0.3",
        "tag": tag,
        "total_audio_ms": total_audio_ms,
        "source": {
            "manifest_path": "manifest_v03.json",
            "work_dir": _rel_to_base(str(work_dir), manifest_dir),
            "config_path": _rel_to_base(str(manifest.get("config_path", "")), manifest_dir),
            "providers": manifest.get("providers", {}),
        },
        "paths": {
            "script": "artifacts/script.txt",
            "image":  "artifacts/image.png",
            "audio":  "artifacts/audio.wav",
            "manifest": "manifest_v03.json",
        },
        "scene_builder_v03": scene_builder_meta,
    }
    if scenes_rel:
        pack_meta["scenes"] = scenes_rel
        pack_meta["scenes_v03"] = manifest_scenes_export

    (pack_dir / "pack.json").write_text(json.dumps(pack_meta, ensure_ascii=False, indent=2), encoding="utf-8")

    print("OK: pack exportado")
    print("PACK_DIR:", str(pack_dir))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
