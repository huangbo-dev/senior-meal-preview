import contextlib
import hashlib
import importlib.util
import io
import pathlib
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("fetch", pathlib.Path(__file__).with_name("fetch_reference_photos.py"))
fetch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fetch)


class AssetTests(unittest.TestCase):
    def test_cache_install_check_and_refuse_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            dest, source = root / "assets", root / "cache"
            dest.mkdir()
            source.mkdir()
            data = b"\xff\xd8\xfffixture"
            (source / "test.jpg").write_bytes(data)
            (dest / "ATTRIBUTION.md").write_text("## test.jpg\n- Thumbnail: https://example.invalid/test.jpg\n")
            with patch.object(fetch, "DEST", dest), patch.object(fetch, "HASHES", {"test.jpg": hashlib.sha256(data).hexdigest()}), contextlib.redirect_stdout(io.StringIO()):
                with patch.object(sys, "argv", ["fetch", "--check"]):
                    with self.assertRaises(SystemExit):
                        fetch.main()
                with patch.object(sys, "argv", ["fetch", "--source-dir", str(source)]):
                    fetch.main()
                self.assertEqual((dest / "test.jpg").read_bytes(), data)
                with patch.object(sys, "argv", ["fetch", "--check"]):
                    fetch.main()
                (dest / "test.jpg").write_bytes(b"preserve me")
                with patch.object(sys, "argv", ["fetch", "--source-dir", str(source)]):
                    with self.assertRaises(SystemExit):
                        fetch.main()
                self.assertEqual((dest / "test.jpg").read_bytes(), b"preserve me")

    def test_invalid_data(self):
        self.assertFalse(fetch.verified(b"not a jpeg", hashlib.sha256(b"not a jpeg").hexdigest()))
        self.assertFalse(fetch.verified(b"\xff\xd8\xfffixture", "0" * 64))


if __name__ == "__main__":
    unittest.main()
