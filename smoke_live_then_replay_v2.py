import json
import subprocess
import sys
from pathlib import Path
from datetime import datetime

def readj(p: Path):
    return json.loads(p.read_text(encoding="utf-8"))

def writej(p: Path, obj):
    p.write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding="utf-8")

def run_regenerate(pack_dir: Path, part: str):
    # Llama al CLI via módulo: python -m app.main regenerate ...
    return subprocess.run(
        [sys.executable, "-m", "app.main", "regenerate", "--pack_dir", str(pack_dir), "--part", part],
        check=True,
        capture_output=False,
    )

def main():
    if len(sys.argv) < 3:
        raise SystemExit("Uso: python smoke_live_then_replay_v2.py <PACK_DIR> <PART>")

    pack_dir = Path(sys.argv[1])
    part = sys.argv[2].strip()

    prov_path = Path("config/providers.json")
    if not prov_path.exists():
        raise SystemExit("ERROR: No encuentro config/providers.json (ejecuta desde la raíz del repo).")
    if not pack_dir.exists():
        raise SystemExit(f"ERROR: pack_dir no existe: {pack_dir}")

    manifest_path = pack_dir / "manifest.json"

    # Backup providers.json (siempre)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    bak = Path(f"config/providers.json.bak_smoke_{ts}")
    bak.write_text(prov_path.read_text(encoding="utf-8"), encoding="utf-8")

    before = readj(prov_path).get("text", {}).get("mode")

    try:
        # ---- LIVE ----
        cfg = readj(prov_path)
        cfg["text"]["mode"] = "LIVE"
        writej(prov_path, cfg)
        print("MODE (set) =", readj(prov_path)["text"]["mode"])

        print("RUN: regenerate (LIVE)")
        run_regenerate(pack_dir, part)

        # ---- REPLAY ----
        cfg = readj(prov_path)
        cfg["text"]["mode"] = "REPLAY"
        writej(prov_path, cfg)
        print("MODE (set) =", readj(prov_path)["text"]["mode"])

        print("RUN: regenerate (REPLAY)")
        run_regenerate(pack_dir, part)

    finally:
        # restaurar estado original exacto
        prov_path.write_text(bak.read_text(encoding="utf-8"), encoding="utf-8")

    if not manifest_path.exists():
        raise SystemExit(f"ERROR: no existe manifest.json en {pack_dir}")

    man = readj(manifest_path)
    entry = (man.get("text_generation") or {}).get(part)
    print("\nmanifest.text_generation.%s =" % part)
    print(json.dumps(entry, ensure_ascii=False, indent=2))

    print("\nBackup providers.json =", bak.name)
    print("Original mode was =", before)

if __name__ == "__main__":
    main()
