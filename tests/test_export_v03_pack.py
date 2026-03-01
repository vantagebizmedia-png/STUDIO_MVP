# -*- coding: utf-8 -*-

import json
import subprocess
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
    cmd = [
        "python",
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
