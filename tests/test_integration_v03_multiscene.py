import json
from pathlib import Path
import subprocess

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
        arts = (s.get("artifacts") or {})
        for k in ("script","image","audio"):
            raw = arts.get(k, "")
            assert raw, f"scene artifact missing path: {k}"
            fp0 = Path(raw)
            assert not fp0.is_absolute(), f"scene artifact path debe ser relativo: {k} -> {raw}"
            fp = (work_dir / fp0).resolve()
            assert fp.exists(), f"scene artifact missing: {k} -> {fp}"
            assert fp.stat().st_size > 0, f"scene artifact empty: {k} -> {fp}"
