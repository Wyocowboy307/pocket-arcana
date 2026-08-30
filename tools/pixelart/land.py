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


def _calm(c, ramp4, seed, cells=(15, 6), third=0.86):
    """The 2026-08-30 ground language: large flat value cells within a narrow
    ramp, no per-pixel speckle. The old 3-5% speck passes are what made every
    capture read as camouflage noise; calm surfaces are the fix, and props and
    creatures carry the detail budget instead."""
    big, small = cells
    for y in range(c.h):
        for x in range(c.w):
            n = value_noise(x, y, big, seed)
            m = value_noise(x, y, small, seed + 7)
            i = 1
            if n < 0.40: i = 0
            elif n > 0.68: i = 2
            if m > third and i == 2: i = 3
            c.set(x, y, ramp4[i])


def grove_fill(variant=0):
    """Grove floor: mossy flats a step darker than the creature greens, so a
    Sproutling never sinks into its own land. Accents stay countable."""
    c = Canvas(TILE, TILE, wrap=True)
    seed = 1400 + variant * 37
    _calm(c, [P.GROVE[1], P.GROVE[2], P.GROVE[3], P.GROVE[4]], seed)
    for i in range(2):                       # moss pools, tone-on-tone
        cx = int(hash2(i, variant, seed) * TILE)
        cy = int(hash2(i, variant, seed + 9) * TILE)
        c.blob(cx, cy, 4 + hash2(i, variant, seed + 3) * 3, P.GROVE[2], 0.45, seed + i, 4)
    if variant % 2 == 0:                     # one bloom on half the tiles
        fx = int(hash2(0, variant, seed + 17) * TILE)
        fy = int(hash2(0, variant, seed + 19) * TILE)
        petal = [P.BLOOM[1], P.CREAM[1]][variant % 2]
        c.set(fx, fy, petal); c.set(fx + 1, fy, petal); c.set(fx, fy + 1, P.LEAF[1])
    return c


def cinder_fill(variant=0):
    """Scorched forge-ground: warm dark crust, embers sparse but genuinely
    hot. The board must read black-with-fire, never mud — this is what makes
    the rival half feel owned before a single creature lands."""
    c = Canvas(TILE, TILE, wrap=True)
    seed = 2400 + variant * 41
    _calm(c, [P.CINDER[2], P.CINDER[3], P.CINDER[4], P.CINDER[5]], seed)
    if variant % 2 == 0:                     # one char pool on half the tiles
        cx = int(hash2(0, variant, seed) * TILE)
        cy = int(hash2(0, variant, seed + 9) * TILE)
        c.blob(cx, cy, 4 + hash2(0, variant, seed + 3) * 3, P.CHAR[1], 0.50, seed, 4)
    # Live ember seam on half the tiles: short, hot, countable.
    if variant % 2 == 1:
        x = int(hash2(0, variant, seed + 31) * TILE)
        y = int(hash2(1, variant, seed + 33) * TILE)
        for step in range(7):
            c.set(x, y + 1, P.CHAR[0]); c.set(x, y - 1, P.CHAR[0])
            c.set(x, y, P.EMBER[2] if 1 < step < 6 else P.EMBER[1])
            x += 1
            y += 1 if hash2(step, 0, seed + 43) > 0.70 else 0
    for i in range(2):                       # lone hot motes
        c.set(int(hash2(i, variant, seed + 61) * TILE),
              int(hash2(i, variant, seed + 63) * TILE), P.EMBER[3])
    return c

def ash_fill(variant=0):
    """Ashbloom: blackened soil that has started to flower again."""
    c = Canvas(TILE, TILE, wrap=True)
    seed = 3400 + variant * 29
    _calm(c, [P.CINDER[1], P.CINDER[2], P.CINDER[3], P.CINDER[4]], seed)
    for i in range(2):
        cx = int(hash2(i, variant, seed + 7) * TILE)
        cy = int(hash2(i, variant, seed + 11) * TILE)
        c.blob(cx, cy, 5 + hash2(i, variant, seed) * 3, P.GROVE[2], 0.50, seed + i, 5)
    for i in range(3):
        fx = int(hash2(i, variant, seed + 17) * TILE)
        fy = int(hash2(i, variant, seed + 19) * TILE)
        petal = [P.BLOOM[2], P.SPORE[2], P.CREAM[2]][i % 3]
        c.set(fx, fy, petal); c.set(fx + 1, fy, petal); c.set(fx, fy + 1, P.SPORE[1])
    return c


def neutral_fill(variant=0):
    """Untamed ground: worn stone, calm — used for rail dressing and the
    clash-channel surrounds rather than the whole board (the board itself is
    now the arcane table, tools/pixelart/table.py)."""
    c = Canvas(TILE, TILE, wrap=True)
    seed = 4400 + variant * 23
    _calm(c, [P.STONE[1], P.STONE[2], P.STONE[3], P.STONE[4]], seed)
    for i in range(2):
        cx = int(hash2(i, variant, seed) * TILE)
        cy = int(hash2(i, variant, seed + 9) * TILE)
        c.blob(cx, cy, 4 + hash2(i, variant, seed + 3) * 3, P.DUST[1], 0.45, seed + i, 5)
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

_CALM_RAMPS = {
    "grove":    lambda: [P.GROVE[1], P.GROVE[2], P.GROVE[3], P.GROVE[4]],
    "cinder":   lambda: [P.CINDER[2], P.CINDER[3], P.CINDER[4], P.CINDER[5]],
    "ashbloom": lambda: [P.CINDER[1], P.CINDER[2], P.CINDER[3], P.CINDER[4]],
    "neutral":  lambda: [P.STONE[1], P.STONE[2], P.STONE[3], P.STONE[4]],
}

def field(element):
    """A 192x192 seamless ground field.

    The calm pattern is generated across the WHOLE canvas rather than pasted
    from 32px fills — per-tile generation put a 32px period into the value
    cells, and the repeat read instantly on the big merged slabs.
    """
    c = Canvas(FIELD, FIELD, wrap=True)
    seed = 900 + sum(ord(ch) for ch in element)
    _calm(c, _CALM_RAMPS[element](), seed, cells=(52, 17))

    ramp = CREST[element]
    # Cross-canvas mid-tone pools, so the surface has regions rather than grain.
    for i in range(10):
        cx = int(hash2(i, 0, seed) * FIELD)
        cy = int(hash2(i, 1, seed + 3) * FIELD)
        r = 4 + hash2(i, 2, seed + 7) * 5
        c.blob(cx, cy, r, ramp[2 if i % 2 else 3], 0.44, seed + i * 11, 6)

    # A handful of countable features — never a speck wash. The calm-ground
    # rule (docs/V2_ART_PASS_TRIAGE.md) is that detail lives in props and
    # creatures; the field only murmurs.
    _field_detail(c, element, seed)
    if element == "cinder":
        # The live ember seams moved up from the 32px fills: a few per field.
        for i in range(4):
            x = int(hash2(i, 20, seed + 81) * FIELD)
            y = int(hash2(i, 21, seed + 83) * FIELD)
            for step in range(7):
                c.set(x, y + 1, P.CHAR[0]); c.set(x, y - 1, P.CHAR[0])
                c.set(x, y, P.EMBER[2] if 1 < step < 6 else P.EMBER[1])
                x += 1
                y += 1 if hash2(step, i, seed + 87) > 0.70 else 0
    return c


def _field_detail(c, element, seed):
    """The pass that decides whether ground reads as a place or as a texture."""
    if element in ("grove", "ashbloom"):
        for i in range(5):                       # clover clumps, tone-on-tone
            cx = int(hash2(i, 7, seed + 23) * FIELD)
            cy = int(hash2(i, 8, seed + 29) * FIELD)
            for k in range(4):
                dx = int(hash2(k, i, seed + 31) * 7) - 3
                dy = int(hash2(k, i, seed + 37) * 7) - 3
                c.set(cx + dx, cy + dy, P.LEAF[1 + k % 2])
        for i in range(4):                       # blooms, sparse and countable
            fx = int(hash2(i, 9, seed + 17) * FIELD)
            fy = int(hash2(i, 10, seed + 19) * FIELD)
            petal = [P.BLOOM[1], P.CREAM[1], P.BERRY[1]][i % 3]
            c.set(fx, fy, petal); c.set(fx + 1, fy, petal); c.set(fx, fy + 1, P.LEAF[1])
    else:
        for i in range(6):                       # crust plates
            cx = int(hash2(i, 7, seed + 23) * FIELD)
            cy = int(hash2(i, 8, seed + 29) * FIELD)
            c.blob(cx, cy, 3 + hash2(i, 9, seed + 31) * 4, P.CHAR[1], 0.46, seed + 300 + i, 5)
        for i in range(3):                       # dim seams, never bright
            x = int(hash2(i, 10, seed + 31) * FIELD)
            y = int(hash2(i, 11, seed + 33) * FIELD)
            for step in range(7 + int(hash2(i, 12, seed + 39) * 6)):
                c.set(x, y, P.CHAR[0]); c.set(x, y + 1, P.CHAR[0])
                if 1 < step < 6: c.set(x, y, P.EMBER[1])
                x += 1
                y += 1 if hash2(step, i, seed + 43) > 0.74 else 0
        for i in range(3):                       # a very few live embers
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

FACE_H = 26

def face(element, variant=0):
    """The plot's visible thickness: a tall earth face under the top surface.

    26px, not the old 14 — the direction lock makes land a chunky elevated
    diorama slab, and the thickness is most of what sells it. The bottom two
    rows are baked INK so a tiled run carries the slab's outline with it.
    """
    c = Canvas(TILE, FACE_H, wrap=True)
    seed = 8100 + variant * 11
    if element == "grove":
        body, deep, tick = P.WOOD[2], P.WOOD[1], P.WOOD[3]
        lip = P.GROVE[5]
    elif element == "ashbloom":
        body, deep, tick = P.CHAR[2], P.CHAR[1], P.CINDER[4]
        lip = P.CINDER[5]
    elif element == "cinder":
        body, deep, tick = P.CHAR[2], P.CHAR[0], P.CINDER[3]
        lip = P.EMBER[1]
    else:
        body, deep, tick = P.STONE[2], P.STONE[1], P.STONE[3]
        lip = P.STONE[5]
    # Flat banded earth, not a dither gradient — an ordered dither over 24px
    # reads as polka dots at this scale.
    for x in range(TILE):
        c.set(x, 0, lip)                       # lit lip where top meets face
        band1 = 9 + int(value_noise(x, 0, 11, seed) * 4)
        band2 = 17 + int(value_noise(x, 0, 7, seed + 3) * 4)
        for y in range(1, FACE_H - 2):
            c.set(x, y, body if y < band1 else (deep if y >= band2 else
                  (body if (x + y) % 5 else deep)))
        c.set(x, FACE_H - 2, P.INK)
        c.set(x, FACE_H - 1, P.INK)
    # strata: short horizontal ticks, like pressed earth layers
    for k in range(7):
        x0 = int(hash2(k, variant, seed) * TILE)
        y0 = 4 + int(hash2(k, variant, seed + 3) * (FACE_H - 12))
        ln = 3 + int(hash2(k, variant, seed + 5) * 5)
        for i in range(ln):
            c.set((x0 + i) % TILE, y0, tick if k % 2 else deep)
    # element flavour: roots trailing down a grove face, ember cracks in cinder
    if element == "grove":
        for k in range(3):
            x0 = int(hash2(k, variant, seed + 7) * TILE)
            for y in range(2, 8 + int(hash2(k, variant, seed + 9) * 8)):
                c.set(x0, y, P.WOOD[1])
    elif element in ("cinder", "ashbloom"):
        for k in range(2):
            x0 = int(hash2(k, variant, seed + 7) * TILE)
            for y in range(3, 9):
                c.set(x0, y, P.EMBER[1] if y < 6 else P.CHAR[0])
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
