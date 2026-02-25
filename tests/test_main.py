# -*- coding: utf-8 -*-
"""
Tests para app/main.py — STUDIO_MVP V2
Cubren: builders deterministas, generate_pack, finalize_pack,
        validate_pack, regenerate (todos los choices), CLI básico.
No requieren API ni ffmpeg — corren 100% offline en DRY mode.
"""

import json
import os
import sys
import tempfile
import unittest

# Asegurar que la raíz del proyecto está en el path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from app.main import (
    build_captions,
    build_clips,
    build_description,
    build_hashtags,
    build_image_prompt,
    build_music_prompt,
    build_story_bible,
    build_storyboard,
    build_topic_summary,
    estimate_clip_seconds,
    finalize_pack,
    generate_pack,
    regenerate,
    split_topics,
    validate_pack,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_pack(tmp_dir: str, **kwargs) -> str:
    """Genera un content_pack completo en DRY mode y devuelve su ruta."""
    defaults = dict(
        topics=["finanzas personales", "habitos", "ahorro"],
        target_format="reel_short",
        language="es",
        style_id="infografia",
        voice_pacing="medio",
        audience_level="principiante",
        constraints=[],
        seed=42,
    )
    defaults.update(kwargs)

    # Apuntar workspace al tmp para no ensuciar el repo
    os.environ["STUDIO_WORKSPACE"] = os.path.join(tmp_dir, "workspace")

    # Necesitamos parchear RUNS_DIR dinámicamente
    import app.main as m
    original_runs = m.RUNS_DIR
    m.RUNS_DIR = os.path.join(tmp_dir, "workspace", "runs")
    os.makedirs(m.RUNS_DIR, exist_ok=True)

    try:
        pack_dir = generate_pack(**defaults)
    finally:
        m.RUNS_DIR = original_runs

    return pack_dir


# ---------------------------------------------------------------------------
# Tests: builders atómicos
# ---------------------------------------------------------------------------

class TestSplitTopics(unittest.TestCase):
    def test_coma(self):
        self.assertEqual(split_topics("a,b,c"), ["a", "b", "c"])

    def test_punto_y_coma(self):
        self.assertEqual(split_topics("x; y; z"), ["x", "y", "z"])

    def test_pipe(self):
        self.assertEqual(split_topics("uno|dos"), ["uno", "dos"])

    def test_vacio_devuelve_default(self):
        self.assertEqual(split_topics(""), ["tema general"])
        self.assertEqual(split_topics("   "), ["tema general"])

    def test_un_tema(self):
        self.assertEqual(split_topics("solo tema"), ["solo tema"])


class TestEstimateClipSeconds(unittest.TestCase):
    def test_rangos_minimo_maximo(self):
        self.assertGreaterEqual(estimate_clip_seconds("hola", "medio"), 4)
        self.assertLessEqual(estimate_clip_seconds("x " * 1000, "rapido"), 60)

    def test_rapido_menor_que_lento(self):
        text = "Este es un texto con varias palabras para estimar la duracion."
        self.assertLessEqual(
            estimate_clip_seconds(text, "rapido"),
            estimate_clip_seconds(text, "lento"),
        )


class TestBuildTopicSummary(unittest.TestCase):
    def test_estructura(self):
        ts = build_topic_summary(["core", "sub1", "sub2"])
        self.assertEqual(ts["core_topic"], "core")
        self.assertIn("sub1", ts["subtopics"])
        self.assertIn("sub2", ts["subtopics"])

    def test_sin_subtemas(self):
        ts = build_topic_summary(["solo"])
        self.assertEqual(ts["core_topic"], "solo")
        self.assertEqual(ts["subtopics"], [])


class TestBuildStoryBible(unittest.TestCase):
    def test_tone_por_audience_level(self):
        casos = [
            ("avanzado", "directo"),
            ("intermedio", "claro"),
            ("principiante", "educativo"),
            ("desconocido", "educativo"),
        ]
        for nivel, tone_esperado in casos:
            sb = build_story_bible(["tema"], "infografia", "es", nivel, [])
            self.assertEqual(sb["tone"], tone_esperado, f"nivel={nivel}")

    def test_campos_obligatorios(self):
        sb = build_story_bible(["tema"], "infografia", "es", "principiante", [])
        for campo in ("tone", "core_message", "continuity_rules", "visual_rules", "language"):
            self.assertIn(campo, sb)

    def test_constraint_tags(self):
        sb = build_story_bible(["t"], "s", "es", "principiante", ["preset_emocion: positivo"])
        self.assertEqual(sb["constraint_tags"].get("preset_emocion"), "positivo")


class TestBuildClips(unittest.TestCase):
    def test_tiene_hook_y_close(self):
        clips = build_clips(["tema"], "reel_short", "medio")
        purposes = [c["purpose"] for c in clips]
        self.assertIn("hook", purposes)
        self.assertIn("close", purposes)

    def test_minimo_3_clips(self):
        clips = build_clips(["solo"], "reel_short", "rapido")
        self.assertGreaterEqual(len(clips), 3)

    def test_cada_clip_tiene_campos(self):
        for clip in build_clips(["t", "s1"], "reel_short", "medio"):
            for campo in ("clip_id", "purpose", "voiceover", "on_screen_text", "estimated_duration_s"):
                self.assertIn(campo, clip)
            self.assertTrue(clip["voiceover"].strip())

    def test_video_long_mas_clips_que_reel_short(self):
        short = build_clips(["t", "a", "b", "c"], "reel_short", "medio")
        long_ = build_clips(["t", "a", "b", "c"], "video_long", "medio")
        self.assertGreaterEqual(len(long_), len(short))


class TestBuildStoryboard(unittest.TestCase):
    def test_un_scene_por_clip(self):
        clips = build_clips(["tema"], "reel_short", "medio")
        scenes = build_storyboard(clips)
        self.assertEqual(len(scenes), len(clips))

    def test_referencias_validas(self):
        clips = build_clips(["tema"], "reel_short", "medio")
        scenes = build_storyboard(clips)
        clip_ids = {c["clip_id"] for c in clips}
        for s in scenes:
            self.assertIn(s["from_clip_id"], clip_ids)
            self.assertTrue(s["image_prompt_ref"].startswith("image_prompts/"))


class TestBuildImagePrompt(unittest.TestCase):
    def test_contiene_safe_area(self):
        clips = build_clips(["inversiones"], "reel_short", "medio")
        sb = build_story_bible(["inversiones"], "infografia", "es", "principiante", [])
        ts = build_topic_summary(["inversiones"])
        scenes = build_storyboard(clips)
        for s, c in zip(scenes, clips):
            prompt = build_image_prompt(s, c, sb, ts)
            self.assertIn("safe area", prompt.lower())

    def test_contiene_estilo_y_tema(self):
        clips = build_clips(["criptomonedas"], "reel_short", "medio")
        sb = build_story_bible(["criptomonedas"], "minimalista", "es", "avanzado", [])
        ts = build_topic_summary(["criptomonedas"])
        scenes = build_storyboard(clips)
        prompt = build_image_prompt(scenes[0], clips[0], sb, ts)
        self.assertIn("minimalista", prompt)
        self.assertIn("criptomonedas", prompt)


class TestBuildMetadata(unittest.TestCase):
    def test_captions_devuelve_lista(self):
        caps = build_captions("inversiones")
        self.assertIsInstance(caps, list)
        self.assertGreaterEqual(len(caps), 2)
        for c in caps:
            self.assertIn("inversiones", c)

    def test_hashtags_empieza_con_hash(self):
        h = build_hashtags(["finanzas", "habitos"])
        self.assertTrue(h.strip().startswith("#"))
        tags = h.strip().split()
        self.assertGreaterEqual(len(tags), 5)

    def test_description_contiene_tema(self):
        d = build_description("ahorro", ["habito", "meta"])
        self.assertIn("ahorro", d)

    def test_music_prompt_contiene_duracion(self):
        mp = build_music_prompt("reel_short", "rapido")
        self.assertIn("30s", mp)
        mp2 = build_music_prompt("video_long", "lento")
        self.assertIn("2-4min", mp2)


# ---------------------------------------------------------------------------
# Tests: generate_pack (DRY mode, sin API)
# ---------------------------------------------------------------------------

class TestGeneratePack(unittest.TestCase):
    def test_crea_archivos_minimos(self):
        with tempfile.TemporaryDirectory() as tmp:
            pack_dir = _make_pack(tmp)
            archivos = [
                "manifest.json",
                "story_bible.json",
                "script_by_clips.json",
                "storyboard.json",
                "captions.txt",
                "hashtags.txt",
                "description.txt",
                "music_prompt.txt",
            ]
            for fn in archivos:
                self.assertTrue(os.path.exists(os.path.join(pack_dir, fn)), f"Falta: {fn}")

    def test_manifest_schema_v2(self):
        with tempfile.TemporaryDirectory() as tmp:
            pack_dir = _make_pack(tmp)
            with open(os.path.join(pack_dir, "manifest.json"), encoding="utf-8") as _f:
                manifest = json.loads(_f.read())
            self.assertEqual(manifest["schema"], "STUDIO_PACK_V2")
            self.assertIn("inputs", manifest)
            self.assertIn("topic_summary", manifest)
            self.assertIn("counts", manifest)

    def test_image_prompts_generados(self):
        with tempfile.TemporaryDirectory() as tmp:
            pack_dir = _make_pack(tmp)
            prompts_dir = os.path.join(pack_dir, "image_prompts")
            self.assertTrue(os.path.isdir(prompts_dir))
            prompts = os.listdir(prompts_dir)
            self.assertGreater(len(prompts), 0)

    def test_seed_reproducible(self):
        with tempfile.TemporaryDirectory() as tmp1, tempfile.TemporaryDirectory() as tmp2:
            p1 = _make_pack(tmp1, seed=99)
            p2 = _make_pack(tmp2, seed=99)
            with open(os.path.join(p1, "script_by_clips.json"), encoding="utf-8") as _f:
                clips1 = json.loads(_f.read())
            with open(os.path.join(p2, "script_by_clips.json"), encoding="utf-8") as _f:
                clips2 = json.loads(_f.read())
            self.assertEqual(len(clips1), len(clips2))
            for c1, c2 in zip(clips1, clips2):
                self.assertEqual(c1["purpose"], c2["purpose"])
                self.assertEqual(c1["voiceover"], c2["voiceover"])

    def test_topic_summary_en_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            pack_dir = _make_pack(tmp, topics=["blockchain", "defi", "nft"])
            with open(os.path.join(pack_dir, "manifest.json"), encoding="utf-8") as _f:
                manifest = json.loads(_f.read())
            ts = manifest["topic_summary"]
            self.assertEqual(ts["core_topic"], "blockchain")
            self.assertIn("defi", ts["subtopics"])


# ---------------------------------------------------------------------------
# Tests: finalize_pack
# ---------------------------------------------------------------------------

class TestFinalizePack(unittest.TestCase):
    def test_crea_tres_outputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            pack_dir = _make_pack(tmp)
            outs = finalize_pack(pack_dir)
            self.assertIn("final_document_md", outs)
            self.assertIn("production_table_csv", outs)
            self.assertIn("prompts_bundle_dir", outs)
            self.assertTrue(os.path.exists(outs["final_document_md"]))
            self.assertTrue(os.path.exists(outs["production_table_csv"]))
            self.assertTrue(os.path.isdir(outs["prompts_bundle_dir"]))

    def test_md_contiene_tema(self):
        with tempfile.TemporaryDirectory() as tmp:
            pack_dir = _make_pack(tmp, topics=["criptomonedas"])
            outs = finalize_pack(pack_dir)
            with open(outs["final_document_md"], encoding="utf-8") as _f:
                md = _f.read()
            self.assertIn("criptomonedas", md)

    def test_csv_tiene_header(self):
        with tempfile.TemporaryDirectory() as tmp:
            pack_dir = _make_pack(tmp)
            outs = finalize_pack(pack_dir)
            with open(outs["production_table_csv"], encoding="utf-8") as _f:
                csv_content = _f.read()
            self.assertIn("scene_id", csv_content)
            self.assertIn("clip_id", csv_content)

    def test_manifest_actualizado_con_final_outputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            pack_dir = _make_pack(tmp)
            finalize_pack(pack_dir)
            with open(os.path.join(pack_dir, "manifest.json"), encoding="utf-8") as _f:
                manifest = json.loads(_f.read())
            self.assertIn("final_outputs", manifest)
            self.assertIn("final_document_md", manifest["final_outputs"])

    def test_bundle_contiene_texto_musica_imagen(self):
        with tempfile.TemporaryDirectory() as tmp:
            pack_dir = _make_pack(tmp)
            outs = finalize_pack(pack_dir)
            bundle = outs["prompts_bundle_dir"]
            self.assertTrue(os.path.exists(os.path.join(bundle, "music", "music_prompt.txt")))
            self.assertTrue(os.path.exists(os.path.join(bundle, "text", "description.txt")))
            # Al menos un prompt de imagen en bundle/image/
            imgs = os.listdir(os.path.join(bundle, "image"))
            self.assertGreater(len(imgs), 0)


# ---------------------------------------------------------------------------
# Tests: validate_pack
# ---------------------------------------------------------------------------

class TestValidatePack(unittest.TestCase):
    def test_pack_valido_ok_true(self):
        with tempfile.TemporaryDirectory() as tmp:
            pack_dir = _make_pack(tmp)
            result = validate_pack(pack_dir)
            self.assertTrue(result["ok"], f"Issues: {result['issues']}")
            self.assertEqual(result["issues"], [])

    def test_genera_run_summary(self):
        with tempfile.TemporaryDirectory() as tmp:
            pack_dir = _make_pack(tmp)
            validate_pack(pack_dir)
            self.assertTrue(os.path.exists(os.path.join(pack_dir, "run_summary.txt")))

    def test_manifest_actualizado_con_validation(self):
        with tempfile.TemporaryDirectory() as tmp:
            pack_dir = _make_pack(tmp)
            validate_pack(pack_dir)
            with open(os.path.join(pack_dir, "manifest.json"), encoding="utf-8") as _f:
                manifest = json.loads(_f.read())
            self.assertIn("validation", manifest)
            self.assertIn("ok", manifest["validation"])

    def test_fallo_si_falta_script_by_clips(self):
        with tempfile.TemporaryDirectory() as tmp:
            pack_dir = _make_pack(tmp)
            os.remove(os.path.join(pack_dir, "script_by_clips.json"))
            with self.assertRaises(Exception):
                validate_pack(pack_dir)


# ---------------------------------------------------------------------------
# Tests: regenerate — todos los choices
# ---------------------------------------------------------------------------

class TestRegenerate(unittest.TestCase):
    def _pack(self, tmp):
        return _make_pack(tmp, topics=["habitos", "disciplina", "foco"])

    def test_choice_20_replay_no_recalcula(self):
        with tempfile.TemporaryDirectory() as tmp:
            pack_dir = self._pack(tmp)
            r = regenerate(pack_dir, 20)
            self.assertTrue(r["ok"])
            self.assertIn("REPLAY", r["note"])

    def test_choice_3_regenera_script(self):
        with tempfile.TemporaryDirectory() as tmp:
            pack_dir = self._pack(tmp)
            r = regenerate(pack_dir, 3)
            self.assertTrue(r["ok"])
            self.assertIn("script_by_clips.json", r["updated"])
            self.assertIn("storyboard.json", r["updated"])

    def test_choice_6_regenera_storyboard(self):
        with tempfile.TemporaryDirectory() as tmp:
            pack_dir = self._pack(tmp)
            r = regenerate(pack_dir, 6)
            self.assertTrue(r["ok"])
            self.assertIn("storyboard.json", r["updated"])

    def test_choice_7_regenera_image_prompts(self):
        with tempfile.TemporaryDirectory() as tmp:
            pack_dir = self._pack(tmp)
            r = regenerate(pack_dir, 7)
            self.assertTrue(r["ok"])
            self.assertIn("image_prompts/*", r["updated"])

    def test_choice_8_regenera_escena_especifica(self):
        with tempfile.TemporaryDirectory() as tmp:
            pack_dir = self._pack(tmp)
            with open(os.path.join(pack_dir, "storyboard.json"), encoding="utf-8") as _f:
                scenes = json.loads(_f.read())
            sid = scenes[0]["scene_id"]
            r = regenerate(pack_dir, 8, scene_id=sid)
            self.assertTrue(r["ok"])
            self.assertIn(sid, r["updated"][0])

    def test_choice_8_sin_scene_id_lanza_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            pack_dir = self._pack(tmp)
            with self.assertRaises(ValueError):
                regenerate(pack_dir, 8, scene_id="")

    def test_choice_8_scene_id_invalido_lanza_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            pack_dir = self._pack(tmp)
            with self.assertRaises(ValueError):
                regenerate(pack_dir, 8, scene_id="scene_99")

    def test_choice_9_music_prompt(self):
        with tempfile.TemporaryDirectory() as tmp:
            pack_dir = self._pack(tmp)
            r = regenerate(pack_dir, 9)
            self.assertTrue(r["ok"])
            self.assertIn("music_prompt.txt", r["updated"])
            self.assertTrue(os.path.exists(os.path.join(pack_dir, "music_prompt.txt")))

    def test_choice_10_captions(self):
        with tempfile.TemporaryDirectory() as tmp:
            pack_dir = self._pack(tmp)
            r = regenerate(pack_dir, 10)
            self.assertTrue(r["ok"])
            self.assertIn("captions.txt", r["updated"])

    def test_choice_11_hashtags(self):
        with tempfile.TemporaryDirectory() as tmp:
            pack_dir = self._pack(tmp)
            r = regenerate(pack_dir, 11)
            self.assertTrue(r["ok"])
            self.assertIn("hashtags.txt", r["updated"])

    def test_choice_12_description(self):
        with tempfile.TemporaryDirectory() as tmp:
            pack_dir = self._pack(tmp)
            r = regenerate(pack_dir, 12)
            self.assertTrue(r["ok"])
            self.assertIn("description.txt", r["updated"])

    def test_choice_13_finalize(self):
        with tempfile.TemporaryDirectory() as tmp:
            pack_dir = self._pack(tmp)
            r = regenerate(pack_dir, 13)
            self.assertTrue(r["ok"])
            self.assertIn("final_outputs", r)

    def test_choice_18_validate(self):
        with tempfile.TemporaryDirectory() as tmp:
            pack_dir = self._pack(tmp)
            r = regenerate(pack_dir, 18)
            self.assertTrue(r["ok"])
            self.assertIn("validation", r)
            self.assertTrue(r["validation"]["ok"])

    def test_choice_invalido_lanza_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            pack_dir = self._pack(tmp)
            with self.assertRaises(ValueError):
                regenerate(pack_dir, 999)

    def test_choices_texto_actualizan_archivos(self):
        """Verifica que después de regenerar, los archivos de texto son más recientes."""
        with tempfile.TemporaryDirectory() as tmp:
            pack_dir = self._pack(tmp)
            for choice, filename in [(9, "music_prompt.txt"), (10, "captions.txt"),
                                     (11, "hashtags.txt"), (12, "description.txt")]:
                path = os.path.join(pack_dir, filename)
                mtime_antes = os.path.getmtime(path)
                import time; time.sleep(0.01)
                regenerate(pack_dir, choice)
                mtime_despues = os.path.getmtime(path)
                self.assertGreaterEqual(mtime_despues, mtime_antes, f"choice={choice}")


# ---------------------------------------------------------------------------
# Tests: CLI básico (sin ejecutar subprocess)
# ---------------------------------------------------------------------------

class TestCLI(unittest.TestCase):
    def test_part_to_choice_mapping(self):
        from app.main import PART_TO_CHOICE
        self.assertEqual(PART_TO_CHOICE["script"], 3)
        self.assertEqual(PART_TO_CHOICE["captions"], 10)
        self.assertEqual(PART_TO_CHOICE["hashtags"], 11)
        self.assertEqual(PART_TO_CHOICE["description"], 12)
        self.assertEqual(PART_TO_CHOICE["music_prompt"], 9)
        self.assertEqual(PART_TO_CHOICE["storyboard"], 6)
        self.assertEqual(PART_TO_CHOICE["image_prompts"], 7)

    def test_main_generate_imprime_json(self):
        import io
        import unittest.mock as mock
        with tempfile.TemporaryDirectory() as tmp:
            os.environ["STUDIO_WORKSPACE"] = os.path.join(tmp, "workspace")
            import app.main as m
            original_runs = m.RUNS_DIR
            m.RUNS_DIR = os.path.join(tmp, "workspace", "runs")
            os.makedirs(m.RUNS_DIR, exist_ok=True)
            try:
                with mock.patch("sys.argv", ["app.main", "generate", "--topics", "ia,futuro", "--seed", "1"]):
                    captured = io.StringIO()
                    with mock.patch("sys.stdout", captured):
                        m.main()
                output = captured.getvalue().strip()
                data = json.loads(output)
                self.assertTrue(data["ok"])
                self.assertIn("pack_dir", data)
            finally:
                m.RUNS_DIR = original_runs


if __name__ == "__main__":
    unittest.main(verbosity=2)
