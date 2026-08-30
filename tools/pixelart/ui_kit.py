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
    # two interlocking rings: two-become-one (a dots-and-bar glyph read as
    # a floating "-1" badge in review)
    import math
    for dcx in (-2.5, 2.5):
        for a in range(20):
            ang = a / 20.0 * 6.28318
            x = int(cx + dcx + math.cos(ang) * 3.6)
            y = int(cy + math.sin(ang) * 3.6)
            c.set(x, y, P.GOLD[4])
    return c


# --- component chrome -------------------------------------------------------

def _bevel_box(c, w, h, fill, hi, lo, edge=None):
    for y in range(h):
        for x in range(w):
            c.set(x, y, fill)
    for x in range(2, w - 2):
        c.set(x, 2, hi); c.set(x, 3, hi)
        c.set(x, h - 3, lo); c.set(x, h - 4, lo)
    for y in range(2, h - 2):
        c.set(2, y, hi)
        c.set(w - 3, y, lo)
    c.frame(0, 0, w, h, P.INK)
    c.frame(1, 1, w - 2, h - 2, P.INK)
    if edge is not None:
        c.frame(3, 3, w - 6, h - 6, edge)
    # chamfered corners
    for cx, cy, dx, dy in ((0, 0, 1, 1), (w - 1, 0, -1, 1),
                           (0, h - 1, 1, -1), (w - 1, h - 1, -1, -1)):
        for k in range(3):
            c.set(cx + dx * k, cy, P.INK); c.set(cx, cy + dy * k, P.INK)


def button(kind, state):
    """A chunky carved button, 9-patched by the UI (10px margins).

    kinds: gold (END TURN), stone (utility), talisman (COMBINE — the marquee).
    states: normal, hover, pressed, disabled."""
    w, h = 72, 48
    c = Canvas(w, h)
    if kind == "gold":
        fill, hi, lo = P.GOLD[2], P.GOLD[3], P.GOLD[1]
    elif kind == "talisman":
        fill, hi, lo = P.GOLD[3], P.GOLD[4], P.GOLD[2]
    else:
        fill, hi, lo = P.STONE[3], P.STONE[4], P.STONE[2]
    edge = None
    if state == "hover":
        fill = tuple(min(255, v + 18) for v in fill)
        edge = P.CREAM[3] if kind != "stone" else P.STONE[5]
    elif state == "pressed":
        fill, hi, lo = lo, lo, lo
    elif state == "disabled":
        g = (58, 55, 60)
        fill, hi, lo = g, tuple(min(255, v + 10) for v in g), tuple(max(0, v - 8) for v in g)
    _bevel_box(c, w, h, fill, hi, lo, edge)
    if kind == "talisman" and state not in ("disabled",):
        # rune studs: this button is a magical object, not a rectangle
        for x in (8, w - 9):
            for y in (8, h - 9):
                c.set(x, y, P.CREAM[3]); c.set(x + 1, y, P.CREAM[3])
                c.set(x, y + 1, P.CREAM[3]); c.set(x + 1, y + 1, P.GOLD[4])
    return c


def tray(w=192, h=172):
    """The wooden hand tray the cards rest on. Tiles horizontally."""
    c = Canvas(w, h, wrap=True)
    for y in range(h):
        for x in range(w):
            c.set(x, y, P.WOOD[2])
    # plank rows
    for py in range(10, h, 34):
        for x in range(w):
            c.set(x, py, P.WOOD[1])
            if (x + py) % 47 == 0:
                c.set(x, py + 1, P.WOOD[1])
    # vertical plank joints, offset per row
    row = 0
    for py in range(10, h - 1, 34):
        off = (row * 61) % w
        for j in range(off, off + 1):
            for y in range(py, min(py + 34, h)):
                c.set(j % w, y, P.WOOD[1])
        row += 1
    # wood grain flecks
    for i in range(int(w * h * 0.004)):
        gx = int(hash2(i, 0, 77) * w)
        gy = int(hash2(i, 1, 79) * h)
        c.set(gx, gy, P.WOOD[3])
    # lit top lip + ink top edge: the tray's front edge against the table
    for x in range(w):
        c.set(x, 0, P.INK); c.set(x, 1, P.INK)
        c.set(x, 2, P.WOOD[4]); c.set(x, 3, P.WOOD[3])
    return c


def parchment(w=96, h=72):
    """A parchment panel for tooltips, coaching and overlays. 9-patch, 12px."""
    c = Canvas(w, h)
    for y in range(h):
        for x in range(w):
            c.set(x, y, P.CREAM[2])
    for x in range(2, w - 2):
        c.set(x, 2, P.CREAM[3])
        c.set(x, h - 3, P.CREAM[1])
    for i in range(int(w * h * 0.006)):
        gx = int(hash2(i, 0, 81) * w)
        gy = int(hash2(i, 1, 83) * h)
        c.set(gx, gy, P.CREAM[1])
    c.frame(0, 0, w, h, P.INK)
    c.frame(1, 1, w - 2, h - 2, P.INK)
    # torn corner nicks
    for cx, cy, dx, dy in ((0, 0, 1, 1), (w - 1, 0, -1, 1),
                           (0, h - 1, 1, -1), (w - 1, h - 1, -1, -1)):
        for k in range(4):
            c.set(cx + dx * k, cy, P.INK); c.set(cx, cy + dy * k, P.INK)
        c.set(cx + dx * 2, cy + dy * 2, P.INK)
        c.set(cx + dx * 3, cy + dy * 3, P.CREAM[1])
    return c
