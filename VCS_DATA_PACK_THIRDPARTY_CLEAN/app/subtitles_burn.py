import os
from typing import List

from PIL import Image, ImageDraw, ImageFont


def _load_font(font_path: str | None, size: int):
    if font_path and os.path.isfile(font_path):
        try:
            return ImageFont.truetype(font_path, size=size)
        except Exception:
            pass
    # fallback portable (puede verse más simple)
    return ImageFont.load_default()


def _wrap_text(draw: ImageDraw.ImageDraw, text: str, font, max_w: int) -> List[str]:
    words = text.split()
    if not words:
        return [""]

    lines = []
    cur = words[0]
    for w in words[1:]:
        trial = cur + " " + w
        bbox = draw.textbbox((0, 0), trial, font=font)
        if (bbox[2] - bbox[0]) <= max_w:
            cur = trial
        else:
            lines.append(cur)
            cur = w
    lines.append(cur)
    return lines


def burn_subtitles_on_image(
    img_path: str,
    out_path: str,
    text: str,
    *,
    target_w: int = 1080,
    target_h: int = 1920,
    font_path: str | None = None,
    font_size: int = 64,
    margin_bottom: int = 180,
    box_padding: int = 22,
    box_alpha: int = 170,
    stroke_w: int = 6,
) -> None:
    os.makedirs(os.path.dirname(out_path), exist_ok=True)

    im = Image.open(img_path).convert("RGBA")

    # safety: ajustar a target
    if im.size != (target_w, target_h):
        im = im.resize((target_w, target_h))

    overlay = Image.new("RGBA", im.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    font = _load_font(font_path, font_size)

    safe_w = target_w - 160
    lines = _wrap_text(draw, (text or "").strip(), font, safe_w)
    lines = lines[:3]  # máx 3 líneas

    # medir
    line_heights = []
    line_widths = []
    for ln in lines:
        bbox = draw.textbbox((0, 0), ln, font=font, stroke_width=stroke_w)
        line_widths.append(bbox[2] - bbox[0])
        line_heights.append(bbox[3] - bbox[1])

    total_h = sum(line_heights) + (len(lines) - 1) * 10
    box_h = total_h + 2 * box_padding
    box_w = min(target_w - 120, max(line_widths) + 2 * box_padding)

    x0 = (target_w - box_w) // 2
    y0 = target_h - margin_bottom - box_h
    x1 = x0 + box_w
    y1 = y0 + box_h

    draw.rounded_rectangle([x0, y0, x1, y1], radius=24, fill=(0, 0, 0, box_alpha))

    y = y0 + box_padding
    for ln, lh, lw in zip(lines, line_heights, line_widths):
        x = (target_w - lw) // 2
        draw.text(
            (x, y),
            ln,
            font=font,
            fill=(255, 255, 255, 255),
            stroke_width=stroke_w,
            stroke_fill=(0, 0, 0, 255),
        )
        y += lh + 10

    out = Image.alpha_composite(im, overlay).convert("RGB")
    out.save(out_path, format="PNG", optimize=True)
