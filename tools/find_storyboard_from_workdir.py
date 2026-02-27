from pathlib import Path

work_dir = Path(r"C:\Users\vanta\Documents\STUDIO_MVP\_v03_hf_latam_video_20260226_140523\artifacts")
if not work_dir.exists():
    raise SystemExit(f"No existe work_dir: {work_dir}")

candidates = sorted(work_dir.rglob("storyboard.json"))

print("=== WORK_DIR ===")
print(work_dir)
print()

print("=== STORYBOARD CANDIDATES ===")
if not candidates:
    print("(sin resultados)")
else:
    for p in candidates:
        print(p)

