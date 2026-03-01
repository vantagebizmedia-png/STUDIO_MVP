import json
from pathlib import Path
import subprocess

def test_v03_text_demo_generates_manifest_and_artifacts(tmp_path):
    # Corre CLI con config demo_text (offline)
    cfg = Path("config/studio_v03_text_smoke.json")
    assert cfg.exists(), "Falta config/studio_v03_text_smoke.json"

    p = subprocess.run(
        ["python", "-m", "cli.main", "--v03-config", str(cfg), "--script", "integration test v03 text"],
        text=True,
        capture_output=True,
    )
    assert p.returncode == 0, f"cli.main fallo:\nSTDOUT:\n{p.stdout}\nSTDERR:\n{p.stderr}"

    # Determina work_dir desde el config
    cfg_obj = json.loads(cfg.read_text(encoding="utf-8-sig"))
    work_dir = Path(cfg_obj.get("work_dir") or "_v03_from_config/artifacts").resolve()
    assert work_dir.exists(), f"work_dir no existe: {work_dir}"

    man = work_dir / "manifest_v03.json"
    assert man.exists(), f"No se creo manifest_v03.json en {work_dir}"

    m = json.loads(man.read_text(encoding="utf-8"))
    arts = m.get("artifacts") or {}
    for k in ("script", "image", "audio"):
        assert arts.get(k), f"manifest.artifacts.{k} vacio"
        assert not Path(arts[k]).is_absolute(), f"manifest.artifacts.{k} debe ser relativo: {arts[k]}"

    sp = (work_dir / arts["script"]).resolve()
    ip = (work_dir / arts["image"]).resolve()
    ap = (work_dir / arts["audio"]).resolve()
    assert sp.exists(), f"script no existe: {sp}"
    assert ip.exists(), f"image no existe: {ip}"
    assert ap.exists(), f"audio no existe: {ap}"

    assert sp.stat().st_size > 0, "script.txt vacio"
    assert ip.stat().st_size > 0, "image.png vacio"
    assert ap.stat().st_size > 0, "audio.wav vacio"
