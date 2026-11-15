"""Model-free tests for finding the rice automatically (no GPU, no weights)."""

import base64
import io
import os
import unittest
from types import SimpleNamespace
from unittest import mock

import numpy as np
from PIL import Image

import auto_mask
import gpu_worker


def png(image):
    buf = io.BytesIO()
    image.save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode("ascii")


def rice_square():
    rice = np.zeros((1024, 1024), bool)
    rice[300:700, 200:800] = True
    return rice


class BroccoliPatchTests(unittest.TestCase):
    def test_patch_is_a_small_area_inside_the_rice(self):
        rice = rice_square()
        patch = auto_mask.broccoli_patch(rice)
        self.assertTrue(patch.any())
        self.assertFalse((patch & ~rice).any())
        self.assertLess(patch.sum(), 0.5 * rice.sum())

    def test_patch_never_exceeds_the_size_cap_on_a_plate_full_of_rice(self):
        rice = np.ones((1024, 1024), bool)
        ys, xs = np.nonzero(auto_mask.broccoli_patch(rice))
        self.assertLessEqual(xs.max() - xs.min(), 0.25 * 1024)
        self.assertLessEqual(ys.max() - ys.min(), 0.25 * 1024)


class AutoMaskPipelineTests(unittest.TestCase):
    def setUp(self):
        self.image = png(Image.new("RGB", (256, 256), "white"))
        for patch in (
            mock.patch.object(
                gpu_worker, "load_research", return_value=SimpleNamespace(Image=Image, np=np)
            ),
            mock.patch.dict(os.environ, {"WORKER_PHOTO_METHOD": "app"}),
        ):
            patch.start()
            self.addCleanup(patch.stop)

    def run_with_rice(self, change_ids):
        calls = []

        def dispatch(research, image, masks, original, ids, tmp, painted):
            calls.append((masks, ids, painted))
            return {"test": "artifact"}

        with (
            mock.patch.object(auto_mask, "find_rice", return_value=(rice_square(), {})),
            mock.patch.object(gpu_worker, "_run_app_method", side_effect=dispatch),
        ):
            self.assertEqual(
                gpu_worker.run_photo_pipeline(change_ids, self.image), {"test": "artifact"}
            )
        return calls[0]

    def test_brown_rice_uses_all_the_rice(self):
        masks, ids, painted = self.run_with_rice(["brown_rice"])
        self.assertEqual(ids, ["brown_rice"])
        self.assertFalse(painted)
        self.assertTrue((masks["brown_rice"] == rice_square()).all())

    def test_two_changes_add_broccoli_on_a_patch_then_recolour_the_rice(self):
        masks, ids, _ = self.run_with_rice(["brown_rice", "extra_vegetables"])
        self.assertEqual(ids, ["extra_vegetables", "brown_rice"])
        self.assertLess(masks["extra_vegetables"].sum(), masks["brown_rice"].sum())

    def test_no_rice_is_its_own_error_not_a_fake_edit(self):
        with mock.patch.object(auto_mask, "find_rice", side_effect=auto_mask.RiceNotFound("x")):
            with self.assertRaises(gpu_worker.RiceNotFoundError):
                gpu_worker.run_photo_pipeline(["brown_rice"], self.image)

    def test_painted_mask_applies_to_one_change_only(self):
        with self.assertRaises(gpu_worker.GpuRequestUnsupportedError):
            gpu_worker.run_photo_pipeline(["brown_rice", "extra_vegetables"], self.image, self.image)

    def test_repeated_change_is_rejected(self):
        with self.assertRaises(gpu_worker.GpuRequestUnsupportedError):
            gpu_worker.run_photo_pipeline(["brown_rice", "brown_rice"], self.image)

    def test_research_method_still_needs_a_painted_mask(self):
        with mock.patch.dict(os.environ, {"WORKER_PHOTO_METHOD": "research"}):
            with self.assertRaises(gpu_worker.GpuRequestUnsupportedError):
                gpu_worker.run_photo_pipeline(["brown_rice"], self.image)

    def test_every_label_passes_the_gateway_provenance_rule(self):
        for label in (
            gpu_worker.PHOTO_DISCLOSURE,
            gpu_worker.RECOLOUR_DISCLOSURE,
            gpu_worker.COMBINED_DISCLOSURE,
        ):
            self.assertIn("not", label.lower())


if __name__ == "__main__":
    unittest.main()
