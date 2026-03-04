# -*- coding: utf-8 -*-
from __future__ import annotations

import argparse
import os
import shutil

from studio.pipeline import StudioPipeline


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="studio-free-demo", description="Demo providers gratuitos (Edge TTS + HF Image)")
    g = p.add_mutually_exclusive_group(required=False)
    g.add_argument("--check", action="store_true", help="Solo verifica dependencias/vars (no llama red)")
    g.add_argument("--run", action="store_true", help="Ejecuta generación real (requiere STUDIO_ALLOW_LIVE=1)")

    p.add_argument("--script", default="hola", help="Texto/prompt base")
    p.add_argument("--out-root", default="_v03_free_run", help="Carpeta raíz de salida")
    p.add_argument("--edge-voice", default="en-US-JennyNeural", help="Voz Edge TTS")
    p.add_argument("--hf-model", default="black-forest-labs/FLUX.1-schnell", help="Modelo HF")
    p.add_argument("--hf-token-env", default="HF_TOKEN", help="Nombre de env var para token HF")
    p.add_argument("--hf-provider", default="hf-inference", help="Provider Inference Providers (auto/fal-ai/replicate/...)")
    return p


def do_check(args) -> int:
    ok = True
    print("== CHECK free providers ==")

    # edge-tts
    try:
        import edge_tts  # noqa: F401
        print("edge-tts: OK")
    except Exception as e:
        ok = False
        print(f"edge-tts: MISSING ({e!r}) -> instala: pip install edge-tts")

    # ffmpeg
    ff = shutil.which("ffmpeg")
    if ff:
        print(f"ffmpeg: OK ({ff})")
    else:
        ok = False
        print("ffmpeg: MISSING -> instala ffmpeg y ponlo en PATH (requerido para WAV)")

    # HF token
    tok = os.environ.get(args.hf_token_env, "").strip()
    if tok:
        print(f"{args.hf_token_env}: OK (set)")
    else:
        ok = False
        print(f"{args.hf_token_env}: MISSING -> setea env {args.hf_token_env}=<token>")

    print("RESULT:", "OK" if ok else "NOT READY")
    return 0  # check nunca falla el proceso; solo reporta


def do_run(args) -> int:
    if os.environ.get("STUDIO_ALLOW_LIVE", "") != "1":
        print("RUN bloqueado. Setea STUDIO_ALLOW_LIVE=1 para permitir llamadas externas.")
        return 2

    from studio.providers.voice.edge_voice import EdgeVoiceProvider
    from studio.providers.image.hf_image import HFImageProvider

    out_root = os.path.abspath(args.out_root)
    work_dir = os.path.join(out_root, "artifacts")
    os.makedirs(work_dir, exist_ok=True)

    voice = EdgeVoiceProvider(voice=args.edge_voice)
    image = HFImageProvider(model=args.hf_model, provider=args.hf_provider, token_env=args.hf_token_env)

    # validate fuerte (mejor error temprano)
    voice.validate()
    image.validate()

    pipe = StudioPipeline(voice=voice, image=image, work_dir=work_dir)
    img, aud = pipe.run(args.script)

    print("OK free-demo RUN")
    print(f"image: {img}")
    print(f"audio: {aud}")
    print(f"out_root: {out_root}")
    return 0


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)

    if args.run:
        return do_run(args)

    # default: check
    return do_check(args)


if __name__ == "__main__":
    raise SystemExit(main())