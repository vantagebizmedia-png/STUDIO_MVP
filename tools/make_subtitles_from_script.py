import argparse
import re
import subprocess
import textwrap
from pathlib import Path


def ffprobe_duration(video_path: Path) -> float:
    cmd = [
        "ffprobe",
        "-v", "error",
        "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1",
        str(video_path),
    ]
    out = subprocess.check_output(cmd, text=True, encoding="utf-8").strip()
    return float(out)


def srt_ts(seconds: float) -> str:
    if seconds < 0:
        seconds = 0.0
    ms_total = int(round(seconds * 1000.0))
    h = ms_total // 3600000
    ms_total %= 3600000
    m = ms_total // 60000
    ms_total %= 60000
    s = ms_total // 1000
    ms = ms_total % 1000
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def normalize_script(text: str) -> str:
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = text.replace("**", "")
    return text


def extract_spoken_blocks(text: str) -> list[str]:
    lines = normalize_script(text).split("\n")
    out = []

    for raw in lines:
        line = raw.strip()
        if not line:
            continue

        if line == "---":
            continue

        if re.fullmatch(r"\[.*?\]", line):
            continue

        line = re.sub(r"^[A-Za-zÁÉÍÓÚÜÑáéíóúüñ ]+:\s*", "", line).strip()

        if not line:
            continue

        if re.fullmatch(r"\[.*?\]", line):
            continue

        out.append(line)

    return out


def split_sentences(blocks: list[str]) -> list[str]:
    parts = []
    for block in blocks:
        chunked = re.split(r"(?<=[\.\!\?])\s+", block)
        for piece in chunked:
            piece = piece.strip()
            if piece:
                parts.append(piece)
    return parts


def chunk_sentences(sentences: list[str], max_chars: int = 72, max_words: int = 14) -> list[str]:
    cues = []
    current = []

    def flush():
        nonlocal current
        if current:
            cues.append(" ".join(current).strip())
            current = []

    for sent in sentences:
        proposal = (" ".join(current + [sent])).strip()
        word_count = len(proposal.split())

        if current and (len(proposal) > max_chars or word_count > max_words):
            flush()

        if len(sent.split()) > max_words or len(sent) > max_chars:
            words = sent.split()
            temp = []
            for w in words:
                proposal2 = (" ".join(temp + [w])).strip()
                if temp and (len(proposal2) > max_chars or len(proposal2.split()) > max_words):
                    cues.append(" ".join(temp).strip())
                    temp = [w]
                else:
                    temp.append(w)
            if temp:
                cues.append(" ".join(temp).strip())
        else:
            current.append(sent)

    flush()
    return [c for c in cues if c.strip()]


def wrap_two_lines(text: str, width: int = 42) -> str:
    lines = textwrap.wrap(text, width=width, break_long_words=False, break_on_hyphens=False)
    if not lines:
        return text
    if len(lines) <= 2:
        return "\n".join(lines)
    first = lines[0]
    second = " ".join(lines[1:])
    second_wrapped = textwrap.wrap(second, width=width, break_long_words=False, break_on_hyphens=False)
    if not second_wrapped:
        return first
    return first + "\n" + " ".join(second_wrapped)


def allocate_times(cues: list[str], total_duration: float) -> list[tuple[float, float, str]]:
    weights = []
    for cue in cues:
        words = len(cue.split())
        weights.append(max(words, 1))

    total_weight = sum(weights)
    raw_durations = [(w / total_weight) * total_duration for w in weights]

    items = []
    current = 0.0
    for i, (cue, dur) in enumerate(zip(cues, raw_durations), start=1):
        start = current
        end = total_duration if i == len(cues) else current + dur
        items.append((start, end, cue))
        current = end

    return items


def build_srt(cues_timed: list[tuple[float, float, str]]) -> str:
    out = []
    for idx, (start, end, text) in enumerate(cues_timed, start=1):
        out.append(str(idx))
        out.append(f"{srt_ts(start)} --> {srt_ts(end)}")
        out.append(wrap_two_lines(text))
        out.append("")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--script", required=True)
    ap.add_argument("--video", required=True)
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    script_path = Path(args.script)
    video_path = Path(args.video)
    output_path = Path(args.output)

    if not script_path.exists():
        raise SystemExit(f"No existe script: {script_path}")
    if not video_path.exists():
        raise SystemExit(f"No existe video: {video_path}")

    total_duration = ffprobe_duration(video_path)
    raw_text = script_path.read_text(encoding="utf-8", errors="replace")

    spoken_blocks = extract_spoken_blocks(raw_text)
    if not spoken_blocks:
        raise SystemExit("No se encontró texto hablado util en script.txt")

    sentences = split_sentences(spoken_blocks)
    cues = chunk_sentences(sentences, max_chars=72, max_words=14)

    if not cues:
        raise SystemExit("No se pudieron construir cues de subtítulos")

    cues_timed = allocate_times(cues, total_duration)
    srt_text = build_srt(cues_timed)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(srt_text, encoding="utf-8", newline="\n")

    print("OK")
    print("SCRIPT :", script_path)
    print("VIDEO  :", video_path)
    print("OUTPUT :", output_path)
    print("DUR    :", f"{total_duration:.3f}")
    print("CUES   :", len(cues))


if __name__ == "__main__":
    main()
