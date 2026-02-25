import json
import subprocess
import sys
from pathlib import Path
from datetime import datetime

PARTS = ["description", "captions", "hashtags", "music_prompt", "script"]

def readj(p: Path):
    return json.loads(p.read_text(encoding="utf-8"))

def writej(p: Path, obj):
    p.write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding="utf-8")

def run_regenerate(pack_dir: Path, part: str):
    return subprocess.run(
        [sys.executable, "-m", "app.main", "regenerate", "--pack_dir", str(pack_dir), "--part", part],
        check=True,
        capture_output=False,
    )

def main():
    if len(sys.argv) < 2:
        raise SystemExit("Uso: python smoke_all_parts_live_then_replay.py <PACK_DIR>")

    pack_dir = Path(sys.argv[1])
    prov_path = Path("config/providers.json")
    manifest_path = pack_dir / "manifest.json"

    if not prov_path.exists():
        raise SystemExit("ERROR: No encuentro config/providers.json (ejecuta desde la raíz del repo).")
    if not pack_dir.exists():
        raise SystemExit(f"ERROR: pack_dir no existe: {pack_dir}")

    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    bak = Path(f"config/providers.json.bak_smoke_all_{ts}")
    bak.write_text(prov_path.read_text(encoding="utf-8"), encoding="utf-8")

    try:
        # LIVE
        cfg = readj(prov_path)
        cfg["text"]["mode"] = "LIVE"
        writej(prov_path, cfg)
        print("MODE =", readj(prov_path)["text"]["mode"])
        for part in PARTS:
            print("LIVE:", part)
            run_regenerate(pack_dir, part)

        # REPLAY
        cfg = readj(prov_path)
        cfg["text"]["mode"] = "REPLAY"
        writej(prov_path, cfg)
        print("MODE =", readj(prov_path)["text"]["mode"])
        for part in PARTS:
            print("REPLAY:", part)
            run_regenerate(pack_dir, part)

    finally:
        prov_path.write_text(bak.read_text(encoding="utf-8"), encoding="utf-8")

    man = readj(manifest_path)
    tg = man.get("text_generation") or {}

    print("\n=== RESULT SUMMARY (should be cache_hit=true, cached_mode='LIVE') ===")
    for part in PARTS:
        e = tg.get(part) or {}
        print(f"{part:12} mode={e.get('mode')} cache_hit={e.get('cache_hit')} cached_mode={e.get('cached_mode')} cache_key={(e.get('cache_key') or '')[:12]}")

    print("\nBackup providers.json =", bak.name)

if __name__ == "__main__":
    main()
