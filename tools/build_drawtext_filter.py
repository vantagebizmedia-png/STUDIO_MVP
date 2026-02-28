import argparse, json, re
from pathlib import Path

def clean_text(t: str) -> str:
    t = (t or "").replace("\r\n", "\n").replace("\r", "\n")
    t = t.replace("\\r\\n", "\n").replace("\\n", "\n").replace("\\r", "\n")
    t = re.sub(r"\s+", " ", t).strip()
    return t

def wrap_2lines(text: str, width: int = 26) -> str:
    # más agresivo que subs (porque onscreen suele ser más corto)
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
    if cur and len(lines) < 2:
        lines.append(cur)

    used = sum(len(l.split()) for l in lines)
    if used < len(words):
        last = lines[-1]
        lines[-1] = (last + "…").rstrip()

    return "\n".join(lines)

def choose_fontsize(text: str) -> int:
    n = len(text)
    if n <= 18:  return 74
    if n <= 32:  return 60
    if n <= 48:  return 52
    if n <= 64:  return 46
    return 40

def esc_drawtext(s: str) -> str:
    # escape para ffmpeg drawtext
    # - \ -> \\ ; : -> \: ; ' -> \' ; newline -> \n
    s = s.replace("\\", "\\\\")
    s = s.replace(":", "\\:")
    s = s.replace("'", "\\'")
    s = s.replace("\n", "\\n")
    return s

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scene-json", required=True, help="scene dict en json (o ruta a json)")
    ap.add_argument("--font", default="Arial", help="FontName para libass/drawtext")
    ap.add_argument("--w", type=int, default=1080)
    ap.add_argument("--h", type=int, default=1920)
    ap.add_argument("--margin-x", type=int, default=80)
    ap.add_argument("--margin-bottom", type=int, default=160)
    args = ap.parse_args()

    p = Path(args.scene_json)
    if p.exists():
        sc = json.loads(p.read_text(encoding="utf-8"))
    else:
        sc = json.loads(args.scene_json)

    raw = sc.get("onscreen") or sc.get("narration") or sc.get("text") or sc.get("audio_text") or ""
    raw = clean_text(raw)
    txt = wrap_2lines(raw, width=26)
    if not txt:
        print("")  # sin overlay
        return

    fs = choose_fontsize(txt)
    safe_w = args.w - (args.margin_x * 2)
    x = args.margin_x
    y = args.h - args.margin_bottom

    # drawtext con box y borde
    # Nota: usa box=1 y borderw para legibilidad, alineado centrado
    t = esc_drawtext(txt)
        font_part = f"fontfile='{args.fontfile}':" if args.fontfile else f"font='{args.font}':"

    vf = (
        f"drawtext="
        f"{font_part}"
        f"text='{t}':"
        f"fontsize={fs}:"
        f"x=(w-text_w)/2:"
        f"y={y}-text_h:"
        f"fontcolor=white:"
        f"borderw=3:"
        f"bordercolor=black:"
        f"box=1:"
        f"boxcolor=black@0.45:"
        f"boxborderw=18"
    )
    print(vf)

if __name__ == '__main__':
    main()

