"""Model-free tests for the app-only photo methods (no GPU, no weights)."""

import os
import unittest
from unittest import mock

try:
    import numpy as np
    from PIL import Image

    import app_methods
except Exception as exc:  # numpy, scipy or Pillow missing on this interpreter
    app_methods = None

import gpu_worker


@unittest.skipIf(app_methods is None, "image libraries unavailable")
class RecolourTest(unittest.TestCase):
    def _meal(self):
        rng = np.random.default_rng(7)
        rgb = np.full((256, 256, 3), (120, 90, 60), "uint8")  # table
        rice = rng.integers(215, 250, (96, 96, 1)).repeat(3, 2).astype("uint8")
        rgb[80:176, 80:176] = rice
        rgb[100:110, 100:110] = (20, 60, 20)  # a dark leaf on the rice
        mask = np.zeros((256, 256), bool)
        mask[80:176, 80:176] = True
        return Image.fromarray(rgb), mask

    def test_lab_round_trip(self):
        rgb = np.random.default_rng(1).integers(0, 256, (16, 16, 3)).astype("uint8")
        back = app_methods.lab_to_rgb(app_methods.rgb_to_lab(rgb))
        self.assertLessEqual(int(np.abs(back.astype(int) - rgb).max()), 1)

    def test_rice_turns_brown_and_the_rest_is_untouched(self):
        image, mask = self._meal()
        before = np.asarray(image)
        after = np.asarray(app_methods.recolour_rice(image, mask))
        self.assertEqual(after.shape, before.shape)
        far = np.ones(mask.shape, bool)
        far[60:196, 60:196] = False
        self.assertTrue((after[far] == before[far]).all())
        lab = app_methods.rgb_to_lab(after[120:170, 120:170]).reshape(-1, 3).mean(0)
        for got, want in zip(lab, app_methods.BROWN_RICE_LAB):
            self.assertAlmostEqual(got, want, delta=4)
        # Grain contrast survives: the rice is not flattened to one colour.
        self.assertGreater(after[120:170, 120:170, 0].std(), 3)
        # The dark leaf is left alone.
        self.assertLess(int(np.abs(after[103:107, 103:107].astype(int) - (20, 60, 20)).max()), 12)


class PhotoMethodSwitchTest(unittest.TestCase):
    def test_default_is_the_research_policy(self):
        with mock.patch.dict(os.environ, {}, clear=False):
            os.environ.pop("WORKER_PHOTO_METHOD", None)
            self.assertEqual(gpu_worker.photo_method(), "research")

    def test_app_methods_are_opt_in(self):
        with mock.patch.dict(os.environ, {"WORKER_PHOTO_METHOD": " App "}):
            self.assertEqual(gpu_worker.photo_method(), "app")
        with mock.patch.dict(os.environ, {"WORKER_PHOTO_METHOD": "other"}):
            self.assertEqual(gpu_worker.photo_method(), "research")

    def test_labels_pass_the_gateway_provenance_rule(self):
        for label in (gpu_worker.PHOTO_DISCLOSURE, gpu_worker.RECOLOUR_DISCLOSURE):
            self.assertIn("not", label.lower())


if __name__ == "__main__":
    unittest.main()
