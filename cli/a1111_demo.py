# -*- coding: utf-8 -*-
from __future__ import annotations

import argparse
import os
import urllib.request
import urllib.error

from studio.pipeline import StudioPipeline


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="studio-a1111-demo", description="Demo A1111 (Automatic1111 WebUI API)")
    g = p.add_mutually_exclusive_group(required=False)
    g.add_argument("--check", action="store_true", help="Ping local API (no genera)")
    g.add_argument("--run", action="store_true", help="Genera 1 imagen (requiere STUDIO_ALLOW_LIVE=1)")

    p.add_argument("--script", default="hola", help="Prompt")
    p.add_argument("--out-root", default="_v03_a1111_run", help="Carpeta raíz de salida")
    p.add_argument("--base-url", default="http://127.0.0.1:7860", help="Base URL del WebUI")
    p.add_argument("--w", type=int, default=512, help="width")
    p.add_argument("--h", type=int, default=512, help="height")
    p.add_argument("--steps", type=int, default=20, help="steps")
    p.add_argument("--cfg", type=float, default=7.0, help="cfg_scale")
    p.add_argument("--sampler", default="DPM++ 2M Karras", help="sampler_name")
    p.add_argument("--seed", type=int, default=-1, help="seed (-1 random)")
    return p


def do_check(args) -> int:
    print("== CHECK A1111 ==")
    url = args.base_url.rstrip("/") + "/sdapi/v1/options"
    try:
        with urllib.request.urlopen(url, timeout=2) as resp:
            _ = resp.read(64)
        print("A1111 API: OK ->", url)
        print("Nota: el WebUI debe correr con --api")
        return 0
    except urllib.error.HTTPError as e:
        print(f"A1111 API: NOT READY (HTTP {e.code}) -> {url}")
        return 0
    except Exception as e:
        print(f"A1111 API: NOT READY ({e!r}) -> {url}")
        return 0


def do_run(args) -> int:
    if os.environ.get("STUDIO_ALLOW_LIVE", "") != "1":
        print("RUN bloqueado. Setea STUDIO_ALLOW_LIVE=1 para permitir generación local.")
        return 2

    from studio.providers.voice.edge_voice import EdgeVoiceProvider
    from studio.providers.image.a1111_image import A1111ImageProvider

    out_root = os.path.abspath(args.out_root)
    work_dir = os.path.join(out_root, "artifacts")
    os.makedirs(work_dir, exist_ok=True)

    # voz gratis + imagen local
    voice = EdgeVoiceProvider(voice="en-US-JennyNeural")
    image = A1111ImageProvider(
        base_url=args.base_url,
        width=args.w,
        height=args.h,
        steps=args.steps,
        cfg_scale=args.cfg,
        sampler_name=args.sampler,
        seed=args.seed,
    )

    # validaciones (sin red)
    voice.validate()
    image.validate()

    pipe = StudioPipeline(voice=voice, image=image, work_dir=work_dir)
    img, aud = pipe.run(args.script)

    print("OK a1111-demo RUN")
    print("image:", img)
    print("audio:", aud)
    print("out_root:", out_root)
    return 0


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    if args.run:
        return do_run(args)
    return do_check(args)


if __name__ == "__main__":
    raise SystemExit(main())