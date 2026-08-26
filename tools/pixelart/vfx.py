"""A reusable Life/Fire effect library, authored as frame strips.

docs/ART_BIBLE.md forbids a giant bespoke sheet per spell, so this is a small
shared set every effect draws from: each entry is a horizontal strip of frames
on one canvas, played by the stage. The goal is the choreography rule from
CLAUDE.md — cause -> travel -> impact -> result — so effects come in three
shapes:

  burst    an impact that blooms and fades in place
  travel   a projectile with a nose and a tail
  aura     a lingering state that loops

Frames are drawn, not blurred: scale and count carry the motion, never alpha
fades between palette entries.
"""
import math

from . import palette as P
from .canvas import Canvas, hash2, value_noise

FRAMES = 6


def _strip(w, h, frames=FRAMES):
    return Canvas(w * frames, h), w, h


def _petal(c, ox, cx, cy, ang, dist, size, ramp, tone):
    px = cx + math.cos(ang) * dist
    py = cy + math.sin(ang) * dist * 0.72
    for k in range(int(size)):
        wdt = max(1, int(size) - k)
        for j in range(-wdt, wdt + 1):
            c.set(ox + int(px + math.cos(ang) * k), int(py + math.sin(ang) * k * 0.72 + j),
                  ramp[tone])


# --- Life -------------------------------------------------------------------


def _leaf(c, ox, x, y, ang, size, ramp):
    """One actual leaf: a pointed blade with a mid-rib, not a dot."""
    for k in range(size):
        wdt = int((size - k) * 0.55) if k > size * 0.4 else int(k * 0.8) + 1
        for j in range(-wdt, wdt + 1):
            px = x + math.cos(ang) * k - math.sin(ang) * j
            py = y + math.sin(ang) * k + math.cos(ang) * j
            c.set(ox + int(px), int(py), ramp[3] if j < 0 else ramp[2])
    for k in range(size):
        c.set(ox + int(x + math.cos(ang) * k), int(y + math.sin(ang) * k), ramp[4])


def leaf_burst():
    """Real leaves thrown outward and tumbling, not a green blob dissolving."""
    c, w, h = _strip(56, 56)
    for fi in range(FRAMES):
        ox = fi * w
        t = fi / float(FRAMES - 1)
        cx, cy = w // 2, h // 2
        for i in range(7):
            a = (i / 7.0) * math.tau + hash2(i, 0, 41) * 0.7
            d = 2 + t * 19
            spin = a + t * 2.2 + hash2(i, 1, 43) * 3.0
            size = max(3, int(8 - t * 3))
            _leaf(c, ox, cx + math.cos(a) * d, cy + math.sin(a) * d * 0.8, spin, size, P.LEAF)
        if t < 0.4:
            c.blob(ox + cx, cy, 8 * (1.0 - t * 2.2) + 2, P.SPORE[2], 0.3, 60 + fi, 4)
        for i in range(6):
            a = hash2(i, fi, 61) * math.tau
            d = 8 + t * 22
            c.set(ox + int(cx + math.cos(a) * d), int(cy + math.sin(a) * d * 0.7), P.SPORE[3])
    return c


def healing_ribbon():
    """A broad ribbon of green light winding up around the target."""
    c, w, h = _strip(44, 60)
    for fi in range(FRAMES):
        ox = fi * w
        t = fi / float(FRAMES - 1)
        cx = w // 2
        for k in range(46):
            u = k / 46.0
            y = int(h - 4 - u * (h - 12) - t * 6)
            if y < 2:
                break
            a = u * math.tau * 1.5 + t * math.tau
            radius = 15 - u * 6
            x = cx + int(math.cos(a) * radius)
            # Width follows the turn, so it reads as a flat ribbon twisting.
            band = 1 + int(abs(math.cos(a)) * 3)
            for j in range(-band, band + 1):
                c.set(ox + x + j, y, P.SPORE[2] if j < 0 else P.SPORE[1])
            c.set(ox + x, y, P.SPORE[3])
        for i in range(5):
            c.set(ox + cx + int((hash2(i, fi, 71) - 0.5) * 26),
                  h - 6 - int((hash2(i, fi, 73) + t) * 24) % (h - 10), P.CREAM[3])
    return c


def vine_growth():
    """A thick vine whipping out, throwing leaves as it goes."""
    c, w, h = _strip(64, 48)
    for fi in range(FRAMES):
        ox = fi * w
        t = fi / float(FRAMES - 1)
        reach = int(5 + t * (w - 10))
        y0 = h // 2
        for x in range(reach):
            yy = y0 + int(math.sin(x * 0.20 + t * 2.0) * 7 * (1.0 - x / float(w * 1.2)))
            for j in range(3):                       # a rope, not a hairline
                c.set(ox + x, yy + j, P.LEAF[3 if j == 0 else 2])
            c.set(ox + x, yy + 3, P.LEAF[1])
            if x % 11 == 5 and x < reach - 4:
                side = 1 if (x // 11) % 2 else -1
                for k in range(5):
                    wdt = 2 - abs(k - 2) // 2
                    for j in range(-wdt, wdt + 1):
                        c.set(ox + x + k, yy + side * (4 + k) + j, P.LEAF[3 if j < 0 else 2])
                c.set(ox + x + 4, yy + side * 8, P.LEAF[4])
        c.blob(ox + reach, y0 + 1, 4, P.LEAF[4], 0.28, 80 + fi, 4)
        c.blob(ox + reach, y0 + 1, 2, P.SPORE[3], 0.24, 84 + fi, 4)
    return c


def flower_pop():
    """A bloom opening: the visible result of a Life effect landing."""
    c, w, h = _strip(36, 36)
    for fi in range(FRAMES):
        ox = fi * w
        t = fi / float(FRAMES - 1)
        cx, cy = w // 2, h // 2
        r = 2 + t * 9
        for i in range(6):
            a = (i / 6.0) * math.tau + t * 0.4
            px = cx + math.cos(a) * r
            py = cy + math.sin(a) * r * 0.8
            c.blob(ox + int(px), int(py), max(1, 4 * t + 1), P.BLOOM[2], 0.24, 90 + i + fi, 4)
        c.disc(ox + cx, cy, max(1, int(3 * t) + 1), P.GOLD[3])
        if t > 0.5:
            for i in range(4):
                a = hash2(i, fi, 97) * math.tau
                c.set(ox + int(cx + math.cos(a) * (r + 4)), int(cy + math.sin(a) * (r + 3)),
                      P.CREAM[3])
    return c


# --- Fire -------------------------------------------------------------------


def ember_burst():
    """An impact that blooms and then throws embers, rather than vanishing."""
    c, w, h = _strip(56, 56)
    for fi in range(FRAMES):
        ox = fi * w
        t = fi / float(FRAMES - 1)
        cx, cy = w // 2, h // 2
        core = max(0.0, 1.0 - t * 1.25)
        if core > 0.02:
            c.blob(ox + cx, cy, 4 + core * 12, P.EMBER[2], 0.34, 100 + fi, 6)
            c.blob(ox + cx, cy, 3 + core * 8, P.EMBER[4], 0.30, 110 + fi, 5)
            c.blob(ox + cx, cy, 1 + core * 4, P.HOT[3], 0.26, 120 + fi, 4)
        ring = 5 + t * 20
        for a_i in range(56):                         # a shock ring, thinning
            a = (a_i / 56.0) * math.tau
            if hash2(a_i, fi, 133) < t * 0.55:
                continue
            c.set(ox + int(cx + math.cos(a) * ring), int(cy + math.sin(a) * ring * 0.8),
                  P.EMBER[4] if t < 0.5 else P.EMBER[2])
        for i in range(14):                           # embers riding outward
            a = hash2(i, 0, 131) * math.tau
            d = 4 + t * (16 + hash2(i, 1, 137) * 14)
            px = int(cx + math.cos(a) * d)
            py = int(cy + math.sin(a) * d * 0.75 - t * 7)
            c.set(ox + px, py, P.EMBER[4] if hash2(i, fi, 139) > 0.5 else P.HOT[1])
            if t < 0.6:
                c.set(ox + px, py + 1, P.EMBER[2])
    return c


def fire_bolt():
    """A bolt, drawn stationary and flickering.

    The stage moves a projectile itself, so a strip that also travels would
    double the motion. What the frames carry is the flame licking off it.
    """
    c, w, h = _strip(52, 28)
    for fi in range(FRAMES):
        ox = fi * w
        cy = h // 2
        nose = w - 8
        for k in range(38):
            x = nose - k
            if x < 2:
                break
            taper = 1.0 - k / 38.0
            r = max(1, int(1 + taper * 7))
            wob = int(math.sin(k * 0.42 + fi * 1.1) * (1.0 - taper) * 4)
            tone = P.HOT[4] if k < 3 else (P.HOT[2] if k < 7 else
                   (P.EMBER[4] if k < 15 else (P.EMBER[3] if k < 26 else P.EMBER[1])))
            for j in range(-r, r + 1):
                if abs(j) > r - 1 and hash2(x, j + fi * 5, 151) < 0.42:
                    continue
                c.set(ox + x, cy + j + wob, tone)
        for i in range(6):                            # sparks shedding backward
            c.set(ox + nose - int(hash2(i, fi, 157) * 34),
                  cy + int((hash2(i, fi, 163) - 0.5) * 16), P.HOT[2])
    return c


def flame_cone():
    """A breath weapon: what makes a dragon's attack differ from a deer's."""
    c, w, h = _strip(72, 48)
    for fi in range(FRAMES):
        ox = fi * w
        t = fi / float(FRAMES - 1)
        reach = int(8 + t * (w - 14))
        cy = h // 2
        for x in range(reach):
            u = x / float(max(reach, 1))
            spread = int(2 + u * 17)
            for j in range(-spread, spread + 1):
                edge = abs(j) / float(max(spread, 1))
                if hash2(x, j + fi * 7, 163) < 0.22 + edge * 0.5:
                    continue
                tone = P.HOT[3] if u < 0.16 else (P.EMBER[4] if edge < 0.45 else
                                                  (P.EMBER[3] if edge < 0.78 else P.EMBER[1]))
                c.set(ox + x, cy + j, tone)
        for i in range(7):
            c.set(ox + reach - int(hash2(i, fi, 167) * 14),
                  cy + int((hash2(i, fi, 173) - 0.5) * 30), P.HOT[2])
    return c


def bloom_cone():
    """A Life breath weapon: a cone of leaves, petals and spores.

    Life needed its own version of the dragon beat — reusing the vine gave a
    Garden Dragon a thin whip where a Blazewing Drake got a wall of fire.
    """
    c, w, h = _strip(72, 48)
    for fi in range(FRAMES):
        ox = fi * w
        t = fi / float(FRAMES - 1)
        reach = int(8 + t * (w - 14))
        cy = h // 2
        for x in range(reach):
            u = x / float(max(reach, 1))
            spread = int(2 + u * 17)
            for j in range(-spread, spread + 1):
                edge = abs(j) / float(max(spread, 1))
                if hash2(x, j + fi * 7, 251) < 0.30 + edge * 0.5:
                    continue
                tone = P.SPORE[3] if u < 0.18 else (P.LEAF[4] if edge < 0.42 else
                                                    (P.LEAF[3] if edge < 0.76 else P.LEAF[1]))
                c.set(ox + x, cy + j, tone)
        for i in range(9):                       # petals riding the gust
            px = reach - int(hash2(i, fi, 257) * 26)
            py = cy + int((hash2(i, fi, 263) - 0.5) * 32)
            petal = [P.BLOOM[2], P.CREAM[2], P.SPORE[3]][i % 3]
            c.set(ox + px, py, petal)
            c.set(ox + px + 1, py, petal)
        for i in range(5):
            c.set(ox + reach - int(hash2(i, fi, 269) * 12),
                  cy + int((hash2(i, fi, 271) - 0.5) * 34), P.SPORE[3])
    return c


def smoke_puff():
    c, w, h = _strip(40, 44)
    for fi in range(FRAMES):
        ox = fi * w
        t = fi / float(FRAMES - 1)
        cx = w // 2
        for i in range(4):
            py = int(h - 6 - t * 26 - i * 6)
            pr = 3 + t * 5 + i * 0.6
            px = cx + int((value_noise(i * 9, fi * 5, 6, 181) - 0.5) * 12)
            tone = P.CINDER[4] if i < 2 else P.CINDER[5]
            c.blob(ox + px, py, pr, tone, 0.3, 181 + i + fi, 5)
            c.blob(ox + px - 1, py - 1, max(1, pr - 2), P.CINDER[6], 0.26, 191 + i + fi, 4)
    return c


# --- shared -----------------------------------------------------------------

def impact_sparks(element="fire"):
    ramp = P.HOT if element == "fire" else P.SPORE
    c, w, h = _strip(40, 40)
    for fi in range(FRAMES):
        ox = fi * w
        t = fi / float(FRAMES - 1)
        cx, cy = w // 2, h // 2
        for i in range(10):
            a = (i / 10.0) * math.tau + hash2(i, 0, 199) * 0.6
            d0 = 2 + t * 16
            for k in range(3):
                px = int(cx + math.cos(a) * (d0 + k * 2))
                py = int(cy + math.sin(a) * (d0 + k * 2) * 0.8)
                c.set(ox + px, py, ramp[min(len(ramp) - 1, 3 - k)])
        if t < 0.4:
            c.disc(ox + cx, cy, int(5 * (1.0 - t * 2.2)) + 1, ramp[min(len(ramp) - 1, 4)])
    return c


def hit_flash():
    """A white-hot ring: the universal 'that connected' read."""
    c, w, h = _strip(56, 56)
    for fi in range(FRAMES):
        ox = fi * w
        t = fi / float(FRAMES - 1)
        cx, cy = w // 2, h // 2
        r = 4 + t * 22
        for a_i in range(64):
            a = (a_i / 64.0) * math.tau
            if hash2(a_i, fi, 211) < t * 0.5:
                continue
            px = int(cx + math.cos(a) * r)
            py = int(cy + math.sin(a) * r * 0.82)
            c.set(ox + px, py, P.HOT[4] if t < 0.4 else P.HOT[2])
            c.set(ox + px, py + 1, P.HOT[1])
    return c


def rune(element):
    """A rune that turns under a caster: the 'cause' beat of a spell."""
    ramp = P.SPORE if element == "life" else P.EMBER
    c, w, h = _strip(56, 32)
    for fi in range(FRAMES):
        ox = fi * w
        t = fi / float(FRAMES - 1)
        cx, cy = w // 2, h // 2
        spin = t * math.tau / 6.0
        for ring, rad in ((0, 22), (1, 15)):
            for a_i in range(48):
                a = (a_i / 48.0) * math.tau + (spin if ring == 0 else -spin)
                if (a_i + ring * 3) % 5 == 0:
                    continue
                c.set(ox + int(cx + math.cos(a) * rad), int(cy + math.sin(a) * rad * 0.42),
                      ramp[2 if ring == 0 else 1])
        for k in range(6):                            # a turning glyph
            a = (k / 6.0) * math.tau + spin * 2.0
            c.set(ox + int(cx + math.cos(a) * 8), int(cy + math.sin(a) * 8 * 0.5), ramp[3])
        c.disc(ox + cx, cy, 2, ramp[min(len(ramp) - 1, 3)])
    return c


def heart_strike():
    """The Heart taking a hit: a crack of red light."""
    c, w, h = _strip(64, 64)
    for fi in range(FRAMES):
        ox = fi * w
        t = fi / float(FRAMES - 1)
        cx, cy = w // 2, h // 2
        for i in range(7):
            a = hash2(i, 0, 223) * math.tau
            length = int(8 + t * 22)
            for k in range(length):
                px = int(cx + math.cos(a) * k)
                py = int(cy + math.sin(a) * k * 0.85)
                tone = P.HEART[4] if k < 4 else (P.HEART[3] if k < length * 0.6 else P.HEART[1])
                c.set(ox + px, py, tone)
        if t < 0.5:
            c.disc(ox + cx, cy, int(9 * (1.0 - t * 1.8)) + 2, P.HEART[4])
    return c


def fusion_core():
    """Two creatures becoming one: a bright core drawing rings inward."""
    c, w, h = _strip(64, 64)
    for fi in range(FRAMES):
        ox = fi * w
        t = fi / float(FRAMES - 1)
        cx, cy = w // 2, h // 2
        pull = 1.0 - t
        for ring in range(3):
            rad = (8 + ring * 8) * pull + 4
            for a_i in range(40):
                a = (a_i / 40.0) * math.tau + t * math.tau * (1 + ring * 0.4)
                if a_i % 4 == 0:
                    continue
                c.set(ox + int(cx + math.cos(a) * rad), int(cy + math.sin(a) * rad * 0.8),
                      P.GOLD[3] if ring == 0 else P.AETHER[3 - ring])
        c.disc(ox + cx, cy, int(3 + t * 9), P.GOLD[4])
        c.disc(ox + cx, cy, int(1 + t * 5), P.HOT[4])
    return c


def summon_portal(element):
    """Where a creature arrives from."""
    ramp = P.SPORE if element == "life" else P.EMBER
    c, w, h = _strip(64, 40)
    for fi in range(FRAMES):
        ox = fi * w
        t = fi / float(FRAMES - 1)
        cx, cy = w // 2, h - 12
        rx = 6 + t * 22
        ry = rx * 0.34
        for a_i in range(72):
            a = (a_i / 72.0) * math.tau
            c.set(ox + int(cx + math.cos(a) * rx), int(cy + math.sin(a) * ry), ramp[2])
            c.set(ox + int(cx + math.cos(a) * (rx - 2)), int(cy + math.sin(a) * (ry - 1)), ramp[1])
        for i in range(8):                            # light rising out of it
            u = hash2(i, fi, 229)
            c.set(ox + int(cx + (u - 0.5) * rx * 1.7), int(cy - u * t * 26), ramp[3])
    return c


LIBRARY = {
    "leaf_burst": leaf_burst, "healing_ribbon": healing_ribbon,
    "vine_growth": vine_growth, "flower_pop": flower_pop,
    "rune_life": lambda: rune("life"), "summon_portal_life": lambda: summon_portal("life"),
    "sparks_life": lambda: impact_sparks("life"),
    "bloom_cone": bloom_cone,
    "ember_burst": ember_burst, "fire_bolt": fire_bolt, "flame_cone": flame_cone,
    "smoke_puff": smoke_puff,
    "rune_fire": lambda: rune("fire"), "summon_portal_fire": lambda: summon_portal("fire"),
    "sparks_fire": lambda: impact_sparks("fire"),
    "hit_flash": hit_flash, "heart_strike": heart_strike, "fusion_core": fusion_core,
}


# --- spell card art ---------------------------------------------------------
#
# Spells never had board sprites, so their cards fell back to a placeholder
# sigil. These are small single-frame scenes, authored rather than generated:
# a spell's art only has to say what it does at card size.

def spell_art(kind):
    c = Canvas(72, 72)
    s = 9000 + sum(ord(ch) for ch in kind)
    if kind == "grow":
        for i in range(5):                              # a sprout opening
            a = -math.pi / 2 + (i - 2) * 0.42
            for k in range(4, 20):
                px = int(36 + math.cos(a) * k)
                py = int(52 + math.sin(a) * k)
                c.set(px, py, P.LEAF[3] if k < 14 else P.LEAF[4])
                c.set(px + 1, py, P.LEAF[2])
        c.blob(36, 30, 9, P.SPORE[2], 0.3, s, 5)
        c.blob(34, 28, 5, P.SPORE[3], 0.26, s + 3, 4)
        for i in range(9):
            c.set(int(36 + (hash2(i, 0, s + 5) - 0.5) * 52),
                  int(30 + (hash2(i, 1, s + 7) - 0.5) * 44), P.CREAM[3])
        c.rect(4, 58, 64, 10, P.GROVE[2])
        c.hline(4, 67, 58, P.GROVE[4])
    elif kind == "warm_sun":
        c.rect(0, 44, 72, 28, P.GROVE[3])               # meadow
        c.hline(0, 71, 44, P.GROVE[5])
        for i in range(16):
            c.set(int(hash2(i, 0, s) * 72), 48 + int(hash2(i, 1, s + 3) * 20), P.LEAF[3])
        c.disc(36, 26, 13, P.GOLD[3])                   # sun
        c.disc(36, 26, 10, P.GOLD[4])
        c.disc(34, 24, 6, P.HOT[4])
        for i in range(12):
            a = (i / 12.0) * math.tau
            for k in range(16, 23):
                c.set(int(36 + math.cos(a) * k), int(26 + math.sin(a) * k), P.GOLD[2])
    elif kind == "little_flame":
        c.rect(0, 52, 72, 20, P.CHAR[1])
        for i, (fx, fy, fr) in enumerate([(36, 44, 11), (31, 34, 8), (40, 32, 7), (36, 24, 6)]):
            c.blob(fx, fy, fr, P.EMBER[3], 0.24, s + i * 5, 5)
        c.blob(36, 40, 7, P.EMBER[4], 0.22, s + 21, 4)
        c.blob(36, 34, 4, P.HOT[2], 0.20, s + 27, 4)
        c.blob(35, 28, 2, P.HOT[4], 0.18, s + 31, 4)
        for i in range(8):
            c.set(int(36 + (hash2(i, 0, s + 9) - 0.5) * 40), int(hash2(i, 1, s + 11) * 26), P.HOT[2])
    else:                                                # dragon_breath
        c.rect(0, 54, 72, 18, P.CHAR[1])
        for x in range(6, 70):                           # a blast crossing the card
            u = (x - 6) / 63.0
            spread = int(3 + u * 18)
            for j in range(-spread, spread + 1):
                edge = abs(j) / float(max(spread, 1))
                if hash2(x, j, s) < 0.26 + edge * 0.52:
                    continue
                tone = P.HOT[3] if u < 0.18 else (P.EMBER[4] if edge < 0.44 else
                       (P.EMBER[3] if edge < 0.78 else P.EMBER[1]))
                c.set(x, 34 + j, tone)
        for i in range(10):
            c.set(int(20 + hash2(i, 0, s + 13) * 48), int(34 + (hash2(i, 1, s + 17) - 0.5) * 40),
                  P.HOT[2])
    return c
