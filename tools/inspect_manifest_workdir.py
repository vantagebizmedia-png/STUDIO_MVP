import json
from pathlib import Path

manifest_path = Path(r"C:\Users\vanta\Documents\STUDIO_MVP\_v03_hf_latam_video_20260226_140523\workspace\exports\pack_v03_42e0fd6e\manifest_v03.json")
if not manifest_path.exists():
    raise SystemExit(f"No existe manifest: {manifest_path}")

obj = json.loads(manifest_path.read_text(encoding="utf-8"))

print("=== MANIFEST PATH ===")
print(manifest_path)
print()

print("=== KEY FIELDS ===")
print("work_dir   :", obj.get("work_dir"))
print("config_path:", obj.get("config_path"))
print("script     :", (obj.get("artifacts") or {}).get("script"))
print("providers  :", obj.get("providers"))
