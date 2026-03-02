# -*- coding: utf-8 -*-

import importlib.util
import re
import sys
from pathlib import Path


def _load_module():
    mod_path = Path("tools/finalize_handoff_v03.py").resolve()
    spec = importlib.util.spec_from_file_location("finalize_handoff_v03", str(mod_path))
    mod = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(mod)
    return mod


def _seed_pack(pack_dir: Path) -> None:
    (pack_dir / "artifacts").mkdir(parents=True, exist_ok=True)
    (pack_dir / "pack.json").write_text('{"pack_version":"v0.3"}', encoding="utf-8")
    (pack_dir / "video.mp4").write_bytes(b"base-video")


def test_finalize_handoff_deterministic_without_auto_music(tmp_path, monkeypatch):
    mod = _load_module()
    pack_dir = tmp_path / "pack_v03_abcd1234"
    _seed_pack(pack_dir)
    monkeypatch.setattr(sys, "argv", ["finalize_handoff_v03.py", "--pack-dir", str(pack_dir)])

    rc1 = mod.main()
    assert rc1 == 0

    video = pack_dir / "video.mp4"
    video_music = pack_dir / "video_music_auto.mp4"
    video_final = pack_dir / "video_final.mp4"
    zip_path = pack_dir.parent / f"{pack_dir.name}.final_delivery.zip"
    sha_path = pack_dir.parent / f"{pack_dir.name}.final_delivery.zip.sha256.txt"
    handoff_path = pack_dir / "HANDOFF_READY.txt"

    assert video.exists()
    assert video_music.exists()
    assert video_final.exists()
    assert video_music.read_bytes() == video.read_bytes()
    assert video_final.read_bytes() == video.read_bytes()
    assert zip_path.exists()
    assert sha_path.exists()
    assert handoff_path.exists()

    sha_line_1 = sha_path.read_text(encoding="ascii").strip()
    assert re.fullmatch(rf"[0-9a-f]{{64}}  {re.escape(zip_path.name)}", sha_line_1)

    handoff_1 = handoff_path.read_text(encoding="utf-8")
    assert "PACK_ID: pack_v03_abcd1234" in handoff_1
    assert "VIDEO_BASE: video.mp4" in handoff_1
    assert "VIDEO_MUSIC_AUTO: video_music_auto.mp4" in handoff_1
    assert "VIDEO_FINAL: video_final.mp4" in handoff_1
    assert "AUTO_MUSIC_ENABLED: false" in handoff_1

    rc2 = mod.main()
    assert rc2 == 0
    sha_line_2 = sha_path.read_text(encoding="ascii").strip()
    handoff_2 = handoff_path.read_text(encoding="utf-8")
    assert sha_line_1 == sha_line_2
    assert handoff_1 == handoff_2


def test_finalize_handoff_auto_music_uses_music_outputs(tmp_path, monkeypatch):
    mod = _load_module()
    pack_dir = tmp_path / "pack_v03_wxyz6789"
    _seed_pack(pack_dir)

    calls = []

    def _fake_run(cmd, text=True):
        calls.append([str(x) for x in cmd])
        if "finalize_pack_auto_music.ps1" in [str(x) for x in cmd]:
            (pack_dir / "video_music_auto.mp4").write_bytes(b"music-video")
            (pack_dir / "video_final.mp4").write_bytes(b"music-video")

        class _P:
            returncode = 0
        return _P()

    monkeypatch.setattr(mod.subprocess, "run", _fake_run)
    monkeypatch.setattr(
        sys,
        "argv",
        ["finalize_handoff_v03.py", "--pack-dir", str(pack_dir), "--auto-music", "--music-dir", "music"],
    )

    rc = mod.main()
    assert rc == 0
    assert any("finalize_pack_auto_music.ps1" in " ".join(c) for c in calls)
    assert (pack_dir / "video_music_auto.mp4").read_bytes() == b"music-video"
    assert (pack_dir / "video_final.mp4").read_bytes() == b"music-video"
    assert "AUTO_MUSIC_ENABLED: true" in (pack_dir / "HANDOFF_READY.txt").read_text(encoding="utf-8")
