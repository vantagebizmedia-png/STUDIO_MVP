import argparse
import json
import re
import subprocess
from pathlib import Path
from typing import Any


def ffprobe_duration(p: Path) -> float:
    cmd = [
        "ffprobe", "-v", "error",
        "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1",
        str(p),
    ]
    out = subprocess.check_output(cmd, text=True).strip()
    return float(out)


def srt_ts(sec: float) -> str:
    ms = int(round(max(0.0, sec) * 1000.0))
    h = ms // 3600000
    ms %= 3600000
    m = ms // 60000
    ms %= 60000
    s = ms // 1000
    ms %= 1000
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def clean_text(t: str) -> str:
    t = (t or "").replace("\r\n", "\n").replace("\r", "\n")
    t = t.replace("\\r\\n", "\n").replace("\\n", "\n").replace("\\r", "\n")
    t = re.sub(r"\s+", " ", t).strip()
    return t


def wrap_2lines(text: str, width: int = 42) -> str:
    words = text.split()
    if not words:
        return ""

    lines: list[str] = []
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

    used = sum(len(line.split()) for line in lines)
    if used < len(words):
        last = lines[-1]
        if len(last) >= width - 1:
            last = last[: max(0, width - 1)].rstrip()
        lines[-1] = (last + "…").rstrip()

    return "\n".join(lines)


def safe_int(value: Any, default: int = 0) -> int:
    try:
        return int(value)
    except Exception:
        return default


def pick_text(sc: dict[str, Any], field: str) -> str:
    if field == "auto":
        raw = (
            sc.get("onscreen")
            or sc.get("narration")
            or sc.get("text")
            or sc.get("audio_text")
            or sc.get("script_text")
            or ""
        )
    else:
        raw = sc.get(field) or ""
    return wrap_2lines(clean_text(str(raw or "")))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack", required=True, help="Directorio del pack (donde está pack.json)")
    ap.add_argument("--output", required=True, help="Ruta de salida subtitles.srt")
    ap.add_argument("--field", default="auto", choices=["auto", "onscreen", "narration", "text", "audio_text"])
    args = ap.parse_args()

    pack_dir = Path(args.pack).resolve()
    pack_json = pack_dir / "pack.json"
    if not pack_json.exists():
        raise SystemExit(f"ERROR: no existe {pack_json}")

    pack = json.loads(pack_json.read_text(encoding="utf-8"))
    scenes = pack.get("scenes") or []
    if not scenes:
        raise SystemExit("ERROR: pack.json no tiene scenes[]")

    out: list[str] = []
    cues = 0
    cursor_ms = 0

    for idx, sc in enumerate(scenes, start=1):
        a_rel = sc.get("audio")
        if not a_rel:
            raise SystemExit(f"ERROR: scene {idx} sin audio")

        a_path = (pack_dir / str(a_rel)).resolve()
        if not a_path.exists():
            raise SystemExit(f"ERROR: no existe audio {a_path}")

        audio_ms = int(round(ffprobe_duration(a_path) * 1000.0))
        if audio_ms <= 0:
            audio_ms = 200

        txt = pick_text(sc, args.field)
        if not txt:
            start_ms = safe_int(sc.get("start_ms"), -1)
            end_ms = safe_int(sc.get("end_ms"), -1)

            if start_ms >= 0 and end_ms > start_ms:
                cursor_ms = max(cursor_ms, end_ms)
            else:
                dur_ms = safe_int(sc.get("duration_ms"), 0)
                if dur_ms <= 0:
                    dur_ms = audio_ms
                start_ms = cursor_ms
                end_ms = start_ms + dur_ms
                cursor_ms = end_ms
            continue

        explicit_start_ms = safe_int(sc.get("start_ms"), -1)
        explicit_end_ms = safe_int(sc.get("end_ms"), -1)

        if explicit_start_ms >= 0 and explicit_end_ms > explicit_start_ms:
            start_ms = explicit_start_ms
            end_ms = explicit_end_ms
        else:
            dur_ms = safe_int(sc.get("duration_ms"), 0)
            if dur_ms <= 0:
                dur_ms = audio_ms
            start_ms = max(0, cursor_ms)
            end_ms = start_ms + max(200, dur_ms)

        if end_ms - start_ms < 200:
            end_ms = start_ms + 200

        cues += 1
        out.append(str(cues))
        out.append(f"{srt_ts(start_ms / 1000.0)} --> {srt_ts(end_ms / 1000.0)}")
        out.append(txt)
        out.append("")

        cursor_ms = max(cursor_ms, end_ms)

    Path(args.output).write_text("\n".join(out), encoding="utf-8")

    print("OK")
    print("PACK  :", str(pack_dir))
    print("OUTPUT:", str(Path(args.output).resolve()))
    print("CUES  :", cues)
    print("END_MS:", cursor_ms)


if __name__ == "__main__":
    main()