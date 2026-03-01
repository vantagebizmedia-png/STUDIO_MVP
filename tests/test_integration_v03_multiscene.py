import json
import re
from pathlib import Path
import subprocess


def _count_sentences(text: str) -> int:
    parts = [s.strip() for s in re.split(r"(?<=[\.\!\?])\s+", str(text or "").strip()) if s.strip()]
    if parts:
        return len(parts)
    return 1 if str(text or "").strip() else 0


def test_v03_multiscene_generates_scenes_and_manifest():
    cfg = Path("config/studio_v03_multiscene_text_smoke.json")
    assert cfg.exists(), "Falta config/studio_v03_multiscene_text_smoke.json"

    script = "escena uno\n---\nescena dos\n---\nescena tres"
    p = subprocess.run(
        ["python", "-m", "cli.main", "--v03-config", str(cfg), "--script", script],
        text=True,
        capture_output=True,
    )
    assert p.returncode == 0, f"cli.main fallo:\nSTDOUT:\n{p.stdout}\nSTDERR:\n{p.stderr}"

    cfg_obj = json.loads(cfg.read_text(encoding="utf-8-sig"))
    work_dir = Path(cfg_obj.get("work_dir") or "_v03_from_config/artifacts").resolve()
    man = work_dir / "manifest_v03.json"
    assert man.exists(), f"No se creo manifest_v03.json en {work_dir}"

    m = json.loads(man.read_text(encoding="utf-8"))
    scenes = m.get("scenes") or []
    assert isinstance(scenes, list) and len(scenes) >= 2, f"manifest.scenes invalido: {scenes}"

    for s in scenes:
        idx = int(s.get("index", 0) or 0)
        assert idx >= 1, f"scene index invalido: {s}"
        for field in ("narration", "onscreen", "stock_query"):
            assert field in s, f"scene sin {field}: {s}"
            assert str(s.get(field) or "").strip(), f"scene {idx} sin texto en {field}"
        assert _count_sentences(s.get("narration", "")) <= 3
        assert len(str(s.get("onscreen", "")).split()) <= 10
        sq = str(s.get("stock_query", ""))
        assert len(sq.split()) <= 6
        assert re.fullmatch(r"[a-z0-9áéíóúüñ ]+", sq), f"stock_query invalido: {sq}"
        arts = (s.get("artifacts") or {})
        for k in ("script","image","audio"):
            raw = arts.get(k, "")
            assert raw, f"scene artifact missing path: {k}"
            expected = f"artifacts/scenes/scene_{idx:02d}/"
            assert str(raw).replace("\\", "/").startswith(expected), f"scene alias path invalido: {k} -> {raw}"
            fp0 = Path(raw)
            assert not fp0.is_absolute(), f"scene artifact path debe ser relativo: {k} -> {raw}"
            fp = (work_dir / fp0).resolve()
            assert fp.exists(), f"scene artifact missing: {k} -> {fp}"
            assert fp.stat().st_size > 0, f"scene artifact empty: {k} -> {fp}"
        scene_script = (work_dir / Path(str(arts["script"]))).read_text(encoding="utf-8")
        assert "NARRACION:" in scene_script
        assert "ONSCREEN:" in scene_script
        assert "STOCK_QUERY:" in scene_script

    global_arts = m.get("artifacts") or {}
    script_rel = str(global_arts.get("script") or "")
    image_rel = str(global_arts.get("image") or "")
    audio_rel = str(global_arts.get("audio") or "")
    assert script_rel and image_rel and audio_rel, f"artifacts globales invalidos: {global_arts}"
    assert "_s01" in script_rel.replace("\\", "/"), f"script global debe apuntar a escena 1: {script_rel}"
    assert "_s01" in image_rel.replace("\\", "/"), f"image global debe apuntar a escena 1: {image_rel}"
    assert "_s01" in audio_rel.replace("\\", "/"), f"audio global debe apuntar a escena 1: {audio_rel}"
