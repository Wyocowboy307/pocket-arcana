"""Construction stages for Places, derived from the finished building.

A Place must physically belong to its land, and it must be *built*, not
teleported in. Rather than generating four separate buildings and hoping they
line up, every stage is cut from the one approved sprite:

  foundation  cleared ground, footing stones, marker posts
  stage 1     the lower third standing, scaffolded
  stage 2     most of it up, scaffold still on
  complete    the approved sprite itself

Deriving them guarantees the stages register perfectly with the final building,
which is the thing that sells the animation.
"""
from PIL import Image

from . import palette as P
from .canvas import Canvas, hash2, value_noise


def _from_image(path):
    im = Image.open(path).convert("RGBA")
    c = Canvas(im.width, im.height)
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a > 128:
                c.px[y][x] = (r, g, b)
    return c


def _footprint(src):
    """The x-span the building actually occupies, per row from the bottom."""
    rows = []
    for y in range(src.h):
        xs = [x for x in range(src.w) if src.px[y][x] is not None]
        rows.append((min(xs), max(xs)) if xs else None)
    return rows


def _ground_pad(c, src, element):
    """Cleared, levelled ground under the build — this is what makes the Place
    sit *in* the land instead of on top of it."""
    rows = _footprint(src)
    solid = [r for r in rows if r]
    if not solid:
        return
    lo = min(r[0] for r in solid) - 4
    hi = max(r[1] for r in solid) + 4
    base = src.h - 1
    seed = 5500 + sum(ord(ch) for ch in element)
    for y in range(base - 7, base + 1):
        t = (y - (base - 7)) / 7.0
        inset = int((1.0 - t) * 5)
        for x in range(lo + inset, hi - inset + 1):
            if hash2(x, y, seed) > 0.10:
                c.set(x, y, P.DUST[1] if hash2(x, y, seed + 3) > 0.45 else P.DUST[2])
    for i in range(9):                                  # footing stones
        fx = lo + int(hash2(i, 0, seed + 7) * max(1, hi - lo))
        fy = base - 2 - int(hash2(i, 1, seed + 11) * 4)
        c.disc(fx, fy, 1 + int(hash2(i, 2, seed + 13) * 2), P.STONE[3])
        c.set(fx - 1, fy - 1, P.STONE[5])


def _scaffold(c, src, upto_y, element):
    """Poles and planks around the part still going up."""
    rows = _footprint(src)
    solid = [r for r in rows if r]
    if not solid:
        return
    lo = min(r[0] for r in solid) - 3
    hi = max(r[1] for r in solid) + 3
    wood = P.WOOD if element == "life" else P.IRON
    top = max(2, upto_y - 10)
    for x in (lo, hi):                                  # uprights
        for y in range(top, src.h - 1):
            c.set(x, y, wood[2]); c.set(x + 1, y, wood[1])
    for k in range(3):                                  # cross planks
        y = top + int((src.h - 1 - top) * (k + 1) / 4.0)
        for x in range(lo, hi + 2):
            c.set(x, y, wood[3] if x % 5 else wood[2])
        c.set(lo + 2, y - 1, wood[4] if len(wood) > 4 else wood[3])
    for k in range(2):                                  # diagonal brace
        x0 = lo if k == 0 else hi
        step = 1 if k == 0 else -1
        x, y = x0, src.h - 2
        while y > top and 0 <= x < src.w:
            c.set(x, y, wood[1])
            x += step; y -= 1


def stage(path, element, level):
    """level: 0 foundation, 1 lower third, 2 most of it, 3 complete."""
    src = _from_image(path)
    if level >= 3:
        return src
    c = Canvas(src.w, src.h)
    _ground_pad(c, src, element)
    if level == 0:
        rows = _footprint(src)
        solid = [r for r in rows if r]
        if solid:
            lo = min(r[0] for r in solid) - 2
            hi = max(r[1] for r in solid) + 2
            for x in (lo, hi, (lo + hi) // 2):          # marker posts
                for y in range(src.h - 14, src.h - 2):
                    c.set(x, y, P.WOOD[2] if element == "life" else P.IRON[2])
                c.set(x, src.h - 15, P.WOOD[4] if element == "life" else P.IRON[4])
            for x in range(lo, hi + 1):                 # string line
                if x % 3 == 0:
                    c.set(x, src.h - 15, P.CREAM[1])
        return c

    keep = {1: 0.34, 2: 0.72}[level]
    cut = int(src.h - src.h * keep)
    for y in range(cut, src.h):
        for x in range(src.w):
            if src.px[y][x] is not None:
                c.set(x, y, src.px[y][x])
    # A raw top edge where the build stops.
    for x in range(src.w):
        if c.get(x, cut) is not None:
            c.set(x, cut, P.WOOD[3] if element == "life" else P.IRON[3])
    _scaffold(c, src, cut, element)
    return c


def passive_glow(element, w=64, h=32):
    """The visual a Place's passive effect emits: a soft ring of its element
    settling over the lane it supports."""
    c = Canvas(w, h)
    ramp = P.SPORE if element == "life" else P.EMBER
    seed = 5800 + sum(ord(ch) for ch in element)
    cx, cy = w // 2, h // 2
    for y in range(h):
        for x in range(w):
            dx = (x - cx) / float(cx)
            dy = (y - cy) / float(cy)
            d = (dx * dx + dy * dy) ** 0.5
            if 0.74 < d < 1.0 and hash2(x, y, seed) > 0.42:
                c.set(x, y, ramp[1 if d > 0.88 else 2])
    for i in range(7):                                   # motes lifting off it
        c.set(cx + int((hash2(i, 0, seed + 3) - 0.5) * w * 0.7),
              cy + int((hash2(i, 1, seed + 5) - 0.5) * h * 0.7), ramp[3])
    return c
