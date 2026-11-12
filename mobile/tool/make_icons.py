"""Generate the "A little change" launcher icons (Android, adaptive, iOS, web).

Design: a cream plate on the app's ink-green background, with one small leaf
on the plate — "a little change" to a meal. Colors come from DESIGN.md tokens.
Run from mobile/:  python3 tool/make_icons.py
"""
from pathlib import Path
from PIL import Image, ImageDraw

INK = (22, 61, 52, 255)        # #163D34
CREAM = (248, 246, 239, 255)   # #F8F6EF
RIM = (215, 221, 209, 255)     # #D7DDD1
LEAF = (98, 148, 96, 255)      # fresh green, 5.0:1 on cream
VEIN = (234, 240, 226, 255)    # #EAF0E2
SS = 4                         # supersampling factor


def art(size, scale=1.0, background=True, rounded=False):
    """Draw at size*SS, content scaled about the centre by `scale`."""
    n = size * SS
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if background:
        if rounded:
            d.rounded_rectangle([0, 0, n - 1, n - 1], radius=int(n * 0.22), fill=INK)
        else:
            d.rectangle([0, 0, n, n], fill=INK)
    c = n / 2
    s = lambda f: f * n * scale  # noqa: E731

    def circle(r, fill):
        d.ellipse([c - s(r), c - s(r), c + s(r), c + s(r)], fill=fill)

    circle(0.36, CREAM)   # plate
    circle(0.30, RIM)     # plate well
    circle(0.285, CREAM)
    # Leaf: two intersecting circles' lens, rotated 45 degrees.
    leaf = Image.new("L", (n, n), 0)
    w, off = s(0.17), s(0.09)
    a = Image.new("L", (n, n), 0)
    b = Image.new("L", (n, n), 0)
    ImageDraw.Draw(a).ellipse([c - w - off, c - w, c + w - off, c + w], fill=255)
    ImageDraw.Draw(b).ellipse([c - w + off, c - w, c + w + off, c + w], fill=255)
    from PIL import ImageChops
    leaf = ImageChops.multiply(a, b)
    leaf = leaf.rotate(-45, resample=Image.BICUBIC, center=(c, c))
    im.paste(LEAF, (0, 0), leaf)
    # Central vein along the leaf's long axis.
    v = s(0.12)
    d.line([(c - v, c + v), (c + v * 0.85, c - v * 0.85)], fill=VEIN, width=max(1, int(s(0.016))))
    # Stem.
    d.line([(c - v, c + v), (c - v * 1.35, c + v * 1.35)], fill=LEAF, width=max(1, int(s(0.022))))
    return im.resize((size, size), Image.LANCZOS)


def save(im, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path, optimize=True)


def main():
    root = Path(__file__).resolve().parent.parent
    res = root / "android/app/src/main/res"
    for dpi, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        save(art(px, rounded=True), res / f"mipmap-{dpi}/ic_launcher.png")
        # Adaptive foreground: 108dp canvas, art inside the 66dp safe zone.
        save(art(px * 108 // 48, scale=0.66 / 0.72 * 0.9, background=False),
             res / f"mipmap-{dpi}/ic_launcher_foreground.png")
    (res / "mipmap-anydpi-v26").mkdir(exist_ok=True)
    (res / "mipmap-anydpi-v26/ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '</adaptive-icon>\n')
    (res / "values/ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        '    <color name="ic_launcher_background">#163D34</color>\n</resources>\n')

    ios = root / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for p in ios.glob("Icon-App-*.png"):
        px = Image.open(p).size[0]
        save(art(px).convert("RGB"), p)  # iOS: square, opaque, no alpha

    web = root / "web"
    for px in (192, 512):
        save(art(px, rounded=True), web / f"icons/Icon-{px}.png")
        save(art(px, scale=0.8), web / f"icons/Icon-maskable-{px}.png")
    save(art(32, rounded=True), web / "favicon.png")


if __name__ == "__main__":
    main()
