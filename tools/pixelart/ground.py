"""One continuous battlefield surface, plus the atmosphere that gives it depth.

The board is no longer slabs floating on a backdrop. It is a single lit ground
plane: Cinder at the top, worn neutral where the two sides actually meet, Grove
at the bottom, joined by interlocking blend strips so no boundary is a straight
line. Depth comes from a vignette, a warm light pool over the centre, and dark
out-of-focus foreground pieces framing the screen edges.
"""
from PIL import Image

from . import palette as P
from .canvas import Canvas, hash2, value_noise
from . import land, clash

WIDE = 192


def _sample(fieldc, x, y):
    return fieldc.get(x % fieldc.w, y % fieldc.h)


def blend(top_element, bottom_element, height=56, seed=0):
    """An interlocking seam between two ground regions.

    Deliberately not a fade: two palette ramps averaged together produce colours
    that are in neither ramp. This interleaves them instead, with a ragged
    boundary and scattered islands of each pushing into the other.
    """
    top = clash.clash_field() if top_element == "neutral" else land.field(top_element)
    bot = clash.clash_field() if bottom_element == "neutral" else land.field(bottom_element)
    c = Canvas(WIDE, height, wrap=True)
    s = 6600 + seed * 37

    for x in range(WIDE):
        # A ragged boundary that wraps, so the strip tiles across the screen.
        edge = height * 0.5 + (value_noise(x, 0, 21, s) - 0.5) * height * 0.55 \
                            + (value_noise(x, 0, 7, s + 11) - 0.5) * height * 0.16
        for y in range(height):
            c.set(x, y, _sample(top if y < edge else bot, x, y))

    # Islands of each element pushing across the seam: the join reads as two
    # grounds meeting rather than one gradient.
    for i in range(16):
        cx = int(hash2(i, 0, s + 3) * WIDE)
        up = i % 2 == 0
        cy = int(height * (0.30 if up else 0.70) + (hash2(i, 1, s + 5) - 0.5) * height * 0.3)
        r = 3 + hash2(i, 2, s + 7) * 5
        src = bot if up else top
        rr = r * 1.5
        for y in range(int(cy - rr), int(cy + rr) + 1):
            for x in range(int(cx - rr), int(cx + rr) + 1):
                dx, dy = x - cx, y - cy
                d = (dx * dx + dy * dy) ** 0.5
                if d <= r * (1.0 + (value_noise(x, y, 5, s + i) - 0.5) * 0.7):
                    c.set(x, y, _sample(src, x, y))

    # Debris gathers where ground types meet.
    for i in range(10):
        dx2 = int(hash2(i, 3, s + 13) * WIDE)
        dy2 = int(height * 0.35 + hash2(i, 4, s + 17) * height * 0.3)
        c.disc(dx2, dy2, 1 + int(hash2(i, 5, s + 19) * 2), P.STONE[3])
        c.set(dx2 - 1, dy2 - 1, P.STONE[5])
    return c


def foreground_piece(kind, v=0):
    """Dark out-of-focus scenery framing the screen edge. Nearly silhouette:
    it must never compete with the play surface, only enclose it."""
    if kind == "roots":
        c = Canvas(150, 80)
        s = 7000 + v * 31
        for i in range(4):
            y0 = 10 + i * 16 + int(hash2(i, 0, s) * 8)
            px, py = 0, y0
            thick = 6 - i % 3
            while px < 150:
                py += 1 if hash2(px, i, s + 3) > 0.72 else (-1 if hash2(px, i, s + 5) > 0.74 else 0)
                py = max(2, min(76, py))
                for j in range(thick):
                    c.set(px, py + j, P.WOOD[0] if j < thick - 1 else P.INK)
                px += 1
        for i in range(8):                       # a few lit edges catch the light
            lx = int(hash2(i, 6, s + 7) * 140)
            for yy in range(80):
                if c.get(lx, yy) == P.WOOD[0]:
                    c.set(lx, yy, P.WOOD[1]); break
    elif kind == "branch":
        c = Canvas(190, 96)
        s = 7100 + v * 29
        px, py = 0, 20 + int(hash2(0, 0, s) * 14)
        while px < 190:
            py += 1 if hash2(px, 1, s + 3) > 0.66 else (-1 if hash2(px, 2, s + 5) > 0.70 else 0)
            py = max(4, min(50, py))
            for j in range(7):
                c.set(px, py + j, P.INK if j > 4 else P.WOOD[0])
            if px % 22 == 0:                     # hanging leaf clusters
                for k in range(5):
                    lx = px + int(hash2(k, px, s + 7) * 12) - 6
                    ly = py + 8 + int(hash2(k, px, s + 11) * 22)
                    r = 4 + hash2(k, px, s + 13) * 4
                    c.blob(lx, ly, r, P.GROVE[0], 0.32, s + k * 7 + px, 5)
            px += 1
    else:                                        # "rock" — a dark boulder mass
        c = Canvas(120, 90)
        s = 7200 + v * 23
        for i in range(5):
            cx = 20 + i * 20 + int(hash2(i, 0, s) * 10)
            cy = 50 + int(hash2(i, 1, s + 3) * 30)
            c.blob(cx, cy, 18 + hash2(i, 2, s + 5) * 12, P.CHAR[0], 0.30, s + i * 11, 8)
        for i in range(4):
            cx = 24 + i * 24
            c.blob(cx, 40 + int(hash2(i, 3, s + 7) * 10), 6, P.CHAR[1], 0.28, s + 40 + i, 6)
    return c


def light_pool(size=192):
    """A warm radial pool over the centre of the board. This is lighting, not
    art, so it carries a smooth alpha — dithering a light this large reads as
    dirt on the lens rather than as depth."""
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = im.load()
    c = (size - 1) / 2.0
    for y in range(size):
        for x in range(size):
            d = (((x - c) / c) ** 2 + ((y - c) / c) ** 2) ** 0.5
            if d >= 1.0:
                continue
            t = (1.0 - d) ** 2.2
            px[x, y] = (255, 236, 196, int(t * 74))
    return im


def contact_shadow(w, h):
    """A soft grounded shadow to sit under a card or a creature."""
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = im.load()
    cx, cy = (w - 1) / 2.0, (h - 1) / 2.0
    for y in range(h):
        for x in range(w):
            d = (((x - cx) / cx) ** 2 + ((y - cy) / cy) ** 2) ** 0.5
            if d >= 1.0:
                continue
            px[x, y] = (8, 6, 10, int((1.0 - d) ** 1.7 * 150))
    return im


def row_path(element="neutral", w=128, h=104):
    """A worn, trodden strip laid along a combat row.

    This is how a row reads as a zone without drawing a box around it: the
    ground itself is beaten flat where things stand. Edges are ragged binary
    alpha so the patch melts into the surrounding field instead of ending on a
    straight line.
    """
    src = clash.clash_field() if element == "neutral" else land.field(element)
    c = Canvas(w, h, wrap=False)
    s = 7300 + sum(ord(ch) for ch in element)
    for x in range(w):
        # Deep, multi-scale ragged edges. A shallow wobble still reads as a
        # horizontal stripe laid across the board.
        top = int(2 + value_noise(x, 0, 31, s) * 20 + value_noise(x, 0, 11, s + 7) * 9
                  + value_noise(x, 0, 4, s + 17) * 4)
        bot = h - int(2 + value_noise(x, 40, 29, s + 11) * 20 + value_noise(x, 0, 11, s + 13) * 9
                      + value_noise(x, 0, 4, s + 19) * 4)
        for y in range(top, bot):
            v = _sample(src, x, y)
            # Trodden: flatten toward the mid tones, darker at the centre line.
            edge_t = min(y - top, bot - y) / float(max((bot - top) * 0.5, 1))
            # Wear the centre line only. Recolouring most of the strip to stone
            # turned every row into a grey concrete band and erased the element.
            if edge_t > 0.82 and hash2(x, y, s + 17) > 0.52:
                v = P.STONE[2] if hash2(x, y, s + 19) > 0.5 else P.STONE[3]
            elif edge_t > 0.5 and hash2(x, y, s + 21) > 0.72:
                v = P.DUST[1] if hash2(x, y, s + 23) > 0.5 else P.DUST[2]
            c.set(x, y, v)
    for i in range(18):                       # scuffs and pressed stones
        px = int(hash2(i, 0, s + 23) * w)
        py = int(h * 0.25 + hash2(i, 1, s + 29) * h * 0.5)
        c.disc(px, py, 1 + int(hash2(i, 2, s + 31) * 2), P.STONE[4])
        c.set(px - 1, py - 1, P.STONE[6])
    for i in range(9):
        px = int(hash2(i, 3, s + 37) * w)
        py = int(h * 0.3 + hash2(i, 4, s + 41) * h * 0.4)
        for k in range(6 + int(hash2(i, 5, s + 43) * 9)):
            c.set(px + k, py + int(1.5 * (value_noise(px + k, 0, 9, s + 47) - 0.5) * 2), P.STONE[1])
    return c


def patch(element, size=140, v=0):
    """A large irregular ground patch, scattered non-periodically over the field.

    A 128px field tiled across a 1280px board repeats ten times, and the eye
    finds that grid immediately. Rather than chase ever-larger seamless
    textures, these break the periodicity: big organic areas of alternate tone
    placed at hashed positions that share no period with the tile.
    """
    src = clash.clash_field() if element == "neutral" else land.field(element)
    c = Canvas(size, size)
    s = 7500 + v * 61 + sum(ord(ch) for ch in element)
    cx = cy = size / 2.0
    for y in range(size):
        for x in range(size):
            dx = (x - cx) / cx
            dy = (y - cy) / cy
            d = (dx * dx + dy * dy) ** 0.5
            edge = 0.62 + value_noise(x, y, 26, s) * 0.34 + value_noise(x, y, 9, s + 7) * 0.10
            if d < edge:
                c.set(x, y, _sample(src, x + v * 53, y + v * 31))

    ramp = land.CREST.get(element, P.STONE)
    for i in range(9):                                   # tonal shift inside it
        bx = int(hash2(i, 0, s + 11) * size)
        by = int(hash2(i, 1, s + 13) * size)
        if c.get(bx, by) is None:
            continue
        tone = ramp[1] if i % 2 else ramp[3]
        r = 8 + hash2(i, 2, s + 17) * 16
        rr = r * 1.5
        for y in range(int(by - rr), int(by + rr) + 1):
            for x in range(int(bx - rr), int(bx + rr) + 1):
                if c.get(x, y) is None:
                    continue
                dd = ((x - bx) ** 2 + (y - by) ** 2) ** 0.5
                if dd <= r * (1.0 + (value_noise(x, y, 7, s + i) - 0.5) * 0.8):
                    c.set(x, y, tone)

    if element in ("grove", "ashbloom"):                 # what makes it a place
        for i in range(26):
            px = int(hash2(i, 3, s + 19) * size)
            py = int(hash2(i, 4, s + 23) * size)
            if c.get(px, py) is None:
                continue
            c.set(px, py, P.LEAF[2]); c.set(px, py - 1, P.LEAF[3])
        for i in range(7):
            px = int(hash2(i, 5, s + 29) * size)
            py = int(hash2(i, 6, s + 31) * size)
            if c.get(px, py) is None:
                continue
            petal = [P.BLOOM[1], P.CREAM[1], P.BERRY[1]][i % 3]
            c.set(px, py, petal); c.set(px + 1, py, petal)
    elif element == "cinder":
        for i in range(20):
            px = int(hash2(i, 3, s + 19) * size)
            py = int(hash2(i, 4, s + 23) * size)
            if c.get(px, py) is None:
                continue
            c.set(px, py, P.CHAR[0])
        for i in range(5):
            px = int(hash2(i, 5, s + 29) * size)
            py = int(hash2(i, 6, s + 31) * size)
            if c.get(px, py) is not None:
                c.set(px, py, P.EMBER[1])
    return c
