"""Builds the Google Play app icon and featured graphic.

Run via tool/store_listing/generate.sh (needs Pillow and FLUTTER_ROOT for the
Roboto fonts). Reads the app icon and the phone screenshots, writes to
docs/play-store/.
"""

import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs" / "play-store"
SOURCE_ICON = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png"
FONTS = Path(os.environ["FLUTTER_ROOT"]) / "bin/cache/artifacts/material_fonts"

BLUE = (10, 92, 235)
TEAL = (22, 190, 160)


def app_icon() -> None:
    """512x512 opaque PNG: the transparent launcher art on white."""
    art = Image.open(SOURCE_ICON).convert("RGBA")
    canvas = Image.new("RGBA", art.size, (255, 255, 255, 255))
    canvas.alpha_composite(art)
    canvas.convert("RGB").resize((512, 512), Image.LANCZOS).save(
        OUT / "app-icon-512.png", optimize=True
    )


def _gradient(size: tuple[int, int]) -> Image.Image:
    w, h = size
    img = Image.new("RGB", size)
    px = img.load()
    for x in range(w):
        for y in range(h):
            t = min(1.0, max(0.0, (x / w) * 0.8 + (y / h) * 0.2))
            px[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(BLUE, TEAL))
    return img


def _rounded(img: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, *img.size), radius, fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def featured_graphic() -> None:
    """1024x500: brand gradient, icon, name, tagline and a phone screenshot."""
    w, h = 1024, 500
    canvas = _gradient((w, h)).convert("RGBA")
    draw = ImageDraw.Draw(canvas)

    # Icon tile.
    tile = Image.new("RGBA", (132, 132), (255, 255, 255, 255))
    art = Image.open(SOURCE_ICON).convert("RGBA").resize((132, 132), Image.LANCZOS)
    tile.alpha_composite(art)
    canvas.alpha_composite(_rounded(tile, 30), (64, 92))

    bold = ImageFont.truetype(str(FONTS / "Roboto-Bold.ttf"), 64)
    regular = ImageFont.truetype(str(FONTS / "Roboto-Regular.ttf"), 30)
    draw.text((64, 254), "My Little CRM", font=bold, fill="white")
    for i, line in enumerate(
        ["Who you spoke with, what was said,", "and what they promised."]
    ):
        draw.text((66, 342 + i * 40), line, font=regular, fill=(235, 245, 255))

    # Phone screenshot, cropped by the bottom edge.
    shot = Image.open(OUT / "screenshots/phone/01-interactions.png").convert("RGB")
    phone_w = 300
    phone = shot.resize((phone_w, round(shot.height * phone_w / shot.width)), Image.LANCZOS)
    frame_pad = 10
    frame = Image.new(
        "RGBA", (phone.width + frame_pad * 2, phone.height + frame_pad * 2), (20, 24, 32, 255)
    )
    frame.alpha_composite(_rounded(phone, 26), (frame_pad, frame_pad))
    frame = _rounded(frame, 36)
    x, y = w - frame.width - 72, 44
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (x + 6, y + 14, x + frame.width + 6, y + frame.height + 14), 36, fill=(0, 0, 0, 90)
    )
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(14)))
    canvas.alpha_composite(frame, (x, y))

    canvas.convert("RGB").save(OUT / "featured-graphic-1024x500.png", optimize=True)


def flatten_screenshots() -> None:
    """Play wants screenshots without an alpha channel (24-bit PNG)."""
    for path in sorted((OUT / "screenshots").glob("*/*.png")):
        Image.open(path).convert("RGB").save(path, optimize=True)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    flatten_screenshots()
    app_icon()
    featured_graphic()
