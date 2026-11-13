"""CPU-only upload validation regressions; no research code or GPU required."""
import base64
import io
import unittest
from types import SimpleNamespace
from unittest import mock

import gpu_worker
from PIL import Image
import numpy as np


def png(image):
    buf = io.BytesIO()
    image.save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode("ascii")


class PhotoValidationTests(unittest.TestCase):
    def setUp(self):
        self.image = png(Image.new("RGB", (256, 256), "white"))
        mask = Image.new("L", (256, 256))
        mask.paste(255, (64, 64, 192, 192))
        self.mask = png(mask)
        patch = mock.patch.object(gpu_worker, "load_research",
                                  return_value=SimpleNamespace(Image=Image, np=np))
        self.research = patch.start()
        self.addCleanup(patch.stop)

    def test_untyped_change_rejected_before_loading_research(self):
        for value in ([], {}, None, True, 12):
            with self.subTest(value=value):
                with self.assertRaises(gpu_worker.GpuRequestUnsupportedError):
                    gpu_worker.run_photo_pipeline(value, self.image, self.mask)
        self.research.assert_not_called()

    def test_dimension_limits_before_pixel_decode(self):
        for size in ((255, 256), (4097, 256), (256, 4097)):
            fake = mock.Mock(size=size)
            with self.subTest(size=size), mock.patch.object(Image, "open", return_value=fake):
                with self.assertRaisesRegex(gpu_worker.PhotoRequestError, "between 256 and 4096"):
                    gpu_worker.run_photo_pipeline("brown_rice", self.image, self.mask)
                fake.load.assert_not_called()

    def test_mismatched_mask_rejected_before_pixel_decode(self):
        photo, mask = mock.Mock(size=(256, 256)), mock.Mock(size=(4096, 4096))
        with mock.patch.object(Image, "open", side_effect=[photo, mask]):
            with self.assertRaisesRegex(gpu_worker.PhotoRequestError, "same size"):
                gpu_worker.run_photo_pipeline("brown_rice", self.image, self.mask)
        photo.load.assert_not_called()
        mask.load.assert_not_called()

    def test_valid_upload_is_dispatched_without_retention_and_temp_is_cleaned(self):
        from pathlib import Path
        paths = []
        def dispatch(*args, **kwargs):
            paths.append(kwargs["original_path"])
            self.assertTrue(paths[-1].exists())
            self.assertFalse(kwargs["retain"])
            self.assertEqual(kwargs["mask"].shape, (1024, 1024))
            return {"test": "artifact"}
        with mock.patch.object(gpu_worker, "_run_sgedit", side_effect=dispatch):
            result = gpu_worker.run_photo_pipeline("brown_rice", self.image, self.mask)
        self.assertEqual(result, {"test": "artifact"})
        self.assertFalse(paths[0].exists())

    def test_failure_also_cleans_uploaded_photo(self):
        paths = []
        def fail(*args, **kwargs):
            paths.append(kwargs["original_path"])
            raise gpu_worker.GpuPipelineUnreadyError("fake unavailable model")
        with mock.patch.object(gpu_worker, "_run_sgedit", side_effect=fail):
            with self.assertRaises(gpu_worker.GpuPipelineUnreadyError):
                gpu_worker.run_photo_pipeline("brown_rice", self.image, self.mask)
        self.assertFalse(paths[0].exists())


if __name__ == "__main__":
    unittest.main()
