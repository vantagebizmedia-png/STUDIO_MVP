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
    global_arts = m.get("artifacts") or {}
    script_rel = str(global_arts.get("script") or "")
    image_rel = str(global_arts.get("image") or "")
    audio_rel = str(global_arts.get("audio") or "")
    assert script_rel and image_rel and audio_rel, f"artifacts globales invalidos: {global_arts}"
    subtitles_rel = str(global_arts.get("subtitles") or "")
    assert subtitles_rel, f"artifacts.subtitles faltante: {global_arts}"
    subtitles_p0 = Path(subtitles_rel)
    assert not subtitles_p0.is_absolute(), f"artifacts.subtitles debe ser relativo: {subtitles_rel}"
    subtitles_fp = (work_dir / subtitles_p0).resolve()
    assert subtitles_fp.exists(), f"subtitles.srt no existe: {subtitles_fp}"
    assert subtitles_fp.stat().st_size > 0, f"subtitles.srt vacio: {subtitles_fp}"
    assert "_s01" in script_rel.replace("\\", "/"), f"script global debe apuntar a escena 1: {script_rel}"
    assert "_s01" in image_rel.replace("\\", "/"), f"image global debe apuntar a escena 1: {image_rel}"
    assert "_s01" in audio_rel.replace("\\", "/"), f"audio global debe apuntar a escena 1: {audio_rel}"
    tag_match = re.search(r"script_([0-9a-f]{8})_s01\.txt$", script_rel.replace("\\", "/"))
    assert tag_match, f"script global debe conservar formato legacy de escena 1: {script_rel}"
    tag = str(tag_match.group(1))

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
        assert scene_script.startswith(f"ESCENA {idx:02d}\n"), f"scene script sin header canonico: {arts['script']}"
        assert "NARRACION:" in scene_script
        assert "ONSCREEN:" in scene_script
        assert "STOCK_QUERY:" in scene_script
        assert scene_script.rstrip().endswith("---"), f"scene script sin cierre canonico: {arts['script']}"
        assert scene_script.count("ESCENA ") == 1
        assert scene_script.count("NARRACION:") == 1
        assert scene_script.count("ONSCREEN:") == 1
        assert scene_script.count("STOCK_QUERY:") == 1

        legacy_script = work_dir / f"script_{tag}_s{idx:02d}.txt"
        assert legacy_script.exists(), f"falta script legacy por escena: {legacy_script}"
        assert legacy_script.read_text(encoding="utf-8") == scene_script
