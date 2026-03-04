import os, json, sys
pack = sys.argv[1]
def rj(p):
  with open(p,"r",encoding="utf-8") as f: return json.load(f)
def as_list(x):
  if isinstance(x,list): return x
  if isinstance(x,dict):
    for k in ("scenes","storyboard","items","data","clips"):
      v = x.get(k)
      if isinstance(v,list): return v
  return []
print("== DIAG PACK ==")
print("pack:", pack)
sb_p = os.path.join(pack,"storyboard.json")
cl_p = os.path.join(pack,"script_by_clips.json")
print("storyboard.json exists:", os.path.exists(sb_p))
print("script_by_clips.json exists:", os.path.exists(cl_p))
if not os.path.exists(sb_p) or not os.path.exists(cl_p):
  sys.exit(0)
sb_raw = rj(sb_p)
cl_raw = rj(cl_p)
sb = as_list(sb_raw)
cl = as_list(cl_raw)
print("storyboard type:", type(sb_raw).__name__, "normalized_len:", len(sb))
print("clips type:", type(cl_raw).__name__, "normalized_len:", len(cl))
if sb[:1]: print("storyboard[0] keys:", sorted(list(sb[0].keys()))[:25])
if cl[:1]: print("clips[0] keys:", sorted(list(cl[0].keys()))[:25])
clip_by_id = {str(c.get("clip_id","")).strip(): c for c in cl if isinstance(c,dict) and str(c.get("clip_id","")).strip()}
missing_ref = 0; total = 0; missing_prompt = 0; picked = 0
for s in sb:
  if not isinstance(s,dict): continue
  scene_id = str(s.get("scene_id") or s.get("id") or "").strip()
  from_clip = str(s.get("from_clip_id") or s.get("clip_id") or s.get("from_clip") or "").strip()
  pref = str(s.get("image_prompt_ref") or s.get("prompt_ref") or s.get("image_prompt_path") or "").strip()
  if not scene_id or not from_clip: continue
  total += 1
  if pref:
    pth = os.path.join(pack, pref.replace("/", os.sep))
    if not os.path.exists(pth): missing_prompt += 1
    else: picked += 1
  else:
    # puede venir prompt inline
    inline = s.get("image_prompt")
    if isinstance(inline,str) and inline.strip(): picked += 1
    else: missing_ref += 1
print("storyboard usable rows:", total)
print("picked scenes (tienen prompt):", picked)
print("missing prompt_ref:", missing_ref)
print("missing prompt file:", missing_prompt)
print("TIP: si picked=0, _collect_scenes devuelve 0 y cae en el ValueError.")
