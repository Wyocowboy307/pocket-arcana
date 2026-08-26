"""The combat zone: the neutral strip where the two realms actually meet.

This was a dark polygon with scattered circles on it. It is the middle of the
board and the place every attack resolves, so it has to read as somewhere —
worn ground that has been fought over, with the two elements bleeding into it
from either side.
"""
from . import palette as P
from .canvas import Canvas, hash2, value_noise

FIELD = 128


def clash_field():
    """Packed, trodden battleground: bare earth, embedded stones, old scars."""
    c = Canvas(FIELD, FIELD, wrap=True)
    s = 7700
    for y in range(FIELD):
        for x in range(FIELD):
            n = value_noise(x, y, 11, s)
            m = value_noise(x, y, 5, s + 31)
            idx = 2
            if n < 0.34: idx = 1
            elif n > 0.68: idx = 3
            if m > 0.82: idx += 1
            elif m < 0.16: idx = max(0, idx - 1)
            c.set(x, y, P.STONE[min(len(P.STONE) - 1, idx)])

    for i in range(16):                       # trodden hollows
        cx = int(hash2(i, 0, s) * FIELD); cy = int(hash2(i, 1, s + 3) * FIELD)
        c.blob(cx, cy, 5 + hash2(i, 2, s + 7) * 7, P.STONE[1], 0.44, s + i * 13, 6)
    for i in range(10):                       # dust drifts catching light
        cx = int(hash2(i, 3, s + 11) * FIELD); cy = int(hash2(i, 4, s + 13) * FIELD)
        c.blob(cx, cy, 4 + hash2(i, 5, s + 17) * 5, P.DUST[2], 0.40, s + 100 + i, 6)
    for i in range(22):                       # embedded stones
        cx = int(hash2(i, 6, s + 19) * FIELD); cy = int(hash2(i, 7, s + 23) * FIELD)
        r = 1 + int(hash2(i, 8, s + 29) * 2)
        c.disc(cx, cy, r, P.STONE[4])
        c.disc(cx - 1, cy - 1, max(0, r - 1), P.STONE[6])
        c.set(cx + r, cy + r, P.STONE[0])
    for i in range(9):                        # old drag scars
        x = int(hash2(i, 9, s + 31) * FIELD); y = int(hash2(i, 10, s + 37) * FIELD)
        for k in range(8 + int(hash2(i, 11, s + 41) * 10)):
            c.set(x + k, y + int(1.5 * (value_noise(x + k, 0, 9, s + 43) - 0.5) * 2), P.STONE[0])
    for y in range(FIELD):                    # fine grit
        for x in range(FIELD):
            if hash2(x, y, s + 47) > 0.965:
                c.set(x, y, P.DUST[3])
            elif hash2(x, y, s + 53) > 0.968:
                c.set(x, y, P.STONE[0])
    return c


def lane_mark(lane=0):
    """A worn circle at a lane's meeting point: the ground here gets hit most."""
    size = 72
    c = Canvas(size, size)
    s = 7800 + lane * 61
    cx = cy = size // 2
    for y in range(size):
        for x in range(size):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            edge = 30 + value_noise(x, y, 9, s) * 5
            if d < edge:
                t = d / edge
                if t > 0.86:
                    c.set(x, y, P.STONE[3])
                elif t > 0.72:
                    c.dither(x, y, P.STONE[1], P.STONE[2], 0.5)
                else:
                    c.set(x, y, P.STONE[1] if value_noise(x, y, 6, s + 5) > 0.42 else P.STONE[0])
    for i in range(10):                       # kicked-up stones round the rim
        import math
        a = hash2(i, 0, s + 9) * 6.28318
        r = 26 + hash2(i, 1, s + 11) * 8
        px, py = int(cx + math.cos(a) * r), int(cy + math.sin(a) * r)
        c.disc(px, py, 1 + int(hash2(i, 2, s + 13) * 2), P.STONE[4])
        c.set(px - 1, py - 1, P.STONE[6])
    return c


def magic_crack(v=0):
    """An arcane fissure — the board's own magic showing through, not an
    element's. Cool violet so it never competes with Life green or Fire orange."""
    c = Canvas(64, 20)
    s = 7900 + v * 29
    x, y = 2, 10
    while x < 62:
        for j in range(-2, 3):
            c.set(x, y + j, P.UI_DARK[1] if abs(j) == 2 else P.UI_DARK[0])
        t = min(x, 62 - x) / 20.0
        if t > 0.35:
            c.set(x, y, P.AETHER[2] if t > 0.8 else P.AETHER[1])
            if t > 0.9: c.set(x, y - 1, P.AETHER[3])
        x += 1
        y += 1 if hash2(x, 3, s) > 0.78 else (-1 if hash2(x, 5, s + 1) > 0.80 else 0)
        y = max(4, min(15, y))
    for i in range(2 + v % 2):                # branches
        bx = 10 + int(hash2(i, 7, s + 3) * 40)
        by = 10 + int(hash2(i, 9, s + 5) * 4) - 2
        d = 1 if i % 2 else -1
        for k in range(1, 5):
            c.set(bx + k, by + d * k, P.UI_DARK[0])
            c.set(bx + k, by + d * k - d, P.AETHER[1] if k < 4 else P.UI_DARK[1])
    return c


def rubble(v=0):
    """Loose stones and splintered debris kicked out of the arena floor."""
    c = Canvas(20, 14)
    s = 8000 + v * 17
    for i in range(2 + v % 3):
        px = 3 + int(hash2(i, 0, s) * 14)
        py = 6 + int(hash2(i, 1, s + 3) * 6)
        r = 2 + int(hash2(i, 2, s + 5) * 2)
        c.blob(px, py, r, P.STONE[3], 0.26, s + i * 7, 4)
        c.blob(px - 1, py - 1, max(1, r - 1), P.STONE[5], 0.22, s + 20 + i, 4)
    c.outline(P.INK)
    return c


def kerb(v=0):
    """A boundary stone marking the edge of the arena."""
    c = Canvas(26, 14)
    s = 8100 + v * 11
    w = 9 + int(hash2(0, 0, s) * 4)
    h = 6 + int(hash2(1, 0, s + 3) * 3)
    c.rect(13 - w, 12 - h, w * 2, h, P.STONE[3])
    c.hline(13 - w, 12 + w, 12 - h, P.STONE[5])
    c.hline(13 - w, 12 + w, 11, P.STONE[1])
    for i in range(3):                        # chips
        c.set(13 - w + int(hash2(i, 2, s + 7) * w * 2), 12 - h + 1 + i, P.STONE[2])
    c.outline(P.INK)
    return c


def influence(element, height=26):
    """A strip of one element bleeding into the neutral ground from its side.
    Subtle: the clash zone must stay neutral, it is only *touched* by them."""
    c = Canvas(FIELD, height)
    s = 8200 + sum(ord(ch) for ch in element)
    for x in range(FIELD):
        reach = int(height * (0.35 + 0.5 * value_noise(x, 0, 15, s)))
        for y in range(reach):
            t = 1.0 - y / float(max(reach, 1))
            if element == "life":
                c.dither(x, y, P.STONE[2], P.GROVE[2], t * 0.85)
                if t > 0.75 and hash2(x, y, s + 3) > 0.90:
                    c.set(x, y, P.LEAF[2])
            else:
                c.dither(x, y, P.STONE[2], P.CHAR[2], t * 0.85)
                if t > 0.78 and hash2(x, y, s + 5) > 0.93:
                    c.set(x, y, P.EMBER[1])
    return c


def decal(kind, v=0):
    """A permanent mark left where something landed."""
    c = Canvas(40, 24)
    s = 8300 + v * 23 + sum(ord(ch) for ch in kind)
    cx, cy = 20, 12
    if kind == "scorch":
        c.blob(cx, cy, 11, P.CHAR[1], 0.36, s, 6)
        c.blob(cx, cy, 7, P.CHAR[0], 0.34, s + 5, 5)
        for i in range(7):
            import math
            a = hash2(i, 0, s + 7) * 6.28318
            for k in range(4, 13):
                c.set(int(cx + math.cos(a) * k), int(cy + math.sin(a) * k * 0.6),
                      P.CHAR[1] if k > 8 else P.CHAR[0])
        for i in range(4):
            c.set(cx + int(hash2(i, 1, s + 9) * 14) - 7,
                  cy + int(hash2(i, 2, s + 11) * 8) - 4, P.EMBER[1])
    else:                                     # growth
        c.blob(cx, cy, 10, P.GROVE[2], 0.38, s, 6)
        c.blob(cx, cy, 6, P.GROVE[3], 0.34, s + 5, 5)
        for i in range(9):
            gx = cx + int(hash2(i, 0, s + 7) * 22) - 11
            gy = cy + int(hash2(i, 1, s + 9) * 14) - 7
            c.set(gx, gy, P.LEAF[2]); c.set(gx, gy - 1, P.LEAF[3])
        for i in range(3):
            fx = cx + int(hash2(i, 2, s + 13) * 20) - 10
            fy = cy + int(hash2(i, 3, s + 15) * 12) - 6
            c.set(fx, fy, P.BLOOM[2]); c.set(fx + 1, fy, P.BLOOM[1])
    return c
