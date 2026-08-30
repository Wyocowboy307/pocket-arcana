"""The arcane table: the calm surface the whole battlefield is built on.

Direction lock (docs/V2_ART_PASS_TRIAGE.md): the unbuilt board is a dark slate
game table, not terrain. Value cells are large and soft, there is no per-pixel
speckle, and the only ornament is carved — sockets and lane guides are drawn by
the stage at runtime; this module supplies the surfaces and the inlaid rune
medallions for the clash channel.
"""
from . import palette as P
from .canvas import Canvas, hash2, value_noise

FIELD = 192          # seamless table tile
MEDALLION = 56       # clash-channel rune disc


def table_field(variant=0):
    """Seamless slate. Two close values plus a rare third — calm on purpose."""
    c = Canvas(FIELD, FIELD, wrap=True)
    seed = 9100 + variant * 41
    for y in range(FIELD):
        for x in range(FIELD):
            n = value_noise(x, y, 48, seed)
            m = value_noise(x, y, 17, seed + 7)
            i = 1
            if n < 0.40: i = 0
            elif n > 0.66: i = 2
            if m > 0.86 and i == 2: i = 3
            c.set(x, y, P.TABLE[i])
    # a few faint worn scratches, sparse enough to never read as texture
    for k in range(5):
        x0 = int(hash2(k, variant, seed + 11) * FIELD)
        y0 = int(hash2(k, variant, seed + 13) * FIELD)
        ln = 4 + int(hash2(k, variant, seed + 17) * 8)
        for i in range(ln):
            c.set((x0 + i) % FIELD, y0, P.TABLE[0])
    return c


def channel_field(variant=0):
    """The inlaid clash channel surface: one step darker than the table."""
    c = Canvas(FIELD, 96, wrap=True)
    seed = 9300 + variant * 31
    dark = [P.TABLE[0], P.TABLE[0], P.TABLE[1]]
    for y in range(96):
        for x in range(FIELD):
            n = value_noise(x, y, 40, seed)
            c.set(x, y, dark[0 if n < 0.5 else (1 if n < 0.8 else 2)])
    # faint centre guide
    for x in range(FIELD):
        if x % 9 < 5:
            c.set(x, 48, P.TABLE_LINE)
    return c


# Rune strokes for the four lane medallions, one glyph each, drawn on a 16px
# grid: (x0, y0, x1, y1) line segments.
_RUNES = [
    [(8, 2, 8, 14), (3, 6, 13, 6), (4, 11, 12, 11)],                    # gate
    [(3, 11, 8, 5), (8, 5, 13, 11), (3, 14, 8, 8), (8, 8, 13, 14)],     # chevrons
    [(3, 3, 13, 13), (13, 3, 3, 13), (8, 1, 8, 5)],                     # cross
    [(8, 2, 13, 8), (13, 8, 8, 14), (8, 14, 3, 8), (3, 8, 8, 2)],       # eye
]


def medallion(variant=0):
    """A carved rune disc set into the clash channel."""
    s = MEDALLION
    c = Canvas(s, s)
    cx = cy = s // 2
    r_out = s // 2 - 2
    for y in range(s):
        for x in range(s):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            if d <= r_out:
                c.set(x, y, P.TABLE[0])
    # engraved double ring
    for y in range(s):
        for x in range(s):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            if r_out - 1.4 <= d <= r_out:
                c.set(x, y, P.TABLE_LINE)
            elif r_out - 5.2 <= d <= r_out - 3.8:
                c.set(x, y, P.TABLE_RUNE)
    # the glyph
    glyph = _RUNES[variant % len(_RUNES)]
    k = (s - 24) / 16.0
    ox = oy = 12
    for (x0, y0, x1, y1) in glyph:
        steps = int(max(abs(x1 - x0), abs(y1 - y0)) * k) + 1
        for i in range(steps + 1):
            t = i / max(1, steps)
            x = int(ox + (x0 + (x1 - x0) * t) * k)
            y = int(oy + (y0 + (y1 - y0) * t) * k)
            for dx in range(2):
                for dy in range(2):
                    c.set(x + dx, y + dy, P.TABLE_RUNE)
    return c
