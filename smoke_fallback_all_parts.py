import json
import subprocess
import sys
from pathlib import Path

PARTS = ["description", "captions", "hashtags", "music_prompt", "script"]

def readj(p: Path):
    return json.loads(p.read_text(encoding="utf-8"))

def run_regenerate(pack_dir: Path, part: str):
    return subprocess.run(
        [sys.executable, "-m", "app.main", "regenerate", "--pack_dir", str(pack_dir), "--part", part],
        check=True,
        capture_output=False,
    )

def main():
    if len(sys.argv) < 2:
        raise SystemExit("Uso: python smoke_fallback_all_parts.py <PACK_DIR_NEW>")

    pack_dir = Path(sys.argv[1])
    manifest_path = pack_dir / "manifest.json"

    if not pack_dir.exists():
        raise SystemExit(f"ERROR: pack_dir no existe: {pack_dir}")

    for part in PARTS:
        print("REPLAY strict (expect fallback):", part)
        run_regenerate(pack_dir, part)

    man = readj(manifest_path)
    tg = man.get("text_generation") or {}

    print("\n=== RESULT SUMMARY (should be REPLAY_FALLBACK + provider fallback_deterministic) ===")
    for part in PARTS:
        e = tg.get(part) or {}
        print(f"{part:12} mode={e.get('mode')} provider={e.get('provider')} cache_hit={e.get('cache_hit')} cache_key='{e.get('cache_key')}' note={(e.get('note') or '')[:60]}")

if __name__ == "__main__":
    main()
