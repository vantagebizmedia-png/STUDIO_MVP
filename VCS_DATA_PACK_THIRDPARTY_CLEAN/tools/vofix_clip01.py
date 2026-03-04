import os, sys, json, time, shutil

packdir = sys.argv[1]
clipid  = sys.argv[2]
fallback = sys.argv[3]
ts = time.strftime("%Y%m%d_%H%M%S")

def is_bad_vo(v):
    if v is None:
        return True
    if not isinstance(v, str):
        return True
    return v.strip() == ""

def walk(node):
    changed = 0
    if isinstance(node, dict):
        if node.get("clip_id") == clipid:
            vo = node.get("voiceover", None)
            if is_bad_vo(vo):
                node["voiceover"] = fallback
                changed += 1
        for k, v in list(node.items()):
            changed += walk(v)
    elif isinstance(node, list):
        for it in node:
            changed += walk(it)
    return changed

json_files = []
for root, _, files in os.walk(packdir):
    for fn in files:
        if fn.lower().endswith(".json"):
            json_files.append(os.path.join(root, fn))

edited = []
total_fixes = 0

for fp in sorted(json_files):
    try:
        raw = open(fp, "r", encoding="utf-8").read()
        if not raw.strip():
            continue
        data = json.loads(raw)
    except Exception:
        continue

    fixes = walk(data)
    if fixes > 0:
        bak = fp + ".bak_vofix_" + ts
        shutil.copy2(fp, bak)
        with open(fp, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
            f.write("\n")
        edited.append((fp, bak, fixes))
        total_fixes += fixes

print("VOFIX clip_id=%s" % clipid)
print("PackDir:", packdir)
print("Edited files:", len(edited), "Total fixes:", total_fixes)
for fp, bak, fixes in edited[:50]:
    print(" -", fp, "(fixes=%d)" % fixes)
    print("   backup:", bak)

if len(edited) == 0:
    print("INFO: no encontré nada que arreglar para clip_id=%s (o el VO vacío viene de otro lugar)." % clipid)
