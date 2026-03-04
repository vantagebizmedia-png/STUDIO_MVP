import os, sys, json, re

pack = sys.argv[1] if len(sys.argv) > 1 else ""

def rj(p):
    with open(p, "r", encoding="utf-8") as f:
        return json.load(f)

def wj(p, o):
    with open(p, "w", encoding="utf-8", newline="\n") as f:
        json.dump(o, f, ensure_ascii=False, indent=2)

def norm(s: str) -> str:
    s = (s or "").strip()
    s = re.sub(r"\s+", " ", s)
    return s

def is_bad_topic(x: str) -> bool:
    x = norm(x)
    return (not x) or (x.upper() == "IGNORED") or (x.lower() in {"none","null","n/a"})

def short_caption(s: str, max_len=92) -> str:
    s = norm(s)
    if not s:
        return " "
    # primera oración
    cut = re.split(r"(?<=[\.\!\?])\s+", s)[0]
    cut = norm(cut)
    if len(cut) <= max_len:
        return cut
    return norm(cut[:max_len].rstrip(" ,.;:") + "...")

def guess_topic_from_clips(clips) -> str:
    words = []
    if isinstance(clips, list):
        for c in clips[:4]:
            if not isinstance(c, dict):
                continue
            vo = str(c.get("voiceover") or c.get("text") or c.get("narration") or "")
            vo = norm(vo).replace("IGNORED", "")
            if not vo:
                continue
            toks = re.findall(r"[A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9]+", vo)
            for w in toks[:10]:
                lw = w.lower()
                if lw in {"hoy","vamos","a","de","la","el","y","en","con","para","una","un","lo","que"}:
                    continue
                words.append(w)
            if len(words) >= 6:
                break
    if not words:
        return "tema"
    return norm(" ".join(words[:6]))

def ensure_topic(manifest, story_bible, clips) -> str:
    # 0) override explícito (determinista)
    ov = norm(os.environ.get("STUDIO_TOPIC_OVERRIDE",""))
    if not is_bad_topic(ov):
        topic = ov
    else:
        topic = ""

        # 1) topic_summary.core_topic
        try:
            ts = manifest.get("topic_summary") or {}
            if isinstance(ts, dict):
                topic = norm(ts.get("core_topic") or "")
        except Exception:
            topic = ""

        # 2) manifest prompt/title
        if is_bad_topic(topic):
            topic = norm(manifest.get("prompt") or manifest.get("title") or "")

        # 3) story_bible core_topic/topic
        if is_bad_topic(topic):
            try:
                topic = norm((story_bible or {}).get("core_topic") or (story_bible or {}).get("topic") or "")
            except Exception:
                topic = ""

        # 4) guess from clips
        if is_bad_topic(topic):
            topic = guess_topic_from_clips(clips)

    if is_bad_topic(topic):
        topic = "tema"

    # escribir back (consistencia third-party)
    manifest["prompt"] = topic

    ts = manifest.get("topic_summary")
    if not isinstance(ts, dict):
        ts = {}
        manifest["topic_summary"] = ts
    ts["core_topic"] = topic

    inp = manifest.get("inputs")
    if not isinstance(inp, dict):
        inp = {}
        manifest["inputs"] = inp
    topics = inp.get("topics")
    if not isinstance(topics, list):
        topics = []
        inp["topics"] = topics
    if len(topics) == 0:
        topics.append(topic)
    else:
        topics[0] = topic

    return topic

def polish_voiceover(t: str, idx: int, n: int, topic: str) -> str:
    t = norm(t)
    if not t:
        return t

    t = t.replace("IGNORED", topic)

    # limpia muletillas (determinista)
    t = re.sub(r"(?i)\b(este|eh|pues|bueno|ok|vale)\b", "", t)
    t = norm(t)

    if idx == 0:
        if topic.lower() not in t.lower():
            t = f"Hoy vamos a entender {topic} de forma simple y aplicable. " + t
    else:
        prefixes = ["Primero", "Luego", "Después", "Por último"]
        p = prefixes[min(idx-1, len(prefixes)-1)]
        if not re.match(r"(?i)^(primero|luego|después|despues|por último|por ultimo)\b", t):
            if len(t) > 1:
                t = f"{p}, {t[0].lower()}{t[1:]}"
            else:
                t = f"{p}, {t}"

    if idx == n-1 and not re.search(r"(?i)\b(ya sabes|listo|prueba|hazlo|aplícalo|aplicalo)\b", t):
        t = t.rstrip(".") + ". Ahora pruébalo hoy."

    if not re.search(r"[\.!\?]$", t):
        t += "."
    return norm(t)

def main(pack: str) -> int:
    if not pack or not os.path.isdir(pack):
        print("polish_pack: invalid pack dir:", pack)
        return 0

    man_p = os.path.join(pack, "manifest.json")
    sb_p  = os.path.join(pack, "storyboard.json")
    cl_p  = os.path.join(pack, "script_by_clips.json")
    bible_p = os.path.join(pack, "story_bible.json")

    for req in (man_p, sb_p, cl_p, bible_p):
        if not os.path.exists(req):
            print("polish_pack: missing required file:", req)
            return 0

    manifest = rj(man_p)
    story_bible = rj(bible_p)
    clips = rj(cl_p)
    sb = rj(sb_p)

    topic = ensure_topic(manifest, story_bible, clips)

    # estilo visual global
    style = story_bible.get("visual_style")
    if not isinstance(style, dict):
        style = {}
    style.setdefault("frame", "vertical 9:16, 1080x1920")
    style.setdefault("look", "cinematic, soft contrast, clean highlights, consistent color grading")
    style.setdefault("detail", "high detail, sharp subject, realistic lighting")
    style.setdefault("camera", "50mm, shallow depth of field, stable composition")
    style.setdefault("palette", "neutral tones with one accent color, consistent palette across scenes")

    neg = story_bible.get("negative_prompt")
    if not isinstance(neg, str) or not neg.strip():
        neg = "text, captions, watermark, logo, lowres, blurry, deformed, extra limbs, bad anatomy, jpeg artifacts"

    story_bible["visual_style"] = style
    story_bible["negative_prompt"] = neg

    # voiceover mejorado + reemplazo IGNORED
    if isinstance(clips, list):
        n = len(clips)
        for i, c in enumerate(clips):
            if not isinstance(c, dict):
                continue
            vo = c.get("voiceover") or c.get("text") or c.get("narration") or ""
            pvo = polish_voiceover(str(vo), i, n, topic)
            if "voiceover" in c or "text" not in c:
                c["voiceover"] = pvo
            else:
                c["text"] = pvo

    # captions.txt cortito y usable
    clip_by_id = {}
    if isinstance(clips, list):
        for c in clips:
            if isinstance(c, dict):
                cid = norm(str(c.get("clip_id") or c.get("id") or ""))
                if cid:
                    vo = c.get("voiceover") or c.get("text") or c.get("narration") or ""
                    clip_by_id[cid] = short_caption(str(vo))

    lines = []
    missing = 0
    if isinstance(sb, list):
        for s in sb:
            if not isinstance(s, dict):
                continue
            cid = norm(str(s.get("from_clip_id") or s.get("clip_id") or s.get("from_clip") or ""))
            txt = clip_by_id.get(cid, "")
            if not txt.strip():
                missing += 1
                txt = " "
            lines.append(txt)

    cap_p = os.path.join(pack, "captions.txt")
    with open(cap_p, "w", encoding="utf-8", newline="\n") as f:
        for ln in lines:
            f.write((ln or " ").rstrip() + "\n")

    # image_prompts consistency
    img_dir = os.path.join(pack, "image_prompts")
    if os.path.isdir(img_dir):
        prefix = f"STYLE: {style['frame']}. {style['look']}. {style['detail']}. {style['camera']}. {style['palette']}."
        suffix = f"NEGATIVE: {neg}"
        for name in os.listdir(img_dir):
            if not name.lower().endswith(".txt"):
                continue
            pth = os.path.join(img_dir, name)
            try:
                txt = open(pth, "r", encoding="utf-8").read().strip()
            except Exception:
                continue
            out = txt
            if "STYLE:" not in out:
                out = prefix + "\n" + out
            if "NEGATIVE:" not in out:
                out = out + "\n" + suffix
            with open(pth, "w", encoding="utf-8", newline="\n") as f:
                f.write(out.rstrip() + "\n")

    wj(man_p, manifest)
    wj(bible_p, story_bible)
    wj(cl_p, clips)

    print("polish_pack: topic =", topic)
    print("polish_pack: updated manifest/story_bible/script_by_clips + captions.txt + image_prompts style/negative")
    print("polish_pack: captions lines:", len(lines), "missing:", missing)
    return 0

if __name__ == "__main__":
    raise SystemExit(main(pack))