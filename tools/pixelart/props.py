"""Decorative props for Grove and Cinder.

Everything here is a bold outlined board piece: chunky silhouette, two or three
flat tones, light from the upper left, one ink rim all the way round. These are
what turn a textured patch into a place you recognise, and they replace the
vector draw_line/draw_circle props the stage used to scribble at runtime.

Every builder takes a variant index so a field of five mushrooms is five
different mushrooms rather than one sprite repeated.
"""
from . import palette as P
from .canvas import Canvas, hash2, value_noise


def _finish(c, soft_shadow=True):
    c.outline(P.INK)
    if soft_shadow:
        pass
    return c


def _rand(seed, i, lo=0.0, hi=1.0):
    return lo + hash2(i, 0, seed) * (hi - lo)


# =========================== GROVE =========================================

def grove_tree(v=0):
    """A small storybook tree: fat trunk, layered canopy clumps."""
    c = Canvas(34, 44)
    s = 100 + v * 13
    tx = 17
    # Trunk with a lit left face.
    for y in range(24, 42):
        w = 3 + int((y - 24) * 0.22)
        c.hline(tx - w, tx + w, y, P.WOOD[2])
        c.vline(tx - w, y, y, P.WOOD[3])
        c.vline(tx + w, y, y, P.WOOD[1])
    # Roots flaring at the base.
    for k in (-1, 1):
        c.line(tx + k * 3, 40, tx + k * 8, 42, P.WOOD[1])
        c.line(tx + k * 3, 39, tx + k * 7, 41, P.WOOD[2])
    # Canopy: three overlapping clumps, biggest in the middle.
    clumps = [(tx - 8, 16, 8), (tx + 8, 17, 8), (tx, 10, 11), (tx - 4, 20, 7), (tx + 5, 21, 6)]
    for i, (cx, cy, r) in enumerate(clumps):
        c.blob(cx + int(_rand(s, i, -1, 1)), cy, r, P.LEAF[2], 0.26, s + i, 5)
    for i, (cx, cy, r) in enumerate(clumps):
        c.blob(cx - 2, cy - 2, r * 0.62, P.LEAF[3], 0.24, s + 20 + i, 4)
    c.blob(tx - 5, 8, 5, P.LEAF[4], 0.22, s + 40, 4)     # upper-left highlight
    # Fruit / blossom so it reads as magical rather than generic foliage.
    for i in range(3 + v % 2):
        fx = int(_rand(s + 7, i, 5, 29)); fy = int(_rand(s + 9, i, 8, 24))
        if c.get(fx, fy) is not None:
            col = [P.BERRY[2], P.BLOOM[2], P.CREAM[2]][i % 3]
            c.set(fx, fy, col); c.set(fx + 1, fy, col); c.set(fx, fy + 1, col)
    return _finish(c)




def grove_root(v=0):
    """A gnarled root breaking the surface: thick, knuckled, with the soil it
    pushed up. Reads as a root at board scale, not as a brown hump."""
    c = Canvas(34, 22)
    s = 130 + v * 7
    c.rect(2, 15, 30, 5, P.GROVE[2])                      # disturbed soil bed
    c.hline(3, 30, 15, P.GROVE[3])

    x0, x1 = 3, 31
    height = 8 + v % 3
    prev_top = None
    for x in range(x0, x1):
        t = (x - x0) / float(x1 - x0 - 1)
        arch = height * (1.0 - (2 * t - 1) ** 2) ** 0.7
        arch += 1.6 * (value_noise(x, 0, 6, s) - 0.5) * 2  # knuckly, not a clean arc
        top = int(16 - arch)
        thick = 5 if arch > 3 else 4
        c.vline(x, top, top + thick, P.WOOD[2])
        c.set(x, top, P.WOOD[4])                           # lit crown
        c.set(x, top + 1, P.WOOD[3])
        c.set(x, top + thick, P.WOOD[1])
        if prev_top is not None and abs(top - prev_top) > 1:   # bark step
            c.vline(x, min(top, prev_top), max(top, prev_top), P.WOOD[2])
        prev_top = top
        if x % 5 == 0:                                     # bark ridges
            c.vline(x, top + 1, top + thick - 1, P.WOOD[1])

    for k, x in ((0, x0), (1, x1 - 1)):                    # it goes back underground
        c.vline(x, 12, 19, P.WOOD[1])
        c.vline(x + (1 if k == 0 else -1), 13, 18, P.WOOD[2])
    for i in range(4):                                     # moss on the sunlit crown
        mx = int(_rand(s + 3, i, 6, 27))
        for j in range(3):
            for yy in range(4, 14):
                if c.get(mx + j, yy) == P.WOOD[4]:
                    c.set(mx + j, yy, P.GROVE[4]); c.set(mx + j, yy + 1, P.GROVE[3])
                    break
    for i in range(2):                                     # a sprout, because it is alive
        sx = int(_rand(s + 11, i, 8, 26))
        c.set(sx, 14, P.LEAF[3]); c.set(sx, 13, P.LEAF[2]); c.set(sx + 1, 13, P.LEAF[4])
    return _finish(c)

def grove_vine(v=0):
    """A rope-thick vine with fat paired leaves."""
    c = Canvas(20, 34)
    s = 140 + v * 11
    for y in range(2, 32):
        x = 9 + int(3.0 * (value_noise(0, y, 9, s) - 0.5) * 2)
        c.set(x, y, P.LEAF[3]); c.set(x + 1, y, P.LEAF[2]); c.set(x + 2, y, P.LEAF[1])
        if y % 7 == 2:
            side = 1 if (y // 7) % 2 else -1
            ox = x + (3 if side > 0 else -1)
            for k in range(4):                            # a leaf, not a tick
                w = 3 - abs(k - 1)
                for j in range(-w, w + 1):
                    c.set(ox + side * k, y + j, P.LEAF[2 + (j < 0)])
            c.set(ox + side * 3, y - 1, P.LEAF[4])
    for i in range(3):
        bx = 9 + int(_rand(s + 5, i, -3, 4)); by = int(_rand(s + 7, i, 6, 30))
        c.set(bx, by, P.BLOOM[2]); c.set(bx + 1, by, P.BLOOM[2]); c.set(bx, by + 1, P.BLOOM[1])
    return _finish(c)


def grove_flower(v=0):
    """A chunky bloom: fat stem, two broad leaves, a solid petal head."""
    c = Canvas(18, 24)
    s = 150 + v * 5
    head = [P.BLOOM, P.BERRY, P.CREAM, P.SPORE][v % 4]
    x = 9
    for y in range(11, 22):                               # 2px stem
        off = int(1.4 * (value_noise(0, y, 8, s) - 0.5) * 2)
        c.set(x + off, y, P.LEAF[3]); c.set(x + off + 1, y, P.LEAF[2])
    for side, ly in ((-1, 16), (1, 14)):                  # broad leaves
        for k in range(1, 6):
            w = 2 - abs(k - 3) // 2
            for j in range(-w, w + 1):
                c.set(x + side * k + (1 if side > 0 else 0), ly + j, P.LEAF[2 + (j < 0)])
    for y in range(4, 11):                                # solid petal head
        half = 4 - abs(y - 7)
        c.hline(x - half - 1, x + half + 1, y, head[2])
    c.hline(x - 3, x + 4, 7, head[min(3, len(head) - 1)])
    c.rect(x - 1, 6, 3, 3, P.GOLD[3])
    c.set(x - 1, 6, P.GOLD[4]); c.set(x + 1, 8, P.GOLD[2])
    return _finish(c)


def grove_mushroom(v=0):
    """A wide domed cap on a stubby stalk. The cap must overhang the stalk
    clearly, or it reads as a goblet."""
    c = Canvas(24, 22)
    s = 160 + v * 9
    caps = [(P.BERRY, P.CREAM[3]), (P.EMBER, P.CREAM[3]),
            (P.BLOOM, P.CREAM[3]), (P.SPORE, P.CREAM[3])]
    cap, spot = caps[v % 4]
    cx = 12
    rx = 9 + v % 2
    dome = 7
    for y in range(dome):                                  # domed top
        half = int(rx * (1.0 - (y / float(dome)) ** 2) ** 0.5)
        c.hline(cx - half, cx + half, 3 + y, cap[2])
    c.hline(cx - rx, cx + rx, 10, cap[2])                  # the overhanging brim
    c.hline(cx - rx, cx + rx, 11, cap[1])
    c.set(cx - rx, 10, cap[1]); c.set(cx + rx, 10, cap[1])
    for x in range(cx - rx + 1, cx + rx):                  # gills under the brim
        if x % 2 == 0: c.set(x, 12, P.CREAM[1])
    for i in range(3 + v % 2):                             # cap spots
        sx = cx + int(_rand(s, i, -6, 7)); sy = 4 + int(_rand(s + 2, i, 0, 5))
        if c.get(sx, sy) is not None:
            for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1)):
                if c.get(sx + dx, sy + dy) is not None: c.set(sx + dx, sy + dy, spot)
    for y in range(3, 8):                                  # upper-left sheen
        for x in range(cx - 7, cx - 2):
            if c.get(x, y) == cap[2] and (x + y) % 3: c.set(x, y, cap[min(3, len(cap) - 1)])
    for y in range(12, 20):                                # stalk, clearly narrower
        c.hline(cx - 3, cx + 3, y, P.CREAM[2])
        c.set(cx - 3, y, P.CREAM[1]); c.set(cx + 3, y, P.CREAM[1])
        c.set(cx - 2, y, P.CREAM[3] if y < 16 else P.CREAM[2])
    c.hline(cx - 5, cx + 5, 20, P.CREAM[1])                # foot
    return _finish(c)

def grove_grass(v=0):
    """A fat tuft — wedge blades, not scratches."""
    c = Canvas(22, 18)
    s = 170 + v * 3
    blades = 5 + v % 3
    for i in range(blades):
        bx = 4 + int(i * (13.0 / blades)) + int(_rand(s, i, 0, 2))
        h = 8 + int(_rand(s + 1, i, 0, 6))
        lean = _rand(s + 2, i, -2.5, 2.5)
        for k in range(h):
            t = k / float(h)
            w = 1 if t > 0.72 else 2                      # wedge: fat base, fine tip
            px = bx + int(lean * t * t * 2)
            for j in range(w):
                c.set(px + j, 15 - k, P.LEAF[2 if j == 0 else 1])
        c.set(bx + int(lean * 2), 15 - h, P.LEAF[4])
    c.rect(3, 14, 16, 3, P.GROVE[2])                      # a clod of soil under it
    c.hline(4, 18, 14, P.GROVE[3])
    return _finish(c)

def grove_stone(v=0):
    """A mossy boulder — flat top plane, dark under-face."""
    c = Canvas(22, 18)
    s = 180 + v * 17
    cx, cy = 11, 11
    c.blob(cx, cy, 7 + v % 2, P.STONE[3], 0.24, s, 6)
    c.blob(cx - 2, cy - 3, 5, P.STONE[5], 0.22, s + 3, 5)
    c.blob(cx + 2, cy + 3, 4, P.STONE[1], 0.24, s + 5, 5)
    for i in range(4):                       # moss caps the lit surface
        mx = cx + int(_rand(s + 7, i, -6, 6)); my = cy + int(_rand(s + 9, i, -6, 0))
        if c.get(mx, my) is not None:
            c.set(mx, my, P.GROVE[4]); c.set(mx + 1, my, P.GROVE[3])
    return _finish(c)


def grove_glowplant(v=0):
    """A glowing bulb plant — the 'this land is magical' cue."""
    c = Canvas(18, 26)
    s = 190 + v * 7
    for k, (bx, by, r) in enumerate([(9, 8, 4), (5, 13, 3), (13, 14, 3)][: 2 + v % 2]):
        for y in range(by + r, 23):
            c.set(bx + int(1.2 * (value_noise(0, y, 6, s + k) - 0.5) * 2), y, P.LEAF[2])
        c.disc(bx, by, r, P.SPORE[1])
        c.disc(bx, by, r - 1, P.SPORE[2])
        c.disc(bx - 1, by - 1, max(1, r - 2), P.SPORE[3])
    for i in range(3):                       # drifting motes
        c.set(int(_rand(s + 11, i, 2, 16)), int(_rand(s + 13, i, 1, 8)), P.SPORE[3])
    c.hline(3, 15, 24, P.GROVE[2])
    return _finish(c)


def grove_detail(v=0):
    """Little garden business: a berry bush, a stack of stones, a lantern post."""
    c = Canvas(20, 24)
    s = 200 + v * 19
    kind = v % 3
    if kind == 0:                             # berry bush
        c.blob(10, 15, 7, P.LEAF[2], 0.28, s, 5)
        c.blob(8, 12, 5, P.LEAF[3], 0.24, s + 3, 4)
        for i in range(5):
            bx = int(_rand(s + 5, i, 4, 16)); by = int(_rand(s + 7, i, 9, 20))
            if c.get(bx, by) is not None:
                c.set(bx, by, P.BERRY[2]); c.set(bx, by - 1, P.BERRY[1])
    elif kind == 1:                           # cairn
        for i, (w, y) in enumerate(((7, 20), (5, 16), (4, 12), (2, 9))):
            c.rect(10 - w, y - 3, w * 2, 4, P.STONE[3 + i % 2])
            c.hline(10 - w, 10 + w, y - 3, P.STONE[5])
        c.set(10, 7, P.SPORE[2]); c.set(9, 6, P.SPORE[3])
    else:                                     # lantern on a hook
        c.vline(6, 4, 22, P.WOOD[2]); c.vline(7, 4, 22, P.WOOD[1])
        c.hline(6, 13, 4, P.WOOD[2])
        c.vline(13, 5, 7, P.WOOD[1])
        c.rect(10, 8, 7, 8, P.IRON[2])
        c.rect(11, 9, 5, 6, P.GOLD[3])
        c.rect(12, 10, 3, 4, P.GOLD[4])
        c.hline(9, 17, 16, P.IRON[1])
    return _finish(c)


# =========================== CINDER ========================================

def cinder_burnt_tree(v=0):
    """A cracked black trunk with snapped branches and live embers inside."""
    c = Canvas(30, 44)
    s = 300 + v * 13
    tx = 15
    for y in range(6, 42):
        w = 2 + int((y - 6) * 0.13)
        c.hline(tx - w, tx + w, y, P.CHAR[2])
        c.vline(tx - w, y, y, P.CHAR[3])
        c.vline(tx + w, y, y, P.CHAR[0])
    for i in range(3):                        # snapped branches
        by = 10 + i * 9 + int(_rand(s, i, 0, 3))
        side = 1 if i % 2 else -1
        ex = tx + side * (7 + int(_rand(s + 2, i, 0, 5)))
        c.line(tx + side * 2, by, ex, by - 5 - i, P.CHAR[2])
        c.line(tx + side * 2, by + 1, ex, by - 4 - i, P.CHAR[1])
        c.set(ex, by - 5 - i, P.EMBER[2])
    for i in range(5):                        # glowing seams in the bark
        gy = int(_rand(s + 5, i, 12, 40))
        gx = tx + int(_rand(s + 7, i, -3, 4))
        c.set(gx, gy, P.EMBER[3]); c.set(gx, gy + 1, P.EMBER[2])
        if i % 2: c.set(gx + 1, gy, P.EMBER[1])
    for k in (-1, 1):
        c.line(tx + k * 3, 40, tx + k * 8, 42, P.CHAR[1])
    return _finish(c)


def cinder_rock(v=0):
    """Angular charcoal — hard planes, never a soft pebble."""
    c = Canvas(24, 20)
    s = 310 + v * 11
    pts = []
    n = 6
    for i in range(n):
        import math
        a = (i / float(n)) * 6.28318
        r = 7 + _rand(s, i, 0, 4)
        pts.append((12 + math.cos(a) * r, 11 + math.sin(a) * r * 0.8))
    c.poly(pts, P.CHAR[2])
    top = [(p[0], p[1]) for p in pts if p[1] < 11]
    if len(top) >= 3:
        c.poly(top + [(12, 11)], P.CINDER[4])
    for i in range(3):
        gx = int(_rand(s + 5, i, 5, 19)); gy = int(_rand(s + 7, i, 8, 17))
        if c.get(gx, gy) is not None:
            c.set(gx, gy, P.EMBER[2]); c.set(gx + 1, gy, P.EMBER[3])
    return _finish(c)



def cinder_debris(v=0):
    """Forge leftovers — solid metal masses, readable at a glance."""
    c = Canvas(24, 18)
    s = 320 + v * 7
    kind = v % 3
    if kind == 0:                                          # broken anvil
        c.rect(3, 5, 17, 5, P.IRON[3]); c.hline(3, 19, 5, P.IRON[4])
        c.rect(7, 10, 8, 5, P.IRON[2])
        c.rect(5, 15, 12, 2, P.IRON[3]); c.hline(5, 16, 15, P.IRON[4])
        c.set(20, 6, P.IRON[4]); c.set(2, 8, P.IRON[2])
        c.set(18, 7, P.EMBER[2])
    elif kind == 1:                                        # ingot stack
        for i, (x, y, w) in enumerate(((4, 12, 15), (6, 8, 12), (8, 4, 9))):
            c.rect(x, y, w, 4, P.IRON[2 + i % 2])
            c.hline(x, x + w - 1, y, P.IRON[4])
            c.hline(x, x + w - 1, y + 3, P.IRON[1])
        c.set(10, 5, P.EMBER[3]); c.set(11, 5, P.EMBER[2])
    else:                                                  # crucible and tongs
        c.rect(4, 8, 11, 7, P.IRON[2])
        c.hline(3, 15, 8, P.IRON[4]); c.hline(5, 14, 15, P.IRON[1])
        c.rect(6, 9, 7, 3, P.EMBER[3]); c.rect(7, 10, 5, 2, P.HOT[2])
        c.line(16, 14, 21, 5, P.IRON[3]); c.line(17, 14, 22, 5, P.IRON[2])
        c.line(18, 14, 21, 8, P.IRON[3])
    return _finish(c)


def cinder_crack(v=0):
    """A fissure in the floor: dark lips first, hot core inside. Reads as a
    hole in the ground rather than a glowing worm lying on top of it."""
    c = Canvas(30, 14)
    s = 330 + v * 5
    path = []
    x, y = 2, 7
    while x < 28:
        path.append((x, y))
        x += 1
        y += 1 if hash2(x, 3, s + 1) > 0.80 else (-1 if hash2(x, 5, s + 2) > 0.82 else 0)
        y = max(4, min(9, y))
    for (px, py) in path:                                  # dark lips
        for j in range(-2, 3):
            c.set(px, py + j, P.CHAR[1] if abs(j) == 2 else P.CHAR[0])
    for i, (px, py) in enumerate(path):                    # hot core, thinning to the ends
        t = min(i, len(path) - 1 - i) / float(max(len(path) * 0.4, 1))
        t = min(1.0, t)
        if t > 0.15:
            c.set(px, py, P.EMBER[4] if t > 0.55 else P.EMBER[3])
            if t > 0.7: c.set(px, py + 1, P.EMBER[2])
    for i in range(2 + v % 2):                             # side branches
        j = int(_rand(s + 7, i, 4, len(path) - 5))
        bx, by = path[j]
        d = 1 if i % 2 else -1
        for k in range(1, 4):
            c.set(bx + k, by + d * k, P.CHAR[0])
            c.set(bx + k, by + d * k - d, P.EMBER[2] if k < 3 else P.CHAR[1])
    return c

def cinder_embers(v=0):
    """A heap of live coals."""
    c = Canvas(22, 16)
    s = 340 + v * 9
    c.blob(11, 12, 7, P.CHAR[1], 0.24, s, 5)
    c.blob(11, 11, 5, P.CHAR[2], 0.22, s + 3, 5)
    for i in range(9):
        ex = 11 + int(_rand(s + 5, i, -6, 7)); ey = 12 + int(_rand(s + 7, i, -4, 3))
        if c.get(ex, ey) is not None:
            hot = [P.EMBER[3], P.EMBER[4], P.EMBER[2], P.HOT[2]][i % 4]
            c.set(ex, ey, hot)
            if i % 3 == 0: c.set(ex + 1, ey, P.EMBER[2])
    for i in range(3):                       # rising sparks
        c.set(11 + int(_rand(s + 11, i, -5, 6)), int(_rand(s + 13, i, 1, 6)), P.HOT[2])
    return _finish(c)



def cinder_vent(v=0):
    """A smoke vent: a stone collar and discrete rising puffs."""
    c = Canvas(22, 30)
    s = 350 + v * 7
    c.ellipse(11, 25, 8, 4, P.CINDER[3])                   # collar
    c.ellipse(11, 25, 6, 3, P.CHAR[2])
    c.ellipse(11, 24, 4, 2, P.CHAR[0])
    c.ellipse(11, 24, 2, 1, P.EMBER[3])
    for x in range(4, 19):                                 # lit rim, upper-left
        if c.get(x, 22) is not None and x < 12: c.set(x, 22, P.CINDER[5])
    puffs = [(11, 19, 4), (9, 14, 4), (13, 10, 3), (10, 6, 3), (12, 3, 2)]
    for i, (px, py, pr) in enumerate(puffs[: 4 + v % 2]):
        tone = P.CINDER[4] if i < 2 else P.CINDER[5]
        c.blob(px, py, pr, tone, 0.26, s + i * 5, 4)
        c.blob(px - 1, py - 1, max(1, pr - 2), P.CINDER[6], 0.22, s + 30 + i, 4)
    for i in range(3):                                     # embers riding the plume
        c.set(11 + int(_rand(s + 11, i, -5, 6)), int(_rand(s + 13, i, 8, 20)), P.EMBER[3])
    return _finish(c)

def cinder_brazier(v=0):
    """A small standing flame — the warm light source of a Cinder field."""
    c = Canvas(20, 30)
    s = 360 + v * 11
    c.rect(6, 20, 8, 6, P.IRON[2])            # bowl
    c.hline(5, 14, 20, P.IRON[4])
    c.rect(7, 21, 6, 3, P.CHAR[1])
    for k in (-1, 1):                          # legs
        c.line(10 + k * 3, 26, 10 + k * 5, 29, P.IRON[2])
    c.hline(4, 15, 29, P.IRON[1])
    flame = [(10, 16, 4), (8, 13, 3), (12, 14, 3), (10, 10, 3)]
    for i, (fx, fy, fr) in enumerate(flame):
        c.blob(fx, fy, fr, P.EMBER[3], 0.22, s + i, 4)
    c.blob(10, 15, 3, P.EMBER[4], 0.2, s + 7, 4)
    c.blob(10, 13, 2, P.HOT[2], 0.2, s + 9, 4)
    c.set(9, 6, P.HOT[1]); c.set(11, 7, P.HOT[2])
    return _finish(c)



def cinder_scorched(v=0):
    """A dead shrub — 2px twisted limbs so it survives at board scale."""
    c = Canvas(22, 26)
    s = 370 + v * 13
    for i in range(3 + v % 3):
        bx = 11 + int(_rand(s, i, -4, 5))
        h = 10 + int(_rand(s + 1, i, 0, 8))
        px, py = bx, 22
        for k in range(h):
            px += 1 if hash2(k, i, s + 3) > 0.72 else (-1 if hash2(k, i, s + 5) > 0.74 else 0)
            px = max(1, min(19, px))
            py -= 1
            tone = P.CHAR[2] if k < h - 3 else P.CHAR[1]
            c.set(px, py, tone); c.set(px + 1, py, P.CHAR[1])
            if k == h // 2:                                # a stubby side twig
                d = 1 if i % 2 else -1
                for j in range(1, 4):
                    c.set(px + d * j, py - j, P.CHAR[2]); c.set(px + d * j, py - j + 1, P.CHAR[1])
        c.set(px, py, P.EMBER[3]); c.set(px + 1, py, P.EMBER[2])
        c.set(px, py + 1, P.EMBER[1])
    c.rect(5, 21, 13, 3, P.CHAR[1])
    c.hline(6, 16, 21, P.CHAR[2])
    return _finish(c)

def grove_log(v=0):
    """A fallen mossy log — the forest floor remembers its elders."""
    c = Canvas(30, 16)
    s = 260 + v * 13
    # trunk lying at a slight diagonal
    for x in range(3, 27):
        t = (x - 3) / 24.0
        y = 9 + int(t * 2) + (1 if _rand(s, x) > 0.8 else 0)
        c.set(x, y - 2, P.WOOD[4])
        c.set(x, y - 1, P.WOOD[3])
        c.set(x, y, P.WOOD[2])
        c.set(x, y + 1, P.WOOD[1])
    # cut face at the near end: rings
    for k in range(4):
        c.set(4, 7 + k, P.WOOD[3] if k % 2 else P.WOOD[5 - 1])
    c.set(3, 8, P.WOOD[1]); c.set(3, 9, P.WOOD[1])
    # moss cap and a shelf mushroom
    for i in range(5):
        mx = 8 + int(_rand(s + 3, i, 0, 16)); my = 6 + int(_rand(s + 5, i, 0, 2))
        c.set(mx, my, P.GROVE[4]); c.set(mx + 1, my, P.GROVE[3])
    c.set(20, 6, P.BLOOM[1]); c.set(21, 6, P.BLOOM[2]); c.set(20, 5, P.BLOOM[2])
    return _finish(c)


def cinder_bones(v=0):
    """Charred remnants — a rib arc and a weathered skull-stone. Strange, not
    grim: the Cinder realm keeps its trophies."""
    c = Canvas(26, 18)
    s = 470 + v * 11
    bone = P.CREAM[1]
    lit = P.CREAM[2]
    # three rib arcs
    for i in range(3):
        bx = 4 + i * 6 + int(_rand(s, i, 0, 2))
        h = 8 + int(_rand(s + 1, i, 0, 4))
        for k in range(h):
            t = k / float(h)
            px = bx + int(3.0 * t * t)
            c.set(px, 15 - k, bone if t < 0.7 else lit)
            if k == 0: c.set(px, 15, P.CHAR[1])
    # a round skull-ish stone half-sunk beside them
    c.blob(20, 12, 4, bone, 0.2, s + 7, 5)
    c.set(19, 11, P.CHAR[1]); c.set(21, 11, P.CHAR[1])   # eye pits
    c.set(20, 14, P.CHAR[2])
    # scorch at the base, one live ember
    c.rect(3, 15, 20, 2, P.CHAR[1])
    c.set(9 + v * 2, 14, P.EMBER[2])
    return _finish(c)


GROVE_PROPS = {
    "tree": grove_tree, "root": grove_root, "vine": grove_vine, "flower": grove_flower,
    "mushroom": grove_mushroom, "grass": grove_grass, "stone": grove_stone,
    "glowplant": grove_glowplant, "detail": grove_detail, "log": grove_log,
}
CINDER_PROPS = {
    "burnt_tree": cinder_burnt_tree, "rock": cinder_rock, "debris": cinder_debris,
    "crack": cinder_crack, "embers": cinder_embers, "vent": cinder_vent,
    "brazier": cinder_brazier, "scorched": cinder_scorched, "bones": cinder_bones,
}
