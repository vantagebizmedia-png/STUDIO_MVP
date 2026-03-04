import os, json, sys
pack = sys.argv[1]
sb = json.load(open(os.path.join(pack, "storyboard.json"), "r", encoding="utf-8"))
missing = []
for s in sb:
    ref = str(s.get("image_prompt_ref", "")).strip()
    if ref:
        p = os.path.join(pack, ref.replace("/", os.sep))
        if not os.path.exists(p):
            missing.append(ref)
print("missing_prompt_files:", len(missing))
if missing:
    print("sample:", missing[:6])
