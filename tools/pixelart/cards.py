"""Card frames — the thing the player actually reads.

A card is built in three pieces so the art inside can change without
regenerating the frame:

  plate    opaque backing, including the recessed art window
  frame    border, bevel and corner ornament, transparent over the window
  (art)    the creature/place sprite, drawn between the two by the renderer

Numbers are drawn in code, because they change every turn.

Two things make a card feel premium rather than like a UI box:

* it is mostly ART. A thin trim and a small stat strip; the illustration gets
  everything else. A wide coloured border with empty ribbons reads as a
  placeholder no matter how well the border itself is drawn.
* one shared dark pewter trim across both elements, with only a thin accent
  line carrying the element. Colouring the whole frame green or red made the
  two sides look like different games.

The art window sits over an element-tinted backdrop so a sprite with its own
outline still separates from the card behind it.
"""
from . import palette as P
from .canvas import Canvas, hash2, value_noise

# Board cards: what a played creature looks like lying on the battlefield.
BOARD_W, BOARD_H = 118, 146
PLACE_W, PLACE_H = 92, 100
# Hand cards must fit inside main_v2's HAND_H row, or the frame is clipped and
# the element footer and stat badges fall off the bottom of the screen.
HAND_W, HAND_H = 148, 158
# Regions, shared with scripts/ui/v2/card_v2.gd. If these move, move them there.
NAME_Y, NAME_H = 5, 20
ROLE_Y, ROLE_H = 27, 17
ART_Y, ART_H = 46, 62
FOOT_Y, FOOT_H = 110, 17
RULES_Y = 129

SCHEME = {
    "life":    {"ramp": P.GROVE, "accent": P.LEAF,  "trim": P.WOOD,  "glow": P.SPORE},
    "fire":    {"ramp": P.CINDER, "accent": P.EMBER, "trim": P.IRON, "glow": P.HOT},
    "neutral": {"ramp": P.STONE, "accent": P.DUST,  "trim": P.IRON,  "glow": P.CREAM},
}


def _trim(c, x, y, w, h, accent):
    """Dark pewter edge, lit upper-left, with a thin element accent inside.
    Shared across both elements so the two sides read as one game."""
    c.frame(x, y, w, h, P.INK)
    c.frame(x + 1, y + 1, w - 2, h - 2, P.IRON[3])
    for i in range(x + 2, x + w - 2):
        c.set(i, y + 1, P.IRON[4])
        c.set(i, y + h - 2, P.IRON[1])
    for j in range(y + 2, y + h - 2):
        c.set(x + 1, j, P.IRON[4])
        c.set(x + w - 2, j, P.IRON[1])
    c.frame(x + 2, y + 2, w - 4, h - 4, P.INK)
    c.frame(x + 3, y + 3, w - 6, h - 6, P.IRON[2])
    for i in range(x + 4, x + w - 4):
        c.set(i, y + h - 4, accent)
        c.set(i, y + h - 5, accent)


def _corner_brackets(c, w, h, accent):
    """Small metal brackets. Cheap ornament, big premium payoff."""
    for cx, cy, dx, dy in ((0, 0, 1, 1), (w - 1, 0, -1, 1),
                           (0, h - 1, 1, -1), (w - 1, h - 1, -1, -1)):
        for k in range(7):
            c.set(cx + dx * k, cy + dy * 1, P.IRON[4] if k < 4 else P.IRON[3])
            c.set(cx + dx * 1, cy + dy * k, P.IRON[4] if k < 4 else P.IRON[3])
        c.set(cx + dx * 2, cy + dy * 2, accent)
        c.set(cx + dx * 3, cy + dy * 2, P.IRON[2])
        c.set(cx + dx * 2, cy + dy * 3, P.IRON[2])


def art_backdrop(c, x, y, w, h, element, seed):
    """What sits behind the illustration: an element-tinted pool, dark at the
    edges so an outlined sprite still separates from it."""
    s = SCHEME.get(element, SCHEME["neutral"])
    ramp, accent, glow = s["ramp"], s["accent"], s["glow"]
    cx, cy = x + w / 2.0, y + h / 2.0
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            dx = (xx - cx) / (w / 2.0)
            dy = (yy - cy) / (h / 2.0)
            d = min(1.0, (dx * dx + dy * dy) ** 0.5)
            n = value_noise(xx, yy, 11, seed) * 0.22
            t = max(0.0, 1.0 - d + n - 0.18)
            idx = 0 if t < 0.34 else (1 if t < 0.68 else 2)
            c.set(xx, yy, ramp[idx])
    # A faint element motif, low contrast, so the backdrop is not dead space.
    if element == "life":
        for i in range(7):
            bx = x + int(hash2(i, 0, seed + 3) * w)
            by = y + int(hash2(i, 1, seed + 5) * h)
            c.blob(bx, by, 4 + hash2(i, 2, seed + 7) * 5, ramp[2], 0.34, seed + i * 9, 5)
        for i in range(4):
            gx = x + int(hash2(i, 3, seed + 11) * w)
            gy = y + int(hash2(i, 4, seed + 13) * h)
            c.set(gx, gy, glow[1]); c.set(gx + 1, gy, glow[0])
    elif element == "fire":
        for i in range(6):
            bx = x + int(hash2(i, 0, seed + 3) * w)
            by = y + int(h * 0.55 + hash2(i, 1, seed + 5) * h * 0.45)
            c.blob(bx, by, 3 + hash2(i, 2, seed + 7) * 5, accent[0], 0.34, seed + i * 9, 5)
        for i in range(6):
            ex = x + int(hash2(i, 3, seed + 11) * w)
            ey = y + int(hash2(i, 4, seed + 13) * h * 0.8)
            c.set(ex, ey, accent[1])


def plate(element, w=BOARD_W, h=BOARD_H, art_rect=None):
    """The opaque backing of a card: trim, art backdrop, stat strip."""
    s = SCHEME.get(element, SCHEME["neutral"])
    accent = s["accent"][2]
    c = Canvas(w, h)
    seed = 4200 + sum(ord(ch) for ch in element)
    c.rect(0, 0, w, h, P.IRON[1])
    ax, ay, aw, ah = art_rect if art_rect else (4, 4, w - 8, h - 26)
    art_backdrop(c, ax, ay, aw, ah, element, seed)
    c.rect(ax, ay + ah, aw, h - 4 - (ay + ah), P.UI_DARK[1])      # stat strip
    for x in range(ax, ax + aw):
        c.set(x, ay + ah, P.INK)
        c.set(x, ay + ah + 1, P.UI_DARK[3])
    _trim(c, 0, 0, w, h, accent)
    _corner_brackets(c, w, h, accent)
    return c


def board_card(element, w=BOARD_W, h=BOARD_H):
    """Frame overlay drawn on top of the live art, so the illustration sits
    inside the card rather than on it. Transparent over the art window."""
    s = SCHEME.get(element, SCHEME["neutral"])
    accent = s["accent"][2]
    c = Canvas(w, h)
    _trim(c, 0, 0, w, h, accent)
    _corner_brackets(c, w, h, accent)
    ax, ay, aw, ah = 4, 4, w - 8, h - 26
    # Inner shadow at the top of the window: the illustration sits *in* a recess.
    for x in range(ax, ax + aw):
        c.set(x, ay, P.INK)
    for j in range(ay, ay + ah):
        c.set(ax, j, P.INK)
        c.set(ax + aw - 1, j, P.INK)
    c.hline(ax, ax + aw - 1, ay + ah - 1, P.INK)
    _ornament(c, element, w - 12, 10, flip=True)
    return c


def _ornament(c, element, x, y, flip=False):
    """A small element motif. Identity without text."""
    if element == "life":
        for k in range(5):
            w = 2 - abs(k - 2) // 2
            for j in range(-w, w + 1):
                c.set(x + (-k if flip else k), y + j, P.LEAF[3 if j < 0 else 2])
        c.set(x + (-2 if flip else 2), y, P.LEAF[4])
    elif element == "fire":
        for k, w in enumerate((0, 1, 2, 2, 1)):
            for j in range(-w, w + 1):
                c.set(x + j, y + 4 - k, P.EMBER[3 if k > 2 else 4])
        c.set(x, y + 1, P.HOT[2])
    else:
        c.disc(x, y, 2, P.DUST[2])


def stat_gem(kind, size=24):
    """A badge for a live number, meant to overlap the card edge."""
    ramps = {"cost": P.AETHER, "power": P.GOLD, "health": P.HEART,
             "presence": P.SPORE, "attack": P.EMBER}
    ramp = ramps.get(kind, P.STONE)
    c = Canvas(size, size)
    r = size // 2 - 1
    cx = cy = size // 2
    c.disc(cx, cy, r, P.INK)
    c.disc(cx, cy, r - 1, P.IRON[3])            # metal socket
    c.disc(cx, cy, r - 3, P.INK)
    c.disc(cx, cy, r - 4, ramp[1])
    c.disc(cx, cy, r - 5, ramp[2])
    c.disc(cx - 1, cy - 1, max(1, r - 7), ramp[3])
    import math
    for a in range(0, 360, 60):                 # rivets on the socket
        rad = math.radians(a)
        c.set(int(cx + math.cos(rad) * (r - 2)), int(cy + math.sin(rad) * (r - 2)), P.IRON[4])
    return c


def place_card(element):
    """Places read as built things: wider, shorter, heavier foundation."""
    s = SCHEME.get(element, SCHEME["neutral"])
    accent = s["accent"][2]
    c = Canvas(PLACE_W, PLACE_H)
    seed = 4400 + sum(ord(ch) for ch in element)
    c.rect(0, 0, PLACE_W, PLACE_H, P.IRON[1])
    art_backdrop(c, 4, 4, PLACE_W - 8, PLACE_H - 22, element, seed)
    c.rect(4, PLACE_H - 18, PLACE_W - 8, 14, P.UI_DARK[1])
    for x in range(4, PLACE_W - 4):
        c.set(x, PLACE_H - 18, P.INK)
        c.set(x, PLACE_H - 17, P.UI_DARK[3])
        if x % 4 == 0:
            c.set(x, PLACE_H - 6, P.IRON[3])    # foundation hatching
    _trim(c, 0, 0, PLACE_W, PLACE_H, accent)
    _corner_brackets(c, PLACE_W, PLACE_H, accent)
    return c


def hand_card(element, role="creature"):
    """The frame the player reads before committing.

    Every region the renderer writes into is recessed here, so text always
    lands on a dark plate and stays legible over any art: name ribbon, role
    ribbon, art window, PLAY ON strip and rules panel.
    """
    sc = SCHEME.get(element, SCHEME["neutral"])
    accent = sc["accent"][2]
    c = Canvas(HAND_W, HAND_H)
    seed = 4600 + sum(ord(ch) for ch in element + role)
    c.rect(0, 0, HAND_W, HAND_H, P.UI_DARK[1])

    def panel(y, h, tone):
        c.rect(5, y, HAND_W - 10, h, tone)
        for x in range(5, HAND_W - 5):
            c.set(x, y, P.INK)
            c.set(x, y + h - 1, P.UI_DARK[4])
        for j in range(y, y + h):
            c.set(5, j, P.INK)
            c.set(HAND_W - 6, j, P.UI_DARK[3])

    panel(NAME_Y, NAME_H, P.UI_DARK[2])
    panel(ROLE_Y, ROLE_H, P.UI_DARK[0])
    art_backdrop(c, 5, ART_Y, HAND_W - 10, ART_H, element, seed)
    for x in range(5, HAND_W - 5):
        c.set(x, ART_Y, P.INK)
        c.set(x, ART_Y + ART_H - 1, P.INK)
    for j in range(ART_Y, ART_Y + ART_H):
        c.set(5, j, P.INK)
        c.set(HAND_W - 6, j, P.INK)
    panel(FOOT_Y, FOOT_H, P.UI_DARK[0])
    c.rect(5, RULES_Y, HAND_W - 10, HAND_H - RULES_Y - 5, P.UI_DARK[1])
    for x in range(5, HAND_W - 5):
        c.set(x, RULES_Y, P.INK)

    _trim(c, 0, 0, HAND_W, HAND_H, accent)
    _corner_brackets(c, HAND_W, HAND_H, accent)

    # Role reads before any text does: each type carries its own edge treatment.
    if role == "place":
        for i in range(10):
            c.set(8 + i, HAND_H - 8, P.IRON[3]); c.set(HAND_W - 9 - i, HAND_H - 8, P.IRON[3])
        for i in range(4):
            c.set(6, HAND_H - 9 - i, P.IRON[3]); c.set(HAND_W - 7, HAND_H - 9 - i, P.IRON[3])
    elif role == "spell":
        for i in range(6):
            c.set(10 + i, 3 + i, accent); c.set(HAND_W - 11 - i, 3 + i, accent)
    elif role == "realm":
        for x in range(10, HAND_W - 10, 5):
            c.set(x, 3, P.GROVE[4] if element == "life" else P.CINDER[5])
            c.set(x + 1, 3, P.GROVE[4] if element == "life" else P.CINDER[5])
    else:
        for i in range(5):
            c.set(HAND_W // 2 - 2 + i, 3, accent)
    return c


def card_back(element):
    """Deck art — what a face-down stack looks like."""
    s = SCHEME.get(element, SCHEME["neutral"])
    ramp, accent = s["ramp"], s["accent"]
    c = Canvas(HAND_W, HAND_H)
    seed = 4900 + sum(ord(ch) for ch in element)
    for y in range(HAND_H):
        for x in range(HAND_W):
            n = value_noise(x, y, 10, seed)
            c.set(x, y, ramp[1 if n < 0.45 else (2 if n < 0.78 else 3)])
    for i in range(14):
        c.blob(int(hash2(i, 0, seed) * HAND_W), int(hash2(i, 1, seed + 3) * HAND_H),
               4 + hash2(i, 2, seed + 5) * 6, ramp[0], 0.36, seed + i * 11, 6)
    c.frame(11, 11, HAND_W - 22, HAND_H - 22, P.IRON[3])
    c.frame(12, 12, HAND_W - 24, HAND_H - 24, P.INK)
    cx, cy = HAND_W // 2, HAND_H // 2
    c.disc(cx, cy, 29, P.INK)
    c.disc(cx, cy, 27, P.IRON[2])
    c.disc(cx, cy, 24, P.INK)
    c.disc(cx, cy, 22, ramp[0])
    if element == "life":
        for k in range(19):                                   # sprout sigil
            c.set(cx, cy + 14 - k, P.LEAF[3]); c.set(cx + 1, cy + 14 - k, P.LEAF[2])
            if k > 7:
                for d in (-1, 1):
                    c.set(cx + d * (k - 7), cy + 14 - k, P.LEAF[3])
                    c.set(cx + d * (k - 7), cy + 15 - k, P.LEAF[2])
        c.disc(cx, cy - 8, 3, P.SPORE[2])
    else:
        for k, w in enumerate((1, 3, 5, 7, 7, 5, 3, 1)):      # flame sigil
            for j in range(-w, w + 1):
                c.set(cx + j, cy + 12 - k * 3, P.EMBER[4] if k > 4 else P.EMBER[3])
        c.disc(cx, cy + 4, 4, P.HOT[2])
        c.disc(cx, cy + 5, 2, P.HOT[4])
    _trim(c, 0, 0, HAND_W, HAND_H, accent[2])
    _corner_brackets(c, HAND_W, HAND_H, accent[2])
    return c
