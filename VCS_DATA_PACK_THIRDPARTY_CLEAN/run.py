# -*- coding: utf-8 -*-
"""STUDIO_MVP — CLI 1-liner para generar video vertical.
Uso:
  python run.py "tema del reel" --seed 123

Salida:
  %STUDIO_WORKSPACE%/runs/<run_id>/render/video_final.mp4  (si no se define, usa ./workspace)
"""

from app.video_pipeline import main

if __name__ == "__main__":
    main()


