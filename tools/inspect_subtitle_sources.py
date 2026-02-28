import json
from pathlib import Path

pack = Path(r"C:\Users\vanta\Documents\STUDIO_MVP\_v03_hf_latam_video_20260226_140523\workspace\exports\pack_v03_42e0fd6e")
files = [
    pack / "manifest_v03.json",
    pack / "pack.json",
    pack / "artifacts" / "script.txt",
]

print("=" * 120)
print("PACK:", pack)
print("=" * 120)

for p in files:
    print()
    print("-" * 120)
    print("FILE:", p)
    print("EXISTS:", p.exists())
    if not p.exists():
        continue

    if p.suffix.lower() == ".txt":
        txt = p.read_text(encoding="utf-8", errors="replace")
        print()
        print("[TXT PREVIEW]")
        print(txt[:4000])
        continue

    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except Exception as e:
        print("ERROR JSON:", e)
        continue

    print()
    print("[TOP-LEVEL KEYS]")
    if isinstance(data, dict):
        for k in data.keys():
            print("-", k)
    else:
        print(type(data).__name__)

    print()
    print("[CANDIDATE FIELDS]")
    wanted = {
        "text", "script", "narration", "voice", "voiceover", "dialogue",
        "dialog", "scene", "scenes", "subtitle", "subtitles", "caption", "captions"
    }

    hits = []

    def walk(obj, path="root"):
        if isinstance(obj, dict):
            for k, v in obj.items():
                kp = f"{path}.{k}"
                if any(w in str(k).lower() for w in wanted):
                    if isinstance(v, (str, int, float, bool)) or v is None:
                        preview = repr(v)
                    else:
                        preview = f"<{type(v).__name__}>"
                    hits.append((kp, preview))
                walk(v, kp)
        elif isinstance(obj, list):
            for i, v in enumerate(obj):
                walk(v, f"{path}[{i}]")

    walk(data)

    if not hits:
        print("(sin campos obvios)")
    else:
        for kp, preview in hits[:80]:
            print(f"{kp} = {preview[:240]}")
