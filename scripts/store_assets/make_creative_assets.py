#!/usr/bin/env python3
"""Builds the App Store creative assets (product page header, search results,
universal) from the iPad tips screenshot and a Duo stats screenshot.

Specs (App Store Connect "Creative assets specifications"):
  universal  5244x2950, PNG only, safe area 1402x962 at (1921, 660)
  header     3840x1646, safe area 1646x661 at (1097, 493)
  search     3840x2560 (3:2, 1920x1280 to 3840x2560), safe area 2168x1030 at (836, 765)
No alpha is allowed, so every file is saved as RGB.

Each asset fills its whole frame with app screens, as screenshots do. Only the
added text and icon must stay inside the safe area, which every placement
shows; placements that crop may cut the screens around it.
  - universal, header, search: the tips list, with the AFL round header
    replaced by an icon-and-headline bar centred in the safe area, so NRL
    cards sit above it and AFL cards below.
  - search-stats: the stats page panel, filling the frame's height. It adds
    no text of its own.
Each asset is also written with a "-guide" suffix showing the safe area
outline, for review only (do not upload those).

Run from the repository root (needs Pillow):
  python3 scripts/store_assets/make_creative_assets.py
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "screenshots" / "app-store" / "creative"
ICON = ROOT / "assets" / "icon" / "AppIcon.png"
FONT = ROOT / "assets" / "fonts" / "Roboto-Bold.ttf"

TIPS = ROOT / "screenshots" / "app-store" / "ipad-13" / "02-tips.png"
# The round 8 AFL header (left, top, right, bottom) in TIPS pixels, with the
# NRL round 8 cards above it and the AFL cards below.
AFL_HEADER = (237, 798, 1826, 988)
AFL_HEADER_RADIUS = 22
# Share of the frame's width the tips column fills.
TIPS_FILL = 0.94

STATS = ROOT / "screenshots" / "app-store" / "creative" / "sources" / "stats-duo-inner.webp"
# The stats panel, from its comp-name header to the NRL and AFL ladder cards.
STATS_BOX = (393, 434, 1431, 1330)
# Share of the frame's height the stats panel fills.
STATS_FILL = 0.94

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


def rounded(image: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, *image.size), radius, fill=255)
    out = Image.new("RGBA", image.size)
    out.paste(image, (0, 0), mask)
    return out


def frame(source: Image.Image, scale: float, src_point: tuple[float, float],
          canvas_point: tuple[float, float],
          size: tuple[int, int]) -> tuple[Image.Image, float, float]:
    """Crops and scales [source] to fill [size], so that [src_point] lands on
    [canvas_point]. Returns the frame and the source position of its top left."""
    left = src_point[0] - canvas_point[0] / scale
    top = src_point[1] - canvas_point[1] / scale
    box = (left, top, left + size[0] / scale, top + size[1] / scale)
    if box[0] < 0 or box[1] < 0 or box[2] > source.width or box[3] > source.height:
        raise ValueError(f"frame {box} falls outside the {source.size} source")
    return (source.resize(size, Image.LANCZOS, box=box).convert("RGBA"), left, top)


def save(name: str, size: tuple[int, int], safe: tuple[int, int, int, int],
         canvas: Image.Image) -> None:
    """Writes [canvas] as RGB, plus a review copy outlining the safe area."""
    sx, sy, sw, sh = safe
    final = canvas.convert("RGB")
    final.save(OUT / f"{name}-{size[0]}x{size[1]}.png", "PNG", optimize=True)

    guide = final.copy()
    ImageDraw.Draw(guide).rectangle((sx, sy, sx + sw, sy + sh),
                                    outline=(255, 0, 255), width=max(6, sw // 300))
    guide.save(OUT / "guides" / f"{name}-guide.png", "PNG", optimize=True)
    print(f"{name}: {size[0]}x{size[1]} written")


def build(name: str, size: tuple[int, int], safe: tuple[int, int, int, int],
          headline: str) -> None:
    """The tips list filling the frame, with the headline bar over the AFL
    round header at the centre of the safe area."""
    sx, sy, sw, sh = safe
    hl, ht, hr, hb = AFL_HEADER
    scale = size[0] * TIPS_FILL / (hr - hl)
    canvas, left, top = frame(Image.open(TIPS).convert("RGB"), scale,
                              ((hl + hr) / 2, (ht + hb) / 2),
                              (size[0] / 2, sy + sh / 2), size)

    bar_box = tuple(round(v) for v in ((hl - left) * scale, (ht - top) * scale,
                                        (hr - left) * scale, (hb - top) * scale))
    bar_h = bar_box[3] - bar_box[1]
    ImageDraw.Draw(canvas).rounded_rectangle(bar_box, round(AFL_HEADER_RADIUS * scale),
                                             fill=PANEL)

    # Icon and headline, centred, as large as fits 90% of the safe area's width.
    text, font, (text_w, text_h), icon_size = fit_headline(headline, sw * 0.9, bar_h)
    gap = round(icon_size * 0.3)
    content_x = round((size[0] - icon_size - gap - text_w) / 2)
    mid_y = (bar_box[1] + bar_box[3]) // 2
    icon = rounded(Image.open(ICON).convert("RGB").resize((icon_size, icon_size),
                                                          Image.LANCZOS),
                   round(icon_size * 0.22))
    canvas.alpha_composite(icon, (content_x, mid_y - icon_size // 2))
    draw = ImageDraw.Draw(canvas)
    spacing = round(font.size * 0.15)
    left, top, _, _ = draw.multiline_textbbox((0, 0), text, font=font, spacing=spacing)
    draw.multiline_text((content_x + icon_size + gap - left, mid_y - text_h / 2 - top),
                        text, font=font, fill=WHITE, spacing=spacing)
    save(name, size, safe, canvas)


def fit_headline(headline: str, max_w: float,
                 bar_h: int) -> tuple[str, ImageFont.FreeTypeFont, tuple[int, int], int]:
    """The largest headline that fits beside its icon in [max_w] and within the
    bar's height. It stays on one line unless splitting it over two, at the
    most even break, makes the text at least 15% larger. Returns the text, its
    font, its size and the icon size."""
    draw = ImageDraw.Draw(Image.new("RGB", (1, 1)))

    def largest(text: str) -> tuple[str, ImageFont.FreeTypeFont, tuple[int, int], int]:
        for font_size in range(round(bar_h * 0.46), 10, -2):
            font = ImageFont.truetype(str(FONT), font_size)
            left, top, right, bottom = draw.multiline_textbbox(
                (0, 0), text, font=font, spacing=round(font_size * 0.15))
            text_w, text_h = right - left, bottom - top
            icon_size = min(round(bar_h * 0.72), max(text_h, round(font_size * 1.6)))
            if text_h <= bar_h * 0.72 and icon_size * 1.3 + text_w <= max_w:
                return text, font, (text_w, text_h), icon_size
        raise ValueError(f"headline {text!r} does not fit")

    words = headline.split()
    probe = ImageFont.truetype(str(FONT), 100)
    split = min(range(1, len(words)), key=lambda i: max(
        draw.textlength(" ".join(words[:i]), font=probe),
        draw.textlength(" ".join(words[i:]), font=probe)))
    one_line = largest(headline)
    two_lines = largest(" ".join(words[:split]) + "\n" + " ".join(words[split:]))
    return two_lines if two_lines[1].size >= one_line[1].size * 1.15 else one_line


def build_stats(name: str, size: tuple[int, int],
                safe: tuple[int, int, int, int]) -> None:
    """The stats panel filling the frame's height, centred."""
    pl, pt, pr, pb = STATS_BOX
    scale = size[1] * STATS_FILL / (pb - pt)
    canvas, _, _ = frame(Image.open(STATS).convert("RGB"), scale,
                         ((pl + pr) / 2, (pt + pb) / 2),
                         (size[0] / 2, size[1] / 2), size)
    save(name, size, safe, canvas)


def main() -> None:
    (OUT / "guides").mkdir(parents=True, exist_ok=True)
    for name, spec in ASSETS.items():
        build(name, **spec)
    search = ASSETS["search"]
    build_stats("search-stats", search["size"], search["safe"])


if __name__ == "__main__":
    main()
