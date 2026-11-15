"""Populate ignored, licensed catalogue assets without adding photos to Git.

Run from any directory: python scripts/fetch_reference_photos.py
Use --source-dir PATH for a verified prior build/cache, or --check for validation.
"""
import argparse
import hashlib
import pathlib
import re
import tempfile
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
DEST = ROOT / "mobile/assets/meals"
HASHES = {
    "chicken_rice.jpg": "6b5c3496b82b97f12933c107c851860fd123b86112d46304ee2439b88f729a02",
    "fish_soup.jpg": "3e8f17a130bdfcda8bc7447a248b529f290207dfa134ff132027e5a6b23c3a03",
    "tofu_rice.jpg": "ff9f69e43ffe2de11794b6870e572c31ae94d1b88c509d6ef40d74dcafd50948",
}


def verified(data, expected):
    return data.startswith(b"\xff\xd8\xff") and hashlib.sha256(data).hexdigest() == expected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=pathlib.Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    notices = (DEST / "ATTRIBUTION.md").read_text(encoding="utf-8")
    urls = dict(re.findall(r"## (\w+\.jpg)\s+.*?- Thumbnail: (https://\S+)", notices, re.S))
    failures = []
    for name, expected in HASHES.items():
        target = DEST / name
        if target.exists():
            if verified(target.read_bytes(), expected):
                print(f"Verified {name}")
                continue
            failures.append(f"{name}: existing file does not match; left untouched")
            continue
        if args.check:
            failures.append(f"{name}: missing; run acquisition first")
            continue
        try:
            if args.source_dir:
                data = (args.source_dir / name).read_bytes()
            else:
                request = urllib.request.Request(urls[name], headers={"User-Agent": "SeniorMealPreview-reference-assets/1.0"})
                with urllib.request.urlopen(request, timeout=30) as response:
                    data = response.read(5 * 1024 * 1024 + 1)
            if not verified(data, expected):
                raise ValueError("download/cache hash or JPEG header mismatch; not installed. Upstream may have changed; review attribution and image before updating pins")
            with tempfile.NamedTemporaryFile(dir=DEST, delete=False) as tmp:
                tmp.write(data)
                temp_path = pathlib.Path(tmp.name)
            try:
                # Do not overwrite any concurrent/manual asset.
                with target.open("xb") as output:
                    output.write(temp_path.read_bytes())
            finally:
                temp_path.unlink()
            print(f"Installed verified {name}")
        except Exception as error:
            failures.append(f"{name}: {error}")
    if failures:
        raise SystemExit("\n".join(failures))
    print("All three catalogue references verified. Preserve ATTRIBUTION.md and license notices in distributions.")


if __name__ == "__main__":
    main()

