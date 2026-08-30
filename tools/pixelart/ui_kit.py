"""Physical game components: the chunky tokens pieces wear on the board.

Direction lock (docs/V2_ART_PASS_TRIAGE.md §5): every number on the
battlefield lives in a carved, bevelled token in the board's own pixel
language — never a flat vector circle. The stage draws the live numeral on
top, so tokens ship with an empty socket face.
"""
from . import palette as P
from .canvas import Canvas, hash2

TOKEN = 26


def _disc(c, cx, cy, r, fill, edge_hi, edge_lo):
    for y in range(c.h):
        for x in range(c.w):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            if d <= r + 1.2:
                c.set(x, y, P.INK)
    for y in range(c.h):
        for x in range(c.w):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            if d <= r - 0.4:
                c.set(x, y, fill)
                # bevel: lit upper-left arc, shaded lower-right arc
                if r - 2.6 <= d:
                    c.set(x, y, edge_hi if (x - cx) - (y - cy) < 0 else edge_lo)
    # inner socket dish, a step darker, where the numeral sits
    for y in range(c.h):
        for x in range(c.w):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            if d <= r - 4.5:
                c.set(x, y, edge_lo)
            if d <= r - 5.5:
                c.set(x, y, fill)


def stat_token(kind):
    """power = gold sun chip, health = heart-red drop chip, presence = leaf,
    cost = aether crystal. 26px, drawn 2x on the board."""
    c = Canvas(TOKEN, TOKEN)
    cx = cy = TOKEN // 2
    r = TOKEN // 2 - 2
    if kind == "power":
        _disc(c, cx, cy, r, P.GOLD[2], P.GOLD[3], P.GOLD[1])
        for k in range(8):                      # sun nicks round the rim
            import math
            a = k / 8.0 * 6.28318
            x = int(cx + math.cos(a) * (r - 1))
            y = int(cy + math.sin(a) * (r - 1))
            c.set(x, y, P.GOLD[4])
    elif kind == "health":
        _disc(c, cx, cy, r, P.HEART[2], P.HEART[3], P.HEART[1])
        c.set(cx - 3, cy - r + 2, P.HEART[4]); c.set(cx - 2, cy - r + 2, P.HEART[4])
    elif kind == "presence":
        _disc(c, cx, cy, r, P.LEAF[3], P.LEAF[4], P.LEAF[1])
    else:  # cost
        _disc(c, cx, cy, r, P.AETHER[2], P.AETHER[3], P.AETHER[1])
        c.set(cx - 3, cy - 4, P.AETHER[4]); c.set(cx - 3, cy - 3, P.AETHER[4])
    return c


def moon_chip():
    """The resting marker: a small slate chip with a carved crescent."""
    s = 18
    c = Canvas(s, s)
    cx = cy = s // 2
    r = s // 2 - 1.5
    for y in range(s):
        for x in range(s):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            if d <= r + 1.0:
                c.set(x, y, P.INK)
            if d <= r - 0.5:
                c.set(x, y, P.UI_DARK[2])
    for y in range(s):
        for x in range(s):
            d1 = ((x - cx - 1) ** 2 + (y - cy) ** 2) ** 0.5
            d2 = ((x - cx - 4) ** 2 + (y - cy - 1) ** 2) ** 0.5
            if d1 <= 5 and d2 > 5:
                c.set(x, y, P.CREAM[2])
    return c


def link_rune():
    """The fusion link: a gold twin-spiral chip hung between two compatible
    creatures. Brighter than anything else at rest — fusion is the marquee."""
    s = 22
    c = Canvas(s, s)
    cx = cy = s // 2
    # diamond chip
    for y in range(s):
        for x in range(s):
            if abs(x - cx) + abs(y - cy) <= s // 2:
                c.set(x, y, P.INK)
            if abs(x - cx) + abs(y - cy) <= s // 2 - 2:
                c.set(x, y, P.GOLD[1])
            if abs(x - cx) + abs(y - cy) <= s // 2 - 4:
                c.set(x, y, P.GOLD[2])
    # twin dots joined by a bar: two-become-one
    for dx in (-3, 3):
        c.set(cx + dx, cy, P.GOLD[4]); c.set(cx + dx, cy - 1, P.GOLD[4])
        c.set(cx + dx, cy + 1, P.GOLD[3])
    c.set(cx - 1, cy, P.GOLD[4]); c.set(cx, cy, P.GOLD[4]); c.set(cx + 1, cy, P.GOLD[4])
    return c
