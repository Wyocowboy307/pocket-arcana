"""The landscape kit: authored ground, organic edges, corners and transitions.

Land is built from a 32px tileset rather than one texture stretched over a
polygon, which is what makes two neighbouring Groves read as one region instead
of two rectangles. Each element supplies:

  fill a..d      seamless interior, four variants so the field never repeats
  edge n/s/e/w   organic outer rim, transparent outside the land
  corner *       outer corners
  inner *        concave corners where two runs meet
  face           the side/thickness face under the south edge
  trans_*        a seam between two different elements

Interiors are drawn with `wrap=True`, so they tile without a visible grid.
"""
from . import palette as P
from .canvas import Canvas, hash2, value_noise

TILE = 32          # rim/seam strip width
FIELD = 192        # the seamless ground field


# --- shared helpers --------------------------------------------------------

def _patchwork(c, ramp, seed, cells=(9, 5), lo=1, mid=3, hi=5):
    """Chunky flat regions, not per-pixel speckle. Big cells first so the ground
    reads as authored shapes; the small pass only breaks up long flat runs."""
    big, small = cells
    for y in range(c.h):
        for x in range(c.w):
            n = value_noise(x, y, big, seed)
            m = value_noise(x, y, small, seed + 71)
            idx = mid
            if n < 0.36: idx = lo + 1
            elif n < 0.44: idx = mid - 1
            elif n > 0.70: idx = hi - 1
            elif n > 0.62: idx = mid + 1
            if m > 0.80 and idx < hi: idx += 1
            elif m < 0.18 and idx > lo: idx -= 1
            c.set(x, y, ramp[max(0, min(len(ramp) - 1, idx))])


def _speck(c, seed, colour, density, pattern="dot"):
    for y in range(c.h):
        for x in range(c.w):
            if hash2(x, y, seed) > 1.0 - density:
                if pattern == "dot":
                    c.set(x, y, colour)
                elif pattern == "pair":
                    c.set(x, y, colour); c.set(x + 1, y, colour)
                elif pattern == "tick":
                    c.set(x, y, colour); c.set(x, y - 1, colour)


# --- grove -----------------------------------------------------------------


def grove_fill(variant=0):
    """Lush grove floor. Ground is backdrop: tonal patches carry the interest,
    and the bright cues (blooms, glow) stay sparse so creatures still win the
    contrast fight, per docs/ART_BIBLE.md."""
    c = Canvas(TILE, TILE, wrap=True)
    seed = 1400 + variant * 37
    _patchwork(c, P.GROVE, seed, cells=(10, 5), lo=1, mid=3, hi=6)

    for i in range(3):                       # moss pools give depth, no gradient
        cx = int(hash2(i, variant, seed) * TILE)
        cy = int(hash2(i, variant, seed + 9) * TILE)
        c.blob(cx, cy, 4 + hash2(i, variant, seed + 3) * 3, P.GROVE[2], 0.45, seed + i, 4)
    for i in range(2):                       # lit clearings, upper-left light
        cx = int(hash2(i + 7, variant, seed + 11) * TILE)
        cy = int(hash2(i + 7, variant, seed + 13) * TILE)
        c.blob(cx, cy, 3 + hash2(i, variant, seed + 5) * 3, P.GROVE[5], 0.40, seed + 30 + i, 4)

    _speck(c, seed + 41, P.GROVE[1], 0.045, "tick")        # low-contrast grass
    _speck(c, seed + 43, P.GROVE[5], 0.035, "dot")
    _speck(c, seed + 45, P.LEAF[2], 0.020, "tick")

    # Root traces only on two of the four variants, and low contrast — as a bold
    # dark bar they read as a plank and give the tiling away instantly.
    if variant % 2 == 0:
        ry = int(hash2(variant, 5, seed + 23) * TILE)
        run, x = 0, 0
        while x < TILE:
            if hash2(x, variant, seed + 27) > 0.34:        # broken, not continuous
                yy = ry + int(2.0 * (value_noise(x, 0, 13, seed + 29) - 0.5) * 2)
                c.set(x, yy, P.GROVE[2])
                c.set(x, yy + 1, P.WOOD[1] if run % 3 else P.GROVE[1])
                run += 1
            x += 1

    for i in range(2):                       # a couple of blooms, no more
        fx = int(hash2(i, variant, seed + 17) * TILE)
        fy = int(hash2(i, variant, seed + 19) * TILE)
        petal = [P.BLOOM[1], P.CREAM[1]][i % 2]
        c.set(fx, fy, petal); c.set(fx + 1, fy, petal)
    return c


def cinder_fill(variant=0):
    """Scorched forge-ground: char crust and ash drifts. Cracks are rare and
    dim here — a bright seam on every tile turned the field into orange
    lightning and beat the creatures for contrast."""
    c = Canvas(TILE, TILE, wrap=True)
    seed = 2400 + variant * 41
    _patchwork(c, P.CINDER, seed, cells=(9, 4), lo=1, mid=3, hi=6)

    for i in range(3):                       # char pools
        cx = int(hash2(i, variant, seed) * TILE)
        cy = int(hash2(i, variant, seed + 9) * TILE)
        c.blob(cx, cy, 4 + hash2(i, variant, seed + 3) * 3, P.CHAR[1], 0.50, seed + i, 4)
    for i in range(3):                       # ash drifts catching the light
        cx = int(hash2(i + 5, variant, seed + 11) * TILE)
        cy = int(hash2(i + 5, variant, seed + 13) * TILE)
        c.blob(cx, cy, 3 + hash2(i, variant, seed + 5) * 3, P.CINDER[5], 0.42, seed + 30 + i, 4)
    for i in range(2):                       # cracked crust plates
        cx = int(hash2(i + 11, variant, seed + 15) * TILE)
        cy = int(hash2(i + 11, variant, seed + 17) * TILE)
        c.blob(cx, cy, 5 + hash2(i, variant, seed + 7) * 3, P.CINDER[2], 0.46, seed + 50 + i, 5)

    # One short, banked seam on a single variant in four.
    if variant == 1:
        x = int(hash2(0, variant, seed + 31) * TILE)
        y = int(hash2(1, variant, seed + 33) * TILE)
        for step in range(9):
            c.set(x, y, P.EMBER[1])
            c.set(x, y + 1, P.CHAR[0])
            c.set(x, y - 1, P.CHAR[0])
            if 2 < step < 7:
                c.set(x, y, P.EMBER[2])
            x += 1
            y += 1 if hash2(step, 0, seed + 43) > 0.70 else 0

    _speck(c, seed + 51, P.CHAR[0], 0.055, "dot")
    _speck(c, seed + 57, P.CINDER[5], 0.030, "dot")
    _speck(c, seed + 59, P.CINDER[1], 0.030, "dot")
    if variant % 2 == 0:                     # a very few live embers
        for i in range(2):
            c.set(int(hash2(i, variant, seed + 61) * TILE),
                  int(hash2(i, variant, seed + 63) * TILE), P.EMBER[1])
    return c

def ash_fill(variant=0):
    """Ashbloom: blackened soil that has started to flower again."""
    c = Canvas(TILE, TILE, wrap=True)
    seed = 3400 + variant * 29
    _patchwork(c, P.CINDER, seed, cells=(10, 5), lo=1, mid=2, hi=5)
    for i in range(3):
        cx = int(hash2(i, variant, seed + 7) * TILE)
        cy = int(hash2(i, variant, seed + 11) * TILE)
        c.blob(cx, cy, 5 + hash2(i, variant, seed) * 3, P.GROVE[2], 0.50, seed + i, 5)
    _speck(c, seed + 61, P.LEAF[3], 0.045, "tick")
    _speck(c, seed + 63, P.EMBER[3], 0.016, "dot")
    for i in range(5):
        fx = int(hash2(i, variant, seed + 17) * TILE)
        fy = int(hash2(i, variant, seed + 19) * TILE)
        petal = [P.BLOOM[2], P.SPORE[2], P.CREAM[2]][i % 3]
        c.set(fx, fy, petal); c.set(fx + 1, fy, petal); c.set(fx, fy + 1, P.SPORE[1])
    return c


def neutral_fill(variant=0):
    """Untamed ground: the board before anyone has built on it."""
    c = Canvas(TILE, TILE, wrap=True)
    seed = 4400 + variant * 23
    _patchwork(c, P.STONE, seed, cells=(11, 5), lo=1, mid=3, hi=6)
    for i in range(3):
        cx = int(hash2(i, variant, seed) * TILE)
        cy = int(hash2(i, variant, seed + 9) * TILE)
        c.blob(cx, cy, 4 + hash2(i, variant, seed + 3) * 3, P.DUST[1], 0.45, seed + i, 5)
    _speck(c, seed + 71, P.DUST[2], 0.045, "tick")
    _speck(c, seed + 73, P.STONE[1], 0.030, "dot")
    return c


_RAW = {}

FILLS = {"grove": grove_fill, "cinder": cinder_fill,
         "ashbloom": ash_fill, "neutral": neutral_fill}
CREST = {"grove": P.GROVE, "cinder": P.CINDER, "ashbloom": P.CINDER, "neutral": P.STONE}
LIT   = {"grove": P.GROVE[6], "cinder": P.CINDER[6], "ashbloom": P.CINDER[5], "neutral": P.STONE[6]}




# --- the ground field ------------------------------------------------------
#
# One large wrapping field per element rather than four 32px variants.
#
# Four mutually-tiling 32px variants cannot be had cheaply: freezing a shared
# border ring so any variant abuts any other puts an identical band of pixels
# every 32px, and that regular ring reads as horizontal banding across the
# realm. A single 128px field repeats seven times across a realm instead of
# twenty-nine, and the props scattered on top break up what is left.

def field(element):
    """A 128x128 seamless ground field.

    Order matters. The join pass has to be modest and mid-toned — a heavy blob
    pass painted straight over the grass, moss and crack detail and left both
    elements reading as camouflage. So: tile, cross the joins gently, then lay
    the fine detail back over the top where it survives.
    """
    c = Canvas(FIELD, FIELD, wrap=True)
    builder = FILLS[element]
    for ty in range(FIELD // TILE):
        for tx in range(FIELD // TILE):
            c.paste(builder((tx * 3 + ty * 5) % 4), tx * TILE, ty * TILE)

    ramp = CREST[element]
    seed = 900 + sum(ord(ch) for ch in element)

    # 1. Cross the internal 32px joins so no feature stops dead on a boundary.
    #    Mid-tones only, and sized to bridge a join rather than repaint the tile.
    for i in range(14):
        cx = int(hash2(i, 0, seed) * FIELD)
        cy = int(hash2(i, 1, seed + 3) * FIELD)
        r = 4 + hash2(i, 2, seed + 7) * 5
        c.blob(cx, cy, r, ramp[2 if i % 2 else 4], 0.44, seed + i * 11, 6)
    for i in range(6):
        cx = int(hash2(i, 4, seed + 13) * FIELD)
        cy = int(hash2(i, 5, seed + 17) * FIELD)
        c.blob(cx, cy, 5 + hash2(i, 6, seed + 19) * 4, ramp[1], 0.40, seed + 200 + i, 6)

    # 2. Fine detail, applied across the whole field so it reads continuous.
    _field_detail(c, element, seed)
    return c


def _field_detail(c, element, seed):
    """The pass that decides whether ground reads as a place or as a texture."""
    if element in ("grove", "ashbloom"):
        _speck(c, seed + 41, P.GROVE[1], 0.050, "tick")
        _speck(c, seed + 43, P.GROVE[5], 0.038, "dot")
        _speck(c, seed + 45, P.LEAF[2], 0.022, "tick")
        for i in range(9):                       # clover / leaf litter clumps
            cx = int(hash2(i, 7, seed + 23) * FIELD)
            cy = int(hash2(i, 8, seed + 29) * FIELD)
            for k in range(5):
                dx = int(hash2(k, i, seed + 31) * 7) - 3
                dy = int(hash2(k, i, seed + 37) * 7) - 3
                c.set(cx + dx, cy + dy, P.LEAF[1 + k % 2])
        for i in range(7):                       # blooms, sparse
            fx = int(hash2(i, 9, seed + 17) * FIELD)
            fy = int(hash2(i, 10, seed + 19) * FIELD)
            petal = [P.BLOOM[1], P.CREAM[1], P.BERRY[1]][i % 3]
            c.set(fx, fy, petal); c.set(fx + 1, fy, petal); c.set(fx, fy + 1, P.LEAF[1])
        for i in range(5):                       # short root traces
            rx = int(hash2(i, 11, seed + 47) * FIELD)
            ry = int(hash2(i, 12, seed + 53) * FIELD)
            for k in range(6 + int(hash2(i, 13, seed + 59) * 8)):
                yy = ry + int(1.6 * (value_noise(rx + k, 0, 11, seed + 61) - 0.5) * 2)
                c.set(rx + k, yy, P.GROVE[1])
                c.set(rx + k, yy + 1, P.WOOD[1])
    else:
        _speck(c, seed + 51, P.CHAR[0], 0.055, "dot")
        _speck(c, seed + 57, P.CINDER[5], 0.032, "dot")
        _speck(c, seed + 59, P.CINDER[1], 0.034, "dot")
        for i in range(10):                      # cracked crust plates
            cx = int(hash2(i, 7, seed + 23) * FIELD)
            cy = int(hash2(i, 8, seed + 29) * FIELD)
            c.blob(cx, cy, 3 + hash2(i, 9, seed + 31) * 4, P.CHAR[1], 0.46, seed + 300 + i, 5)
        for i in range(4):                       # dim seams, never bright
            x = int(hash2(i, 10, seed + 31) * FIELD)
            y = int(hash2(i, 11, seed + 33) * FIELD)
            for step in range(7 + int(hash2(i, 12, seed + 39) * 6)):
                c.set(x, y, P.CHAR[0]); c.set(x, y + 1, P.CHAR[0])
                if 1 < step < 6: c.set(x, y, P.EMBER[1])
                x += 1
                y += 1 if hash2(step, i, seed + 43) > 0.74 else 0
        for i in range(4):                       # a very few live embers
            c.set(int(hash2(i, 13, seed + 61) * FIELD),
                  int(hash2(i, 14, seed + 63) * FIELD), P.EMBER[2])


# --- rim strips ------------------------------------------------------------
#
# A rim is ADDITIVE: it is the outermost sliver of land plus its lit or shaded
# edge, drawn on top of an inset field. Immediate-mode drawing cannot punch a
# hole in a rect, so the silhouette has to be added outward rather than cut
# inward. It also means a tone mismatch at the joint is hidden under the rim
# line, which is a deliberate highlight anyway.

RIM = 18


def rim(element, side, variant=0):
    """One organic edge strip, 32 wide. `side` is n/s/e/w."""
    ramp = CREST[element]
    horizontal = side in ("n", "s")
    w, h = (TILE, RIM) if horizontal else (RIM, TILE)
    c = Canvas(w, h)
    seed = 5100 + variant * 131 + {"n": 0, "s": 1, "e": 2, "w": 3}[side] * 977
    fld = field(element)

    span = w if horizontal else h
    for i in range(span):
        # How far the land pushes outward at this step.
        out = 4 + int(value_noise(i, 0, 9, seed) * 8)
        for j in range(RIM):
            if j >= out:
                continue
            if side == "n":   x, y = i, RIM - 1 - j
            elif side == "s": x, y = i, j
            elif side == "w": x, y = RIM - 1 - j, i
            else:             x, y = j, i
            c.set(x, y, fld.get(x + variant * 37, y + variant * 53))

        if side == "n":
            c.set(i, RIM - out, LIT[element])
            if out > 1: c.set(i, RIM - out + 1, ramp[4])
        elif side == "s":
            c.set(i, out - 1, ramp[1])
            if out > 1: c.set(i, out - 2, ramp[2])
        elif side == "w":
            c.set(RIM - out, i, ramp[5])
        else:
            c.set(out - 1, i, ramp[2])

    if element == "grove" and side == "n":
        for i in range(0, TILE, 3):                    # grass fringing the top rim
            out = 4 + int(value_noise(i, 0, 9, seed) * 8)
            blade = 2 + int(hash2(i, 0, seed + 5) * 3)
            for k in range(blade):
                c.set(i, RIM - out - k, P.LEAF[2 if k < blade - 1 else 4])
    if element == "cinder" and side == "n":
        for i in range(0, TILE, 5):                    # crumbling char lip
            if hash2(i, 0, seed + 9) > 0.55:
                out = 4 + int(value_noise(i, 0, 9, seed) * 8)
                c.set(i, RIM - out - 1, P.CHAR[1])
    return c


def rim_corner(element, corner_name, variant=0):
    """Where two rims meet: rounded off so the region is not a square notch."""
    ramp = CREST[element]
    c = Canvas(RIM + 8, RIM + 8)
    seed = 6100 + variant * 17 + sum(ord(ch) for ch in corner_name)
    fld = field(element)
    north = "n" in corner_name
    west = "w" in corner_name
    size = RIM + 8
    for y in range(size):
        for x in range(size):
            ax = (size - 1 - x) if west else x
            ay = (size - 1 - y) if north else y
            r = ((ax - 0) ** 2 + (ay - 0) ** 2) ** 0.5
            edge = size - 6 + value_noise(x, y, 7, seed) * 5
            if r < edge:
                c.set(x, y, fld.get(x + 61, y + 29))
    for y in range(size):
        for x in range(size):
            if c.get(x, y) is None:
                continue
            outward = c.get(x, y - 1) if north else c.get(x, y + 1)
            if outward is None:
                c.set(x, y, LIT[element] if north else ramp[1])
    return c


# --- thickness and seams ---------------------------------------------------

def face(element, variant=0):
    """The side face under the south rim: the slab's visible thickness. Without
    it the region reads as a sticker lying on the backdrop."""
    c = Canvas(TILE, 14)
    ramp = CREST[element]
    seed = 8100 + variant * 11
    for x in range(TILE):
        depth = 10 + int(value_noise(x, 0, 9, seed) * 4)
        for y in range(depth):
            t = y / float(max(depth - 1, 1))
            c.dither(x, y, ramp[2], ramp[1], 1.0 - t * 0.8)
        c.set(x, 0, ramp[3])
        if element in ("cinder", "ashbloom") and hash2(x, 0, seed + 5) > 0.84:
            c.set(x, 2, P.EMBER[1]); c.set(x, 3, P.CHAR[1])
        if element == "grove" and hash2(x, 0, seed + 7) > 0.86:
            c.set(x, 1, P.WOOD[2]); c.set(x, 2, P.WOOD[1])
    return c


def transition(left, right, variant=0):
    """A seam where two elements meet: interlocking, never a straight cut."""
    a, b = field(left), field(right)
    c = Canvas(TILE, TILE)
    seed = 9100 + variant * 7
    for y in range(TILE):
        split = 16 + int((value_noise(0, y, 8, seed) - 0.5) * 14)
        for x in range(TILE):
            src = a if x < split else b
            c.set(x, y, src.get(x + variant * 31, y + variant * 17))
        blendmark = P.CHAR[1] if right in ("cinder", "ashbloom") else P.GROVE[2]
        c.set(split, y, blendmark)
        if hash2(0, y, seed + 3) > 0.55:
            c.set(split + 1, y, blendmark)
    return c
