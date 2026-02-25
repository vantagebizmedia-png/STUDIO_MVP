# -*- coding: utf-8 -*-
"""Tests unitarios para STUDIO_MVP.
Cubre: video_utils.py, providers/_utils.py, pipeline lógica.
No requiere moviepy, ffmpeg ni APIs externas.
"""

import sys
import os
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))


class TestNormalizeMotionProfiles(unittest.TestCase):
    def _fn(self, *args):
        from app.video_utils import normalize_motion_profiles
        return normalize_motion_profiles(*args)

    def test_none_devuelve_lista_de_none(self):
        self.assertEqual(self._fn(None, 3), ["none", "none", "none"])

    def test_string_unico_se_repite(self):
        self.assertEqual(self._fn("pan_left", 4), ["pan_left"] * 4)

    def test_lista_exacta(self):
        self.assertEqual(self._fn(["slow_zoom_in", "pan_right"], 2), ["slow_zoom_in", "pan_right"])

    def test_lista_corta_se_extiende_con_ultimo(self):
        self.assertEqual(self._fn(["pan_up"], 3), ["pan_up", "pan_up", "pan_up"])

    def test_lista_larga_se_recorta(self):
        self.assertEqual(self._fn(["a", "b", "c", "d"], 2), ["a", "b"])

    def test_n_cero_devuelve_lista_vacia(self):
        self.assertEqual(self._fn("pan_left", 0), [])


class TestNormalizeMotionStrengths(unittest.TestCase):
    def _fn(self, *args):
        from app.video_utils import normalize_motion_strengths
        return normalize_motion_strengths(*args)

    def test_none_usa_default(self):
        self.assertEqual(self._fn(None, 3, 0.10), [0.10, 0.10, 0.10])

    def test_scalar_se_repite(self):
        self.assertEqual(self._fn(0.15, 3, 0.10), [0.15, 0.15, 0.15])

    def test_lista_exacta(self):
        result = self._fn([0.10, 0.20, 0.15], 3, 0.10)
        self.assertAlmostEqual(result[0], 0.10)
        self.assertAlmostEqual(result[1], 0.20)
        self.assertAlmostEqual(result[2], 0.15)

    def test_lista_corta_se_extiende(self):
        result = self._fn([0.10], 3, 0.05)
        self.assertEqual(len(result), 3)
        self.assertAlmostEqual(result[2], 0.10)  # repite el último

    def test_n_cero_devuelve_vacio(self):
        self.assertEqual(self._fn(0.10, 0, 0.10), [])


class TestBuildVfFilters(unittest.TestCase):
    def _fn(self, *args):
        from app.video_utils import build_vf_filters
        return build_vf_filters(*args)

    def test_sin_efectos_devuelve_vacio(self):
        self.assertEqual(self._fn(0.0, 0.0, 12345), "")

    def test_solo_grain_genera_noise_filter(self):
        result = self._fn(0.02, 0.0, 12345)
        self.assertIn("noise=alls=", result)
        self.assertNotIn("vignette", result)

    def test_solo_vignette_genera_vignette_filter(self):
        result = self._fn(0.0, 0.18, 12345)
        self.assertIn("vignette=", result)
        self.assertNotIn("noise", result)

    def test_ambos_combinados_con_coma(self):
        result = self._fn(0.02, 0.18, 12345)
        self.assertIn("noise=alls=", result)
        self.assertIn("vignette=", result)
        self.assertIn(",", result)

    def test_grain_0020_mapea_a_alls_20(self):
        result = self._fn(0.020, 0.0, 0)
        self.assertIn("alls=20", result)

    def test_seed_diferente_produce_diferente_resultado(self):
        r1 = self._fn(0.02, 0.0, 111)
        r2 = self._fn(0.02, 0.0, 222)
        self.assertNotEqual(r1, r2)

    def test_mismo_seed_produce_mismo_resultado(self):
        r1 = self._fn(0.02, 0.15, 999)
        r2 = self._fn(0.02, 0.15, 999)
        self.assertEqual(r1, r2)


class TestProviderUtils(unittest.TestCase):
    def test_sha256_hex_consistente(self):
        from app.providers._utils import sha256_hex
        self.assertEqual(sha256_hex("hola"), sha256_hex("hola"))
        self.assertEqual(len(sha256_hex("test")), 64)

    def test_sha256_hex_diferente_para_inputs_distintos(self):
        from app.providers._utils import sha256_hex
        self.assertNotEqual(sha256_hex("a"), sha256_hex("b"))

    def test_stable_dumps_ordena_keys(self):
        from app.providers._utils import stable_dumps
        self.assertEqual(stable_dumps({"b": 2, "a": 1}), stable_dumps({"a": 1, "b": 2}))

    def test_stable_dumps_sin_espacios(self):
        from app.providers._utils import stable_dumps
        result = stable_dumps({"key": "value"})
        self.assertNotIn(" ", result)

    def test_sub_env_reemplaza_variable(self):
        from app.providers._utils import sub_env
        os.environ["_TEST_STUDIO_VAR"] = "VALOR"
        result = sub_env("inicio_${ENV:_TEST_STUDIO_VAR}_fin")
        self.assertEqual(result, "inicio_VALOR_fin")
        del os.environ["_TEST_STUDIO_VAR"]

    def test_sub_env_variable_inexistente_queda_vacia(self):
        from app.providers._utils import sub_env
        result = sub_env("${ENV:_VAR_QUE_NO_EXISTE_STUDIO_XYZ}")
        self.assertEqual(result, "")

    def test_apply_template_reemplaza_context(self):
        from app.providers._utils import apply_template
        result = apply_template("model={{model}}", {"model": "gpt-4"})
        self.assertEqual(result, "model=gpt-4")

    def test_apply_template_recursivo_en_dict(self):
        from app.providers._utils import apply_template
        result = apply_template({"key": "{{val}}"}, {"val": "test"})
        self.assertEqual(result, {"key": "test"})

    def test_apply_template_recursivo_en_lista(self):
        from app.providers._utils import apply_template
        result = apply_template(["{{a}}", "{{b}}"], {"a": "1", "b": "2"})
        self.assertEqual(result, ["1", "2"])

    def test_extract_path_anidado(self):
        from app.providers._utils import extract_path
        obj = {"data": [{"b64_json": "abc123"}]}
        self.assertEqual(extract_path(obj, "data.0.b64_json"), "abc123")

    def test_extract_path_key_inexistente_devuelve_none(self):
        from app.providers._utils import extract_path
        self.assertIsNone(extract_path({}, "data.0.b64_json"))

    def test_extract_path_indice_fuera_de_rango(self):
        from app.providers._utils import extract_path
        self.assertIsNone(extract_path({"data": []}, "data.5"))

    def test_extract_path_nivel_simple(self):
        from app.providers._utils import extract_path
        self.assertEqual(extract_path({"key": "val"}, "key"), "val")


class TestVideoPipelineLogic(unittest.TestCase):
    """Tests de lógica del pipeline sin ejecutar FFmpeg/API."""

    def test_abs_if_exists_retorna_vacio_si_no_existe(self):
        from app.video_utils import abs_if_exists
        result = abs_if_exists("/ruta/que/no/existe/abc123.mp3")
        self.assertEqual(result, "")

    def test_abs_if_exists_retorna_ruta_absoluta_si_existe(self):
        from app.video_utils import abs_if_exists
        result = abs_if_exists(__file__)
        self.assertTrue(os.path.isabs(result))
        self.assertTrue(os.path.isfile(result))

    def test_abs_if_exists_con_base_dir(self):
        from app.video_utils import abs_if_exists
        dirname = os.path.dirname(__file__)
        basename = os.path.basename(__file__)
        result = abs_if_exists(basename, base_dir=dirname)
        self.assertTrue(os.path.isfile(result))

    def test_ensure_dirs_crea_tres_directorios(self):
        import tempfile
        from app.video_utils import ensure_dirs
        with tempfile.TemporaryDirectory() as tmp:
            dirs = ensure_dirs(tmp)
            self.assertTrue(os.path.isdir(dirs["images_dir"]))
            self.assertTrue(os.path.isdir(dirs["audio_dir"]))
            self.assertTrue(os.path.isdir(dirs["render_dir"]))

    def test_ensure_dirs_devuelve_paths_correctos(self):
        import tempfile
        from app.video_utils import ensure_dirs
        with tempfile.TemporaryDirectory() as tmp:
            dirs = ensure_dirs(tmp)
            self.assertIn("render", dirs["render_dir"])
            self.assertIn("images", dirs["images_dir"])
            self.assertIn("audio", dirs["audio_dir"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
