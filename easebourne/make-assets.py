#!/usr/bin/env python3
"""Generate the icon and link-preview images from brand.env.

Run on a laptop (needs Python 3 and Pillow: pip install pillow), then
commit the files in easebourne/assets/. The server never runs this.

Usage: python3 easebourne/make-assets.py [path/to/a/bold.ttf]
"""
import pathlib
import re
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE / "assets"
OUT.mkdir(exist_ok=True)


def read_env(path):
    values = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        m = re.match(r'^([A-Z_]+)="?(.*?)"?\s*$', line)
        if m and not line.lstrip().startswith("#"):
            values[m.group(1)] = m.group(2)
    return values


env = read_env(HERE / "brand.env")
NAME = env["BRAND_NAME"]
TAGLINE = env["BRAND_TAGLINE"]
SECTIONS = env["BRAND_SECTIONS"]
MONO = env["BRAND_MONOGRAM"]
COLOR = env["BRAND_COLOR"]

FONT_CANDIDATES = [
    sys.argv[1] if len(sys.argv) > 1 else "",
    "/usr/share/fonts/opentype/inter/Inter-Bold.otf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/Library/Fonts/Arial Bold.ttf",
    "C:/Windows/Fonts/arialbd.ttf",
]
REG_CANDIDATES = [
    "/usr/share/fonts/opentype/inter/Inter-Regular.otf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/Library/Fonts/Arial.ttf",
    "C:/Windows/Fonts/arial.ttf",
]


def font(candidates, size):
    for c in candidates:
        if c and pathlib.Path(c).exists():
            return ImageFont.truetype(c, size)
    return ImageFont.load_default(size)


def fit(draw, text, candidates, start, max_width):
    size = start
    while size > 12:
        f = font(candidates, size)
        if draw.textlength(text, font=f) <= max_width:
            return f
        size -= 2
    return font(candidates, size)


# Browser tab icon (SVG, scales cleanly).
(OUT / "icon.svg").write_text(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64">\n'
    f'  <rect width="64" height="64" rx="14" fill="{COLOR}"></rect>\n'
    '  <text x="32" y="45" text-anchor="middle" font-family="Inter, ui-sans-serif, '
    'system-ui, -apple-system, sans-serif" font-weight="700" font-size="38" '
    f'fill="#ffffff">{MONO}</text>\n'
    "</svg>\n",
    encoding="utf-8",
)

# Home-screen icon for iPhones (180x180 PNG, iOS rounds the corners itself).
icon = Image.new("RGB", (180, 180), COLOR)
d = ImageDraw.Draw(icon)
f = font(FONT_CANDIDATES, 112)
d.text((90, 92), MONO, font=f, fill="white", anchor="mm")
icon.save(OUT / "apple-icon.png")

# Link preview image (1200x630) shown when a sign-up link is shared.
og = Image.new("RGB", (1200, 630), "white")
d = ImageDraw.Draw(og)
d.rectangle([0, 0, 1200, 24], fill=COLOR)
d.rectangle([0, 606, 1200, 630], fill=COLOR)
d.rounded_rectangle([80, 120, 200, 240], radius=26, fill=COLOR)
d.text((140, 182), MONO, font=font(FONT_CANDIDATES, 84), fill="white", anchor="mm")
title_font = fit(d, NAME, FONT_CANDIDATES, 76, 1040)
d.text((80, 300), NAME, font=title_font, fill="#0b1220", anchor="ls")
d.text((80, 380), TAGLINE, font=fit(d, TAGLINE, REG_CANDIDATES, 48, 1040),
       fill="#3b4250", anchor="ls")
d.text((80, 520), SECTIONS, font=fit(d, SECTIONS, REG_CANDIDATES, 34, 1040),
       fill=COLOR, anchor="ls")
og.save(OUT / "opengraph-image.png")
og.save(OUT / "twitter-image.png")

alt = f"{NAME}: {TAGLINE.lower()}."
(OUT / "opengraph-image.alt.txt").write_text(alt + "\n", encoding="utf-8")
(OUT / "twitter-image.alt.txt").write_text(alt + "\n", encoding="utf-8")

print("Wrote", ", ".join(sorted(p.name for p in OUT.iterdir())))
