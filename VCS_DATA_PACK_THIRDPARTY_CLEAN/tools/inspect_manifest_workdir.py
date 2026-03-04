import argparse
import json
from pathlib import Path

def find_manifest_under(pack_dir: Path) -> Path:
    # Prefer pack_dir/manifest_v03.json
    cand1 = pack_dir / "manifest_v03.json"
    if cand1.exists():
        return cand1

    # Fallback: pack_dir/artifacts/manifest_v03.json
    cand2 = pack_dir / "artifacts" / "manifest_v03.json"
    if cand2.exists():
        return cand2

    raise SystemExit(f"No existe manifest_v03.json en pack-dir: {pack_dir}")

def main() -> int:
    ap = argparse.ArgumentParser(
        prog="inspect_manifest_workdir.py",
        description="Imprime campos clave de un manifest_v03.json (pack-dir o manifest explícito).",
    )
    ap.add_argument("--manifest", type=str, default="", help="Ruta directa al manifest_v03.json")
    ap.add_argument("--pack-dir", type=str, default="", help="Directorio del pack/LIVE que contiene manifest_v03.json")
    args = ap.parse_args()

    manifest_path: Path | None = None

    if args.manifest:
        manifest_path = Path(args.manifest).expanduser().resolve()
        if not manifest_path.exists():
            raise SystemExit(f"No existe manifest: {manifest_path}")
    elif args.pack_dir:
        pack_dir = Path(args.pack_dir).expanduser().resolve()
        if not pack_dir.exists():
            raise SystemExit(f"No existe pack-dir: {pack_dir}")
        manifest_path = find_manifest_under(pack_dir)
    else:
        raise SystemExit("Uso: --manifest <ruta> o --pack-dir <dir>")

    obj = json.loads(manifest_path.read_text(encoding="utf-8"))

    print("=== MANIFEST PATH ===")
    print(manifest_path)
    print()

    print("=== KEY FIELDS ===")
    print("version    :", obj.get("version"))
    print("mode       :", obj.get("mode"))
    print("work_dir   :", obj.get("work_dir"))
    print("config_path:", obj.get("config_path"))
    print("providers  :", obj.get("providers"))
    print()

    sb = obj.get("scene_builder_v03") or {}
    print("=== SCENE_BUILDER_V03 ===")
    print("max_scenes     :", sb.get("max_scenes"))
    print("total_audio_ms :", sb.get("total_audio_ms"))
    print("note           :", sb.get("note"))
    print()

    sc = obj.get("scenes_v03") or []
    print("=== SCENES_V03 ===")
    print("count:", len(sc))
    if sc:
        s0 = sc[0]
        print("first.id        :", s0.get("id"))
        print("first.start_ms  :", s0.get("start_ms"))
        print("first.end_ms    :", s0.get("end_ms"))
        print("first.image_q   :", s0.get("image_query"))
        st = (s0.get("script_text") or "")
        st = st.replace("\n", " ").strip()
        print("first.script[:80]:", st[:80])

    return 0

if __name__ == "__main__":
    raise SystemExit(main())
