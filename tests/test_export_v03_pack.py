# -*- coding: utf-8 -*-

import json
import subprocess
import sys
from pathlib import Path


def test_export_v03_pack_uses_manifest_parent_and_emits_relative_paths(tmp_path):
    run_dir = tmp_path / "run_artifacts"
    run_dir.mkdir(parents=True, exist_ok=True)

    (run_dir / "script_abcd1234.txt").write_text("hola export", encoding="utf-8")
    (run_dir / "image_abcd1234.png").write_bytes(b"img")
    (run_dir / "audio_abcd1234.wav").write_bytes(b"aud")

    manifest = {
        "version": "v0.3",
        "mode": "RUN",
        "artifacts": {
            "script": "script_abcd1234.txt",
            "image": "image_abcd1234.png",
            "audio": "audio_abcd1234.wav",
        },
        "providers": {
            "text": "demo_text",
            "image": "demo_image",
            "voice": "demo_voice",
        },
    }
    manifest_path = run_dir / "manifest_v03.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")

    out_root = tmp_path / "exports"
    cmd = [sys.executable,
        "tools/export_v03_pack.py",
        "--manifest",
        str(manifest_path),
        "--out-root",
        str(out_root),
        "--overwrite",
    ]
    p1 = subprocess.run(cmd, text=True, capture_output=True)
    assert p1.returncode == 0, f"export 1 fallo:\nSTDOUT:\n{p1.stdout}\nSTDERR:\n{p1.stderr}"

    pack_dir = out_root / "pack_v03_abcd1234"
    assert pack_dir.exists(), f"No se creo pack esperado: {pack_dir}"

    pack_json_path = pack_dir / "pack.json"
    pack_json_1 = pack_json_path.read_text(encoding="utf-8")
    pack = json.loads(pack_json_1)

    assert "created_at_utc" not in pack, "pack.json no debe incluir timestamp no determinista"
    assert "pack_dir" not in (pack.get("paths") or {}), "paths.pack_dir no debe serializar path absoluto"
    assert (pack.get("source") or {}).get("manifest_path") == "manifest_v03.json"
    assert (pack.get("source") or {}).get("work_dir") == "."

    for rel in [
        (pack.get("source") or {}).get("manifest_path", ""),
        (pack.get("source") or {}).get("work_dir", ""),
        (pack.get("source") or {}).get("config_path", ""),
        ((pack.get("paths") or {}).get("script", "")),
        ((pack.get("paths") or {}).get("image", "")),
        ((pack.get("paths") or {}).get("audio", "")),
        ((pack.get("paths") or {}).get("manifest", "")),
    ]:
        if rel:
            assert not Path(rel).is_absolute(), f"Path absoluto no permitido en pack.json: {rel}"

    exported_manifest = json.loads((pack_dir / "manifest_v03.json").read_text(encoding="utf-8"))
    assert exported_manifest.get("work_dir") == "."
    arts = exported_manifest.get("artifacts") or {}
    for k in ("script", "image", "audio"):
        rel = str(arts.get(k) or "")
        assert rel, f"manifest exportado sin artifacts.{k}"
        assert not Path(rel).is_absolute(), f"manifest exportado con path absoluto: artifacts.{k}={rel}"

    p2 = subprocess.run(cmd, text=True, capture_output=True)
    assert p2.returncode == 0, f"export 2 fallo:\nSTDOUT:\n{p2.stdout}\nSTDERR:\n{p2.stderr}"
    pack_json_2 = pack_json_path.read_text(encoding="utf-8")
    assert pack_json_1 == pack_json_2, "pack.json debe ser estable entre exports iguales"


def test_export_v03_pack_multiscene_paths_are_stable_and_relative(tmp_path):
    run_dir = tmp_path / "run_artifacts"
    run_dir.mkdir(parents=True, exist_ok=True)

    (run_dir / "script_t1234567_s01.txt").write_text("NARRACION: uno\n", encoding="utf-8")
    (run_dir / "image_t1234567_s01.png").write_bytes(b"img1")
    (run_dir / "audio_t1234567_s01.wav").write_bytes(b"aud1")
    (run_dir / "script_t1234567_s02.txt").write_text("NARRACION: dos\n", encoding="utf-8")
    (run_dir / "image_t1234567_s02.png").write_bytes(b"img2")
    (run_dir / "audio_t1234567_s02.wav").write_bytes(b"aud2")

    for idx in (1, 2):
        sdir = run_dir / "artifacts" / "scenes" / f"scene_{idx:02d}"
        sdir.mkdir(parents=True, exist_ok=True)
        (sdir / "script.txt").write_text(f"NARRACION: scene {idx}\n", encoding="utf-8")
        (sdir / "image.png").write_bytes(f"img{idx}".encode("ascii"))
        (sdir / "audio.wav").write_bytes(f"aud{idx}".encode("ascii"))

    manifest = {
        "version": "v0.3",
        "mode": "RUN",
        "work_dir": ".",
        "artifacts": {
            "script": "script_t1234567_s01.txt",
            "image": "image_t1234567_s01.png",
            "audio": "audio_t1234567_s01.wav",
        },
        "scenes": [
            {
                "index": 1,
                "narration": "uno",
                "onscreen": "",
                "stock_query": "uno",
                "artifacts": {
                    "script": "script_t1234567_s01.txt",
                    "image": "image_t1234567_s01.png",
                    "audio": "audio_t1234567_s01.wav",
                },
            },
            {
                "index": 2,
                "narration": "dos",
                "onscreen": "",
                "stock_query": "dos",
                "artifacts": {
                    "script": "script_t1234567_s02.txt",
                    "image": "image_t1234567_s02.png",
                    "audio": "audio_t1234567_s02.wav",
                },
            },
        ],
        "providers": {"text": "demo_text", "image": "demo_image", "voice": "demo_voice"},
    }
    manifest_path = run_dir / "manifest_v03.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")

    out_root = tmp_path / "exports"
    cmd = [sys.executable,
        "tools/export_v03_pack.py",
        "--manifest",
        str(manifest_path),
        "--out-root",
        str(out_root),
        "--overwrite",
    ]
    p = subprocess.run(cmd, text=True, capture_output=True)
    assert p.returncode == 0, f"export multiscene fallo:\nSTDOUT:\n{p.stdout}\nSTDERR:\n{p.stderr}"

    pack_dir = out_root / "pack_v03_t1234567_s01"
    assert pack_dir.exists(), f"No se creo pack esperado: {pack_dir}"

    pack = json.loads((pack_dir / "pack.json").read_text(encoding="utf-8"))
    scenes = pack.get("scenes") or []
    assert len(scenes) == 2, f"pack.json scenes invalido: {scenes}"
    for idx, row in enumerate(scenes, start=1):
        assert row.get("script") == f"artifacts/scenes/scene_{idx:02d}/script.txt"
        assert row.get("image") == f"artifacts/scenes/scene_{idx:02d}/image.png"
        assert row.get("audio") == f"artifacts/scenes/scene_{idx:02d}/audio.wav"
        for k in ("script", "image", "audio"):
            assert not Path(str(row.get(k) or "")).is_absolute()

    exported_manifest = json.loads((pack_dir / "manifest_v03.json").read_text(encoding="utf-8"))
    for row in exported_manifest.get("scenes") or []:
        arts = row.get("artifacts") or {}
        for k in ("script", "image", "audio"):
            rel = str(arts.get(k) or "")
            assert rel, f"manifest exportado sin scenes.artifacts.{k}"
            assert not Path(rel).is_absolute(), f"manifest exportado con absoluto en scenes.artifacts.{k}: {rel}"

