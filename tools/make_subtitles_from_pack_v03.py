import argparse, json, subprocess, re
from pathlib import Path

def ffprobe_duration(p: Path) -> float:
    cmd = [
        "ffprobe", "-v", "error",
        "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1",
        str(p)
    ]
    out = subprocess.check_output(cmd, text=True).strip()
    return float(out)

def srt_ts(sec: float) -> str:
    ms = int(round(max(0.0, sec) * 1000.0))
    h = ms // 3600000; ms %= 3600000
    m = ms // 60000;   ms %= 60000
    s = ms // 1000;    ms %= 1000
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"

def clean_text(t: str) -> str:
    t = (t or "").replace("\r\n", "\n").replace("\r", "\n")
    t = t.replace("\\r\\n", "\n").replace("\\n", "\n").replace("\\r", "\n")
    t = re.sub(r"\s+", " ", t).strip()
    return t

def wrap_2lines(text: str, width: int = 42) -> str:
    # determinista: max 2 líneas, truncado con …
    words = text.split()
    if not words:
        return ""
    lines = []
    cur = ""
    i = 0
    while i < len(words) and len(lines) < 2:
        w = words[i]
        if not cur:
            cur = w
        elif len(cur) + 1 + len(w) <= width:
            cur += " " + w
        else:
            lines.append(cur)
            cur = w
        i += 1
        if len(lines) == 1 and i >= len(words):
            # se terminó justo después de 1 línea
            pass
    if cur and len(lines) < 2:
        lines.append(cur)

    used = sum(len(l.split()) for l in lines)
    if used < len(words):
        # sobran palabras -> truncar última línea con …
        last = lines[-1]
        if len(last) >= width - 1:
            last = last[: max(0, width - 1)].rstrip()
        lines[-1] = (last + "…").rstrip()

    return "\n".join(lines)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack", required=True, help="Directorio del pack (donde está pack.json)")
    ap.add_argument("--output", required=True, help="Ruta de salida subtitles.srt")
    ap.add_argument("--field", default="auto", choices=["auto","onscreen","narration","text","audio_text"])
    args = ap.parse_args()

    pack_dir = Path(args.pack)
    pack_json = pack_dir / "pack.json"
    if not pack_json.exists():
        raise SystemExit(f"ERROR: no existe {pack_json}")

    pack = json.loads(pack_json.read_text(encoding="utf-8"))
    scenes = pack.get("scenes") or []
    if not scenes:
        raise SystemExit("ERROR: pack.json no tiene scenes[]")

    out = []
    t = 0.0
    cues = 0

    for idx, sc in enumerate(scenes, start=1):
        a_rel = sc.get("audio")
        if not a_rel:
            raise SystemExit(f"ERROR: scene {idx} sin audio")
        a_path = (pack_dir / a_rel).resolve()
        if not a_path.exists():
            raise SystemExit(f"ERROR: no existe audio {a_path}")

        dur = ffprobe_duration(a_path)
        # texto fuente
        if args.field == "auto":
            raw = sc.get("onscreen") or sc.get("narration") or sc.get("text") or sc.get("audio_text") or ""
        else:
            raw = sc.get(args.field) or ""
        txt = wrap_2lines(clean_text(raw))
        if not txt:
            # si viene vacío, no generamos cue (pero esto debería ser raro)
            t += dur
            continue

        start = t
        end = t + dur
        # safety: mínimo 0.20s
        if end - start < 0.20:
            end = start + 0.20

        cues += 1
        out.append(str(cues))
        out.append(f"{srt_ts(start)} --> {srt_ts(end)}")
        out.append(txt)
        out.append("")  # blank line

        t += dur

    Path(args.output).write_text("\n".join(out), encoding="utf-8")
    print("OK")
    print("PACK  :", str(pack_dir))
    print("OUTPUT:", str(Path(args.output)))
    print("CUES  :", cues)
    print("DUR   :", round(t, 3))

if __name__ == "__main__":
    main()
