#!/usr/bin/env python3
"""Builds the App Store creative assets (product page header, search results,
universal) from the app's own art and the iPad tips screenshot.

Specs (App Store Connect "Creative assets specifications"):
  universal  5244x2950, PNG only, safe area 1402x962 at (1921, 660)
  header     3840x1646, safe area 1646x661 at (1097, 493)
  search     3840x2560 (3:2, 1920x1280 to 3840x2560), safe area 2168x1030 at (836, 765)
No alpha is allowed, so every file is saved as RGB.

Key art (icon, headline, cards) stays inside the safe area; only the blurred
grass background fills the rest. Each asset is also written with a "-guide"
suffix showing the safe area outline, for review only (do not upload those).

Run from the repository root (needs Pillow):
  python3 scripts/store_assets/make_creative_assets.py
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "screenshots" / "app-store" / "creative"
BACKGROUND = ROOT / "assets" / "grass_background_blurred.webp"
ICON = ROOT / "assets" / "icon" / "AppIcon.png"
FONT = ROOT / "assets" / "fonts" / "Roboto-Bold.ttf"
TIPS = ROOT / "screenshots" / "app-store" / "ipad-13" / "02-tips.png"
# The four NRL round 8 cards (two "Game today" ribbons, two picked tips).
CARDS_BOX = (230, 270, 1830, 790)

PANEL = (52, 64, 56)  # the app's dark round-header green
WHITE = (255, 255, 255)

ASSETS = {
    "universal": dict(size=(5244, 2950), safe=(1921, 660, 1402, 962),
                      headline="Footy tipping for NRL & AFL"),
    "header": dict(size=(3840, 1646), safe=(1097, 493, 1646, 661),
                   headline="Tip every NRL & AFL game"),
    "search": dict(size=(3840, 2560), safe=(836, 765, 2168, 1030),
                   headline="NRL + AFL footy tipping"),
}


def cover(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    """Scales and centre-crops [image] to fill [size]."""
    scale = max(size[0] / image.width, size[1] / image.height)
    scaled = image.resize((round(image.width * scale), round(image.height * scale)),
                          Image.LANCZOS)
    left = (scaled.width - size[0]) // 2
    top = (scaled.height - size[1]) // 2
    return scaled.crop((left, top, left + size[0], top + size[1]))


def rounded(image: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, *image.size), radius, fill=255)
    out = Image.new("RGBA", image.size)
    out.paste(image, (0, 0), mask)
    return out


def shadow_paste(canvas: Image.Image, art: Image.Image, xy: tuple[int, int],
                 blur: int) -> None:
    """Pastes [art] (RGBA) at [xy] over a soft drop shadow."""
    pad = blur * 3
    shadow = Image.new("RGBA", (art.width + pad * 2, art.height + pad * 2))
    alpha = art.getchannel("A").point(lambda a: a * 0.45)
    shadow.paste((0, 0, 0, 255), (pad, pad), alpha)
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(shadow, (xy[0] - pad, xy[1] - pad + blur // 2))
    canvas.alpha_composite(art, xy)


def build(name: str, size: tuple[int, int], safe: tuple[int, int, int, int],
          headline: str) -> None:
    sx, sy, sw, sh = safe
    canvas = cover(Image.open(BACKGROUND).convert("RGB"), size).convert("RGBA")
    # Darken slightly towards the bottom so the key art stands out.
    shade = Image.new("L", (1, size[1]))
    for y in range(size[1]):
        shade.putpixel((0, y), round(70 * y / size[1]))
    canvas.alpha_composite(Image.merge("RGBA", (
        *(Image.new("L", size, 0),) * 3, shade.resize(size))))

    # Layout inside the safe area: headline bar on top, cards below.
    gap = round(sh * 0.05)
    bar_h = round(sh * 0.21)
    cards = Image.open(TIPS).convert("RGB").crop(CARDS_BOX)
    cards_w = sw
    cards_h = round(cards.height * cards_w / cards.width)
    max_cards_h = sh - bar_h - gap
    if cards_h > max_cards_h:
        cards_h = max_cards_h
        cards_w = round(cards.width * cards_h / cards.height)
    block_h = bar_h + gap + cards_h
    top = sy + (sh - block_h) // 2

    # Headline bar: icon + text on the app's dark panel colour.
    icon_size = round(bar_h * 0.72)
    pad_x = round(bar_h * 0.28)
    # Largest font, up to 46% of the bar height, whose line fits the safe width.
    font_size = round(bar_h * 0.46)
    while True:
        font = ImageFont.truetype(str(FONT), font_size)
        text_w = ImageDraw.Draw(canvas).textlength(headline, font=font)
        if pad_x * 3 + icon_size + text_w <= sw:
            break
        font_size -= 2
    bar_w = round(pad_x * 3 + icon_size + text_w)
    bar = Image.new("RGBA", (bar_w, bar_h), (*PANEL, 235))
    bar = rounded(bar, round(bar_h * 0.28))
    icon = rounded(Image.open(ICON).convert("RGB").resize((icon_size, icon_size),
                                                          Image.LANCZOS),
                   round(icon_size * 0.22))
    bar.alpha_composite(icon, (pad_x, (bar_h - icon_size) // 2))
    ImageDraw.Draw(bar).text((pad_x * 2 + icon_size, bar_h // 2), headline,
                             font=font, fill=WHITE, anchor="lm")
    shadow_paste(canvas, bar, (sx + (sw - bar_w) // 2, top), round(bar_h * 0.12))

    card_art = rounded(cards.resize((cards_w, cards_h), Image.LANCZOS),
                       round(cards_h * 0.04))
    shadow_paste(canvas, card_art, (sx + (sw - cards_w) // 2, top + bar_h + gap),
                 round(cards_h * 0.03))

    final = canvas.convert("RGB")
    final.save(OUT / f"{name}-{size[0]}x{size[1]}.png", "PNG", optimize=True)

    guide = final.copy()
    ImageDraw.Draw(guide).rectangle((sx, sy, sx + sw, sy + sh),
                                    outline=(255, 0, 255), width=max(6, sw // 300))
    guide.save(OUT / "guides" / f"{name}-guide.png", "PNG", optimize=True)
    print(f"{name}: {size[0]}x{size[1]} written")


def main() -> None:
    (OUT / "guides").mkdir(parents=True, exist_ok=True)
    for name, spec in ASSETS.items():
        build(name, **spec)


if __name__ == "__main__":
    main()
