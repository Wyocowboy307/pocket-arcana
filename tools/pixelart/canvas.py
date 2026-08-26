"""Deterministic pixel-drawing primitives.

Everything an asset needs is here so the build script reads like a description
of the art rather than a wall of PIL calls. Two rules the whole kit obeys:

* No anti-aliasing and no blending between palette entries. Shading is ordered
  dithering between two ramp indices, because a blend of two palette colours is
  not a palette colour.
* Alpha is binary. A soft edge on a sprite reads as a halo once Godot scales it.

Canvas.wrap makes drawing wrap around the edges, which is how the ground tiles
come out seamless.
"""
from PIL import Image

from . import palette

# 4x4 ordered dither. Threshold t in 0..1 decides how much of `hi` shows.
BAYER4 = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]


def hash2(x, y, seed=0):
    """Stable value hash -> 0.0..1.0. Same coords always give the same result."""
    h = (int(x) * 374761393 + int(y) * 668265263 + int(seed) * 2147483647) & 0xFFFFFFFF
    h = (h ^ (h >> 13)) * 1274126177 & 0xFFFFFFFF
    h = h ^ (h >> 16)
    return (h & 0xFFFFFF) / float(0xFFFFFF)


def value_noise(x, y, cell, seed=0):
    """Smoothed lattice noise, for organic edges that still land on whole pixels."""
    fx, fy = x / float(cell), y / float(cell)
    x0, y0 = int(fx // 1), int(fy // 1)
    tx, ty = fx - x0, fy - y0
    tx = tx * tx * (3 - 2 * tx)
    ty = ty * ty * (3 - 2 * ty)
    n00 = hash2(x0, y0, seed);       n10 = hash2(x0 + 1, y0, seed)
    n01 = hash2(x0, y0 + 1, seed);   n11 = hash2(x0 + 1, y0 + 1, seed)
    a = n00 + (n10 - n00) * tx
    b = n01 + (n11 - n01) * tx
    return a + (b - a) * ty


class Canvas:
    def __init__(self, w, h, wrap=False):
        self.w, self.h = w, h
        self.wrap = wrap
        self.px = [[None] * w for _ in range(h)]   # None = transparent

    # --- addressing --------------------------------------------------------
    def _xy(self, x, y):
        x, y = int(x), int(y)
        if self.wrap:
            return x % self.w, y % self.h
        if x < 0 or y < 0 or x >= self.w or y >= self.h:
            return None
        return x, y

    def set(self, x, y, colour):
        at = self._xy(x, y)
        if at is None:
            return
        self.px[at[1]][at[0]] = colour

    def get(self, x, y):
        at = self._xy(x, y)
        if at is None:
            return None
        return self.px[at[1]][at[0]]

    # --- shapes ------------------------------------------------------------
    def fill(self, colour):
        for y in range(self.h):
            for x in range(self.w):
                self.px[y][x] = colour

    def rect(self, x, y, w, h, colour):
        for yy in range(int(y), int(y + h)):
            for xx in range(int(x), int(x + w)):
                self.set(xx, yy, colour)

    def frame(self, x, y, w, h, colour):
        for xx in range(int(x), int(x + w)):
            self.set(xx, y, colour); self.set(xx, y + h - 1, colour)
        for yy in range(int(y), int(y + h)):
            self.set(x, yy, colour); self.set(x + w - 1, yy, colour)

    def hline(self, x0, x1, y, colour):
        if x1 < x0: x0, x1 = x1, x0
        for x in range(int(x0), int(x1) + 1):
            self.set(x, y, colour)

    def vline(self, x, y0, y1, colour):
        if y1 < y0: y0, y1 = y1, y0
        for y in range(int(y0), int(y1) + 1):
            self.set(x, y, colour)

    def line(self, x0, y0, x1, y1, colour):
        """Bresenham — no anti-aliasing anywhere in this kit."""
        x0, y0, x1, y1 = int(x0), int(y0), int(x1), int(y1)
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx + dy
        while True:
            self.set(x0, y0, colour)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy: err += dy; x0 += sx
            if e2 <= dx: err += dx; y0 += sy

    def disc(self, cx, cy, r, colour):
        r2 = r * r
        for y in range(int(cy - r) - 1, int(cy + r) + 2):
            for x in range(int(cx - r) - 1, int(cx + r) + 2):
                dx, dy = x - cx, y - cy
                if dx * dx + dy * dy <= r2:
                    self.set(x, y, colour)

    def ellipse(self, cx, cy, rx, ry, colour):
        for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
            for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
                dx = (x - cx) / float(max(rx, 0.001))
                dy = (y - cy) / float(max(ry, 0.001))
                if dx * dx + dy * dy <= 1.0:
                    self.set(x, y, colour)

    def blob(self, cx, cy, r, colour, wobble=0.30, seed=0, cell=5):
        """A disc with an organic, whole-pixel edge. The workhorse for foliage
        clumps, ember pools and rock masses."""
        rr = r * (1.0 + wobble)
        for y in range(int(cy - rr) - 2, int(cy + rr) + 3):
            for x in range(int(cx - rr) - 2, int(cx + rr) + 3):
                dx, dy = x - cx, y - cy
                d = (dx * dx + dy * dy) ** 0.5
                edge = r * (1.0 + (value_noise(x, y, cell, seed) - 0.5) * 2.0 * wobble)
                if d <= edge:
                    self.set(x, y, colour)

    def poly(self, points, colour):
        """Even-odd scanline fill of a closed polygon."""
        if len(points) < 3:
            return
        ys = [p[1] for p in points]
        for y in range(int(min(ys)), int(max(ys)) + 1):
            xs = []
            for i in range(len(points)):
                ax, ay = points[i]
                bx, by = points[(i + 1) % len(points)]
                if (ay <= y < by) or (by <= y < ay):
                    xs.append(ax + (y - ay) * (bx - ax) / float(by - ay))
            xs.sort()
            for i in range(0, len(xs) - 1, 2):
                self.hline(xs[i], xs[i + 1], y, colour)

    # --- shading -----------------------------------------------------------
    def dither(self, x, y, lo, hi, t):
        """Place lo or hi at (x,y) so that a region reads as t of the way to hi."""
        thresh = (BAYER4[int(y) % 4][int(x) % 4] + 0.5) / 16.0
        self.set(x, y, hi if t > thresh else lo)

    def dither_rect(self, x, y, w, h, lo, hi, t):
        for yy in range(int(y), int(y + h)):
            for xx in range(int(x), int(x + w)):
                self.dither(xx, yy, lo, hi, t)

    def shade_where(self, lo, hi, t, mask):
        """Dither lo->hi over every pixel where mask(x, y) is true."""
        for y in range(self.h):
            for x in range(self.w):
                if mask(x, y):
                    self.dither(x, y, lo, hi, t)

    def recolour(self, old, new):
        for y in range(self.h):
            for x in range(self.w):
                if self.px[y][x] == old:
                    self.px[y][x] = new

    # --- outline -----------------------------------------------------------
    def outline(self, colour=None, diagonal=False):
        """Trace a 1px border around every opaque cluster. The bible's single
        strongest identity cue: a bold dark rim all the way around."""
        colour = colour or palette.INK
        neigh = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        if diagonal:
            neigh += [(-1, -1), (1, -1), (-1, 1), (1, 1)]
        add = []
        for y in range(self.h):
            for x in range(self.w):
                if self.px[y][x] is not None:
                    continue
                for dx, dy in neigh:
                    at = self._xy(x + dx, y + dy)
                    if at and self.px[at[1]][at[0]] is not None and self.px[at[1]][at[0]] != colour:
                        add.append((x, y))
                        break
        for x, y in add:
            self.set(x, y, colour)

    def inner_outline(self, colour=None, diagonal=False):
        """Darken the rim *inside* the silhouette. Used when the sprite already
        fills its canvas and an outward outline would be clipped."""
        colour = colour or palette.INK
        neigh = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        if diagonal:
            neigh += [(-1, -1), (1, -1), (-1, 1), (1, 1)]
        edge = []
        for y in range(self.h):
            for x in range(self.w):
                if self.px[y][x] is None:
                    continue
                for dx, dy in neigh:
                    at = self._xy(x + dx, y + dy)
                    if at is None or self.px[at[1]][at[0]] is None:
                        edge.append((x, y))
                        break
        for x, y in edge:
            self.set(x, y, colour)

    def drop_shadow(self, colour, dx=0, dy=1):
        """A hard offset shadow under the silhouette, opaque and palette-legal."""
        add = []
        for y in range(self.h):
            for x in range(self.w):
                if self.px[y][x] is not None and self.get(x + dx, y + dy) is None:
                    add.append((x + dx, y + dy))
        for x, y in add:
            self.set(x, y, colour)

    # --- composition -------------------------------------------------------
    def paste(self, other, ox, oy, skip=None):
        for y in range(other.h):
            for x in range(other.w):
                c = other.px[y][x]
                if c is None or (skip is not None and c == skip):
                    continue
                self.set(ox + x, oy + y, c)

    def crop(self, x, y, w, h):
        out = Canvas(w, h)
        for yy in range(h):
            for xx in range(w):
                out.px[yy][xx] = self.get(x + xx, y + yy)
        return out

    def flip_h(self):
        out = Canvas(self.w, self.h, self.wrap)
        for y in range(self.h):
            for x in range(self.w):
                out.px[y][x] = self.px[y][self.w - 1 - x]
        return out

    def bbox(self):
        xs, ys = [], []
        for y in range(self.h):
            for x in range(self.w):
                if self.px[y][x] is not None:
                    xs.append(x); ys.append(y)
        if not xs:
            return None
        return min(xs), min(ys), max(xs) + 1, max(ys) + 1

    def is_empty(self):
        return self.bbox() is None

    # --- output ------------------------------------------------------------
    def image(self):
        im = Image.new("RGBA", (self.w, self.h), (0, 0, 0, 0))
        data = []
        for y in range(self.h):
            for x in range(self.w):
                c = self.px[y][x]
                data.append((0, 0, 0, 0) if c is None else (c[0], c[1], c[2], 255))
        im.putdata(data)
        return im

    def save(self, path):
        import os
        os.makedirs(os.path.dirname(path), exist_ok=True)
        self.image().save(path)
        return path
