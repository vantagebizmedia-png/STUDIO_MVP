# studio/audio_clip_v03.py
# Deterministic WAV clipper (stdlib only). No ffmpeg. Replay-safe.

from __future__ import annotations

import os
import wave
from typing import Tuple


def _ms_to_frames(ms: int, framerate: int) -> int:
    # round-half-up? We want deterministic + consistent. Use integer floor.
    # Since scene boundaries come from evenly-split timings, floor is OK.
    if ms <= 0:
        return 0
    return int((ms * framerate) // 1000)


def read_wav_info(path: str) -> Tuple[int, int, int, int, int]:
    """
    Returns (nchannels, sampwidth, framerate, nframes, comptype)
    """
    with wave.open(path, "rb") as w:
        return (w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes(), 0)


def clip_wav_segment(
    master_wav: str,
    out_wav: str,
    start_ms: int,
    end_ms: int,
) -> None:
    """
    Deterministically write a WAV segment [start_ms, end_ms) from master_wav.
    If master is shorter than requested, pad with zero-bytes (silence) deterministically.
    """
    if end_ms < start_ms:
        # swap defensively (still deterministic)
        start_ms, end_ms = end_ms, start_ms

    if start_ms < 0:
        start_ms = 0
    if end_ms < 0:
        end_ms = 0

    os.makedirs(os.path.dirname(out_wav) or ".", exist_ok=True)

    with wave.open(master_wav, "rb") as r:
        nch = r.getnchannels()
        sw  = r.getsampwidth()
        fr  = r.getframerate()
        nfr = r.getnframes()
        params = r.getparams()

        start_frame = _ms_to_frames(start_ms, fr)
        end_frame   = _ms_to_frames(end_ms, fr)
        if end_frame < start_frame:
            end_frame = start_frame

        # Clamp read window to available frames
        read_start = min(max(start_frame, 0), nfr)
        read_end   = min(max(end_frame, 0), nfr)
        to_read = max(0, read_end - read_start)

        r.setpos(read_start)
        data = r.readframes(to_read)

        # If we need more (requested longer than master), pad with silence bytes.
        req_frames = max(0, end_frame - start_frame)
        got_frames = to_read
        missing_frames = max(0, req_frames - got_frames)

        if missing_frames > 0:
            frame_bytes = nch * sw
            data += (b"\x00" * (missing_frames * frame_bytes))

        # Always write a valid wav with same params
        with wave.open(out_wav, "wb") as w:
            w.setparams(params)
            w.writeframes(data)


def safe_copy_master_as_clip(master_wav: str, out_wav: str) -> None:
    """
    Deterministic fallback: byte-for-byte copy of master wav.
    (Used only if clipping fails in the caller.)
    """
    os.makedirs(os.path.dirname(out_wav) or ".", exist_ok=True)
    with open(master_wav, "rb") as src, open(out_wav, "wb") as dst:
        while True:
            b = src.read(1024 * 1024)
            if not b:
                break
            dst.write(b)
