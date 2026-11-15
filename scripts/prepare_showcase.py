"""Build the offline walkthrough from a pinned public photo and a recorded Spark run."""
import argparse
import base64
import json
import hashlib
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageOps

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "gpu-worker"))
from app_methods import recolour_rice
from fetch_reference_photos import DEST, HASHES

# Hand-traced rice outline on a 450 px-wide rendering of Misaochan's photograph.
OUTLINE = [(247,184),(251,168),(255,158),(261,146),(270,138),(284,132),
           (301,129),(314,130),(326,136),(335,144),(342,154),(347,168),
           (350,182),(349,198),(345,211),(337,218),(327,222),(311,225),
           (297,224),(283,220),(269,214),(257,206),(249,197)]
SPARK_SHA = "5c2a04666085be9195f2399f8817dacdd5dddd996d2a0c4af9d2f75a625b462d"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("comparison", type=Path, help="Archived 1536 × 550 tofu contact sheet")
    parser.add_argument("--html", type=Path, help="Write a self-contained browser walkthrough")
    args = parser.parse_args()
    photo = DEST / "chicken_rice.jpg"
    for path, expected in [(photo, HASHES[photo.name]), (args.comparison, SPARK_SHA)]:
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            parser.error(f"Unexpected source bytes in {path}")
    with Image.open(photo) as original:
        source = ImageOps.fit(original.convert("RGB"), (1024, 1024), method=Image.Resampling.LANCZOS)
        mask = Image.new("L", original.size)
        scale = original.width / 450
        ImageDraw.Draw(mask).polygon([(round(x * scale), round(y * scale)) for x, y in OUTLINE], fill=255)
    mask = ImageOps.fit(mask, source.size, method=Image.Resampling.NEAREST)
    edited = recolour_rice(source, np.asarray(mask) > 0)
    if not np.any(np.asarray(source) != np.asarray(edited)):
        raise RuntimeError("The edit changed no pixels")
    overlay = Image.composite(Image.blend(source, Image.new("RGB", source.size, "#19bba5"), .56), source, mask)
    for name, image in [("original", source), ("region", overlay), ("edited", edited)]:
        image.resize((720, 720), Image.Resampling.LANCZOS).save(DEST / f"sample_{name}.jpg", quality=92)
    # The original contact sheet uses three 512 px columns and a 38 px heading.
    with Image.open(args.comparison) as sheet:
        for i in range(3):
            sheet.crop((512*i, 38, 512*(i+1), 550)).save(DEST / f"sample_tofu_{i}.jpg", quality=94)

    if args.html:
        photos = {}
        for name in ("original", "region", "edited", "tofu_0", "tofu_1", "tofu_2"):
            data = (DEST / f"sample_{name}.jpg").read_bytes()
            photos[name] = "data:image/jpeg;base64," + base64.b64encode(data).decode("ascii")
        template = Path(__file__).with_name("showcase.html").read_text()
        args.html.write_text(template.replace("PHOTO_DATA", json.dumps(photos)), encoding="utf-8")


if __name__ == "__main__":
    main()
