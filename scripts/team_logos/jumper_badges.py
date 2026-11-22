"""Writes original jumper-style badges (club colours and stripe pattern only) for the
teams whose old logos were auto-traced, plus a neutral badge for the finals placeholder
teams. The files are then optimised with `npm run optimise:logos`.

Usage: python3 -I scripts/team_logos/jumper_badges.py team_logos"""
import sys
from pathlib import Path

out = Path(sys.argv[1])


def svg(size, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}">'
            f'{body}</svg>\n')


def rect(x, y, w, h, fill):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{fill}"/>'


def poly(points, fill):
    pts = ' '.join(f'{x},{y}' for x, y in points)
    return f'<polygon points="{pts}" fill="{fill}"/>'


def bg(size, fill):
    return rect(0, 0, size, size, fill)


def hoops(colours):
    """Equal horizontal bands, top to bottom, on a 100 square."""
    # Each band runs to the bottom and the next one covers it, so no seams show.
    h = 100 / len(colours)
    body = ''
    for i, c in enumerate(colours):
        y = round(i * h, 2)
        body += rect(0, y, 100, round(100 - y, 2), c)
    return svg(100, body)


def stripes(base, stripe, count):
    """Vertical stripes on a 10-unit grid: base, stripe, base, ... (count is odd)."""
    size = count * 10
    body = bg(size, base)
    for i in range(1, count, 2):
        body += rect(i * 10, 0, 10, size, stripe)
    return svg(size, body)


def panels(colours):
    """Equal vertical panels, left to right, on a 90 square."""
    w = 90 // len(colours)
    body = ''
    for i, c in enumerate(colours):
        body += rect(i * w, 0, 90 - i * w, 90, c)
    return svg(90, body)


def v_band(top, bottom, fill):
    """A chevron band whose apex runs from y=top to y=bottom at x=50, arms at 45 degrees.
    Drawn as one polygon kept inside the 100 square."""
    def edge(a):
        # The V line y = a - |x - 50|, clipped to the square, from left to right.
        if a <= 50:
            return [(50 - a, 0), (50, a), (50 + a, 0)]
        return [(0, a - 50), (50, a), (100, a - 50)]

    upper, lower = edge(top), edge(bottom)
    corners_right, corners_left = [], []
    if top <= 50 < bottom:
        # The upper line leaves through the top edge and the lower through the sides,
        # so the band takes in the top corners.
        corners_right, corners_left = [(100, 0)], [(0, 0)]
    pts = upper + corners_right + list(reversed(lower)) + corners_left
    return poly(pts, fill)


designs = {
    # Hoops
    'afl-Adelaide Crows': hoops(['#002B5C', '#E21937', '#FFD200', '#002B5C', '#E21937', '#FFD200']),
    'afl-Geelong Cats': hoops(['#FFFFFF', '#002B5C', '#FFFFFF', '#002B5C', '#FFFFFF', '#002B5C']),
    'afl-Western Bulldogs': svg(100, bg(100, '#0039A6') + rect(0, 36, 100, 14, '#C60C30')
                                + rect(0, 50, 100, 14, '#FFFFFF')),
    # Vertical stripes and panels
    'afl-Collingwood': stripes('#000000', '#FFFFFF', 7),
    'afl-Hawthorn': stripes('#FBBF15', '#4D2004', 7),
    'afl-St Kilda': panels(['#ED1B2F', '#FFFFFF', '#000000']),
    'afl-West Coast Eagles': panels(['#F2A900', '#FFFFFF', '#003087']),
    # Sashes and diagonals
    'afl-Essendon': svg(100, bg(100, '#000000')
                        + poly([(0, 78), (78, 0), (100, 0), (100, 22), (22, 100), (0, 100)], '#CC2031')),
    'afl-GWS Giants': svg(100, bg(100, '#F47920')
                          + poly([(56, 100), (93, 0), (100, 0), (100, 14), (67, 100)], '#FFFFFF')
                          + poly([(67, 100), (100, 14), (100, 100)], '#313B42')),
    # Chevrons and yokes
    'afl-Fremantle': svg(100, bg(100, '#2A0D54')
                         + v_band(12, 24, '#FFFFFF') + v_band(34, 46, '#FFFFFF') + v_band(56, 68, '#FFFFFF')),
    'afl-Port Adelaide': svg(100, bg(100, '#000000')
                             + v_band(46, 70, '#008AAB') + v_band(70, 94, '#FFFFFF')),
    'afl-Sydney Swans': svg(100, bg(100, '#FFFFFF')
                            + poly([(0, 0), (100, 0), (100, 10), (50, 60), (0, 10)], '#E1251B')),
    'nrl-Broncos': svg(100, bg(100, '#6A0F38') + v_band(30, 46, '#FBB03F')),
}

# Finals fixtures name a placeholder team until the matchup is known.
TO_BE_ANNOUNCED = svg(100, bg(100, '#9E9E9E') + poly([(0, 100), (100, 0), (100, 100)], '#BDBDBD'))
designs['afl-to be announced'] = TO_BE_ANNOUNCED
designs['nrl-to be announced'] = TO_BE_ANNOUNCED

for key, text in designs.items():
    (out / f'{key}.svg').write_text(text)
    print(f'{key}: {len(text)} bytes')
