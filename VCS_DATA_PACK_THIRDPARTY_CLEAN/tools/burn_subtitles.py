import argparse
import shutil
import subprocess
from pathlib import Path


def require_cmd(name: str) -> None:
    if shutil.which(name) is None:
        raise SystemExit(f"No se encontró '{name}' en PATH")


def ffmpeg_subtitles_path(p: Path) -> str:
    s = str(p.resolve()).replace("\\", "/")
    if len(s) >= 2 and s[1] == ":":
        s = s[0] + "\\:" + s[2:]
    s = s.replace("'", r"\'")
    return s


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--video", required=True)
    ap.add_argument("--srt", required=True)
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    require_cmd("ffmpeg")
    require_cmd("ffprobe")

    video = Path(args.video)
    srt = Path(args.srt)
    output = Path(args.output)

    if not video.exists():
        raise SystemExit(f"No existe video: {video}")
    if not srt.exists():
        raise SystemExit(f"No existe srt: {srt}")

    output.parent.mkdir(parents=True, exist_ok=True)

    sub_path = ffmpeg_subtitles_path(srt)
    vf = (
        f"subtitles='{sub_path}':charenc=UTF-8:"
        f"force_style='FontName=Arial,FontSize=20,Outline=2,Shadow=0,"
        f"MarginV=28,Alignment=2'"
    )

    cmd = [
        "ffmpeg",
        "-y",
        "-i", str(video),
        "-vf", vf,
        "-map", "0:v:0",
        "-map", "0:a:0",
        "-c:v", "libx264",
        "-preset", "medium",
        "-crf", "18",
        "-c:a", "copy",
        "-movflags", "+faststart",
        str(output),
    ]

    print("VIDEO :", video)
    print("SRT   :", srt)
    print("OUT   :", output)
    print("VF    :", vf)
    subprocess.check_call(cmd)
    print("OK")


if __name__ == "__main__":
    main()
