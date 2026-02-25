import json
import subprocess
import sys
from pathlib import Path
from datetime import datetime

def readj(p: Path):
    return json.loads(p.read_text(encoding="utf-8"))

def writej(p: Path, obj):
    p.write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding="utf-8")

def main():
    if len(sys.argv) < 3:
        raise SystemExit("Uso: python smoke_live_then_replay.py <PACK_DIR> <PART>\nEj: python smoke_live_then_replay.py C:\\...\\content_pack description")

    pack_dir = Path(sys.argv[1])
    part = sys.argv[2].strip()

    prov_path = Path("config/providers.json")
    if not prov_path.exists():
        raise SystemExit("ERROR: No encuentro config/providers.json (ejecuta desde la raíz del repo).")

    if not pack_dir.exists():
        raise SystemExit(f"ERROR: pack_dir no existe: {pack_dir}")

    manifest_path = pack_dir / "manifest.json"

    # Backup providers.json
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    bak = prov_path.with_suffix(f".json.bak_{ts}")
    bak.write_text(prov_path.read_text(encoding="utf-8"), encoding="utf-8")

    cfg = readj(prov_path)
    before = cfg["text"]["mode"]

    # ---- LIVE ----
    cfg["text"]["mode"] = "LIVE"
    writej(prov_path, cfg)
    cfg2 = readj(prov_path)
    print("MODE (set) =", cfg2["text"]["mode"])

    print("RUN: studio regenerate (LIVE)")
    subprocess.run(["studio", "regenerate", "--pack_dir", str(pack_dir), "--part", part], check=True)

    # ---- REPLAY (restore exact backup) ----
    prov_path.write_text(bak.read_text(encoding="utf-8"), encoding="utf-8")
    cfg3 = readj(prov_path)
    print("MODE (restored) =", cfg3["text"]["mode"])

    print("RUN: studio regenerate (REPLAY)")
    subprocess.run(["studio", "regenerate", "--pack_dir", str(pack_dir), "--part", part], check=True)

    # Print manifest part
    if not manifest_path.exists():
        raise SystemExit(f"ERROR: no existe manifest.json en {pack_dir}")

    man = readj(manifest_path)
    tg = man.get("text_generation", {})
    entry = tg.get(part)
    print("\nmanifest.text_generation.%s =" % part)
    print(json.dumps(entry, ensure_ascii=False, indent=2))

    print("\nBackup providers.json =", bak.name)
    print("Original mode was =", before)

if __name__ == "__main__":
    main()
