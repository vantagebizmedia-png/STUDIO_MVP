import os, sys, json, re

pack = sys.argv[1]

def rj(p):
    with open(p, "r", encoding="utf-8") as f:
        return json.load(f)

sb_p = os.path.join(pack, "storyboard.json")
cl_p = os.path.join(pack, "script_by_clips.json")

if not os.path.exists(sb_p) or not os.path.exists(cl_p):
    print("make_captions: missing storyboard/script_by_clips")
    sys.exit(0)

sb = rj(sb_p)
clips = rj(cl_p)

def norm(s: str) -> str:
    s = (s or "").strip()
    s = re.sub(r"\s+", " ", s)
    return s

clip_by_id = {}
for c in clips if isinstance(clips, list) else []:
    if isinstance(c, dict):
        cid = str(c.get("clip_id") or c.get("id") or "").strip()
        if cid:
            vo = c.get("voiceover") or c.get("text") or c.get("narration") or ""
            clip_by_id[cid] = norm(str(vo))

lines = []
missing = 0

for s in sb if isinstance(sb, list) else []:
    if not isinstance(s, dict):
        continue
    cid = str(s.get("from_clip_id") or s.get("clip_id") or s.get("from_clip") or "").strip()
    txt = clip_by_id.get(cid, "")
    if not txt:
        missing += 1
        txt = " "  # evita línea vacía
    lines.append(txt)

out_p = os.path.join(pack, "captions.txt")
with open(out_p, "w", encoding="utf-8", newline="\n") as f:
    for ln in lines:
        f.write((ln or " ").rstrip() + "\n")

print("make_captions: wrote", len(lines), "lines ->", out_p, "| missing:", missing)