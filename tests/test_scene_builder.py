# -*- coding: utf-8 -*-

import re

from studio.scene_builder import build_scenes, render_scenes_strict


def _count_sentences(text: str) -> int:
    parts = [s.strip() for s in re.split(r"(?<=[\.\!\?])\s+", str(text or "").strip()) if s.strip()]
    if parts:
        return len(parts)
    return 1 if str(text or "").strip() else 0


def test_scene_builder_truncates_and_sanitizes_fields():
    raw = (
        "NARRACION: uno. dos. tres. cuatro. cinco.\n"
        "ONSCREEN: uno dos tres cuatro cinco seis siete ocho nueve diez once doce\n"
        "STOCK_QUERY: \"hola\" mundo !!! 123 #video @test alpha beta gamma delta\n"
    )
    scenes = build_scenes(raw, max_scenes=1, split_mode="auto")
    assert len(scenes) == 1
    s = scenes[0]
    assert _count_sentences(s.narration) <= 3
    assert len(s.onscreen.split()) <= 10
    assert len(s.stock_query.split()) <= 6
    assert re.fullmatch(r"[a-z0-9áéíóúüñ ]+", s.stock_query)


def test_scene_builder_fallbacks_are_short_and_present():
    scenes = build_scenes("ESCENA 01\n---\nESCENA 02", max_scenes=2, split_mode="dash")
    assert len(scenes) == 2
    for s in scenes:
        assert s.narration.strip()
        assert s.onscreen.strip()
        assert s.stock_query.strip()
        assert _count_sentences(s.narration) <= 2
        assert len(s.onscreen.split()) <= 6
        assert len(s.stock_query.split()) <= 4


def test_scene_builder_respects_dash_split_and_max_scenes():
    raw = "NARRACION: uno\n---\nNARRACION: dos\n---\nNARRACION: tres"
    scenes = build_scenes(raw, max_scenes=2, split_mode="dash")
    assert len(scenes) == 2


def test_render_scenes_strict_format():
    scenes = build_scenes("NARRACION: uno\n---\nNARRACION: dos", max_scenes=2, split_mode="dash")
    out = render_scenes_strict(scenes)
    assert "ESCENA 01" in out
    assert "ESCENA 02" in out
    assert out.count("NARRACION:") == 2
    assert out.count("ONSCREEN:") == 2
    assert out.count("STOCK_QUERY:") == 2
    assert out.count("\n---\n") == 1
