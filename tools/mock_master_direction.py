#!/usr/bin/env python3
"""Master-direction mock for the Pocket Arcana V2 art pass.

Builds a full 1280x720 screen from existing production assets plus
new-direction pieces (arcana table, elevated land plots, stat plinths,
embedded hearts, hand tray). Iterated visually before any GDScript changes.
"""
import math, os, sys
from PIL import Image, ImageDraw

ROOT = os.path.expanduser("~/Projects/pocket-arcana")
sys.path.insert(0, os.path.join(ROOT, "tools"))
from pixelart import palette as P
from pixelart.canvas import hash2, value_noise

W, H = 1280, 720
PX = 2  # world pixel size: draw at half res then scale 2x for chunky pixels


def A(path):
    return Image.open(os.path.join(ROOT, "assets/art", path)).convert("RGBA")


def scale(im, k):
    return im.resize((int(im.width * k), int(im.height * k)), Image.NEAREST)


# ---------------------------------------------------------------- table ----
TABLE = [(26, 28, 40), (31, 34, 48), (36, 40, 56), (42, 47, 64)]
TABLE_LINE = (52, 58, 82)
RUNE = (64, 72, 104)

def table_surface(w, h, seed=7):
    """Calm arcane slate. Big soft cells, no per-pixel speckle."""
    im = Image.new("RGB", (w // PX, h // PX), TABLE[1])
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            n = value_noise(x, y, 34, seed)
            m = value_noise(x, y, 90, seed + 5)
            i = 1
            if n < 0.40: i = 0
            elif n > 0.68: i = 2
            if m > 0.62 and i < 3: i += 1
            px[x, y] = TABLE[i]
    return scale(im, PX)


def rune_ring(draw, cx, cy, r, col=RUNE, wpx=PX):
    steps = 64
    for i in range(steps):
        a0 = i / steps * math.tau
        if i % 8 in (3, 4):  # broken ring, carved feel
            continue
        x0, y0 = cx + math.cos(a0) * r, cy + math.sin(a0) * r
        draw.ellipse([x0 - wpx, y0 - wpx, x0 + wpx, y0 + wpx], fill=col)


# ---------------------------------------------------------------- fields ---
def calm_field(element, w, h, seed=3):
    """Reworked land surface: chunky flat patches, sparse accents."""
    if element == "grove":
        ramp = [P.GROVE[2], P.GROVE[3], P.GROVE[4], P.GROVE[5]]
        accent = [(P.LEAF[4], 0.010), (P.BLOOM[2], 0.004), (P.GROVE[6], 0.010)]
    else:
        ramp = [P.CINDER[2], P.CINDER[3], P.CINDER[4], P.CINDER[5]]
        accent = [(P.EMBER[2], 0.014), (P.EMBER[3], 0.008), (P.EMBER[4], 0.004),
                  (P.CHAR[1], 0.016)]
    im = Image.new("RGB", (w // PX, h // PX), ramp[1])
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            n = value_noise(x, y, 22, seed)
            i = 1
            if n < 0.38: i = 0
            elif n > 0.72: i = 3
            elif n > 0.58: i = 2
            px[x, y] = ramp[i]
    for col, dens in accent:
        for y in range(im.height):
            for x in range(im.width):
                if hash2(x, y, seed + col[0]) > 1.0 - dens:
                    px[x, y] = col
                    if x + 1 < im.width: px[x + 1, y] = col
    return scale(im, PX)


def rounded_mask(w, h, r):
    m = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=r, fill=255)
    return m


def plot(element, w, h, seed=3):
    """An elevated diorama plot: top surface + thick face + ink outline."""
    face_h = 26
    im = Image.new("RGBA", (w, h + face_h), (0, 0, 0, 0))
    top = calm_field(element, w, h, seed)
    mask = rounded_mask(w, h, 18)
    im.paste(top, (0, 0), mask)
    d = ImageDraw.Draw(im)
    # face: dark earth strip under the south edge
    if element == "grove":
        fc, fc2 = P.WOOD[1], P.WOOD[2]
        edge_hi = P.GROVE[6]
    else:
        fc, fc2 = P.CHAR[0], P.CHAR[1]
        edge_hi = P.EMBER[2]
    d.rounded_rectangle([0, h - 20, w - 1, h + face_h - 1], radius=14, fill=fc + (255,))
    for x in range(4, w - 4, 6):  # strata ticks on the face
        if hash2(x, 0, seed) > 0.5:
            d.rectangle([x, h + 4, x + 3, h + 6], fill=fc2 + (255,))
    im.paste(top, (0, 0), mask)
    # ink outline around everything
    sil = Image.new("L", im.size, 0)
    sd = ImageDraw.Draw(sil)
    sd.rounded_rectangle([0, 0, w - 1, h - 1], radius=18, fill=255)
    sd.rounded_rectangle([0, h - 18, w - 1, h + face_h - 1], radius=14, fill=255)
    outline = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ink = P.INK + (255,)
    for ox, oy in ((-PX, 0), (PX, 0), (0, -PX), (0, PX)):
        outline.paste(Image.new("RGBA", im.size, ink), (ox, oy), sil)
    outline.paste(im, (0, 0), sil)
    # top edge highlight rim
    od = ImageDraw.Draw(outline)
    od.rounded_rectangle([PX, PX, w - 1 - PX, h - 1 - PX], radius=16,
                         outline=edge_hi + (140,), width=PX)
    return outline


def socket(draw, x, y, w, h):
    """An unbuilt lane: a faint carved recess in the table."""
    draw.rounded_rectangle([x, y, x + w, y + h], radius=16,
                           outline=(18, 19, 28, 255), width=PX * 2)
    draw.rounded_rectangle([x + PX * 2, y + PX * 2, x + w - PX * 2, y + h - PX * 2],
                           radius=14, outline=TABLE_LINE + (120,), width=PX)


# --------------------------------------------------------------- pieces ----
def shadow(im, cx, cy, w, h, alpha=90):
    d = ImageDraw.Draw(im)
    d.ellipse([cx - w // 2, cy - h // 2, cx + w // 2, cy + h // 2],
              fill=(8, 6, 10, alpha))


def token(kind, value):
    """A chunky carved stat token: power (gold) or health (heart red)."""
    s = 23
    im = Image.new("RGBA", (s * PX, s * PX), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    col = P.GOLD if kind == "power" else P.HEART
    base, mid, hi = col[1], col[2], col[3]
    r = s * PX // 2 - PX
    cx = cy = s * PX // 2
    d.ellipse([cx - r - PX, cy - r - PX, cx + r + PX, cy + r + PX], fill=P.INK + (255,))
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=base + (255,))
    d.ellipse([cx - r + PX * 2, cy - r + PX * 2, cx + r - PX * 2, cy + r - PX * 2],
              fill=mid + (255,))
    d.ellipse([cx - r + PX * 2, cy - r + PX * 2, cx, cy], fill=hi + (150,))
    # numeral, chunky
    _digit(d, str(value), cx, cy, P.INK)
    return im


def _digit(d, text, cx, cy, col):
    seg = {  # 3x5 microfont
     "0":"111101101101111","1":"010110010010111","2":"111001111100111",
     "3":"111001111001111","4":"101101111001001","5":"111100111001111",
     "6":"111100111101111","7":"111001010010010","8":"111101111101111",
     "9":"111101111001111"}
    k = PX * 2
    total_w = len(text) * 4 - 1
    x0 = cx - total_w * k // 2
    y0 = cy - 5 * k // 2
    for ch in text:
        bits = seg.get(ch, seg["0"])
        for i, b in enumerate(bits):
            if b == "1":
                x, y = i % 3, i // 3
                d.rectangle([x0 + x * k, y0 + y * k, x0 + x * k + k - 1,
                             y0 + y * k + k - 1], fill=col + (255,))
        x0 += 4 * k


def heart_crystal(hp, maxhp=20, big=False):
    """Compact faceted heart gem on a stone plaque socket."""
    w, h = 30 * PX, 38 * PX
    im = Image.new("RGBA", (w + 8 * PX, h + 26 * PX), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx = im.width // 2
    # plaque below
    d.rounded_rectangle([cx - 15 * PX, h + 2 * PX, cx + 15 * PX, h + 22 * PX],
                        radius=4 * PX, fill=P.STONE[1] + (255,),
                        outline=P.INK + (255,), width=PX)
    frac = hp / maxhp
    pts = [(cx, PX), (cx + w // 2 - PX, h * 0.36), (cx, h - PX), (cx - w // 2 + PX, h * 0.36)]
    # dark empty crystal
    d.polygon(pts, fill=(42, 14, 26, 255))
    # fill from bottom
    fill_im = Image.new("RGBA", im.size, (0, 0, 0, 0))
    fd = ImageDraw.Draw(fill_im)
    fd.polygon(pts, fill=P.HEART[2] + (255,))
    top = PX + (h - 2 * PX) * (1 - frac)
    fd.rectangle([0, 0, im.width, top], fill=(0, 0, 0, 0))
    im.alpha_composite(fill_im)
    d.polygon(pts, outline=P.INK + (255,))
    d.line([(cx - 4 * PX, 6 * PX), (cx - w // 4, h * 0.3)], fill=P.HEART[4] + (220,), width=PX)
    _digit(d, str(hp), cx, h + 12 * PX, (250, 240, 245))
    return im


def orb_row(n_lit, n_total):
    s = 14 * PX
    im = Image.new("RGBA", (n_total * (s + PX * 2), s + PX * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for i in range(n_total):
        x = i * (s + PX * 2)
        if i < n_lit:
            d.ellipse([x, PX, x + s, PX + s], fill=P.AETHER[2] + (255,),
                      outline=P.INK + (255,), width=PX)
            d.ellipse([x + PX * 2, PX * 3, x + s // 2, PX + s // 2],
                      fill=P.AETHER[4] + (200,))
        else:
            d.ellipse([x, PX, x + s, PX + s], fill=(20, 22, 34, 255),
                      outline=P.UI_EDGE[0] + (160,), width=PX)
    return im


def wood_panel(w, h, ramp=P.WOOD):
    im = Image.new("RGBA", (w, h), ramp[2] + (255,))
    d = ImageDraw.Draw(im)
    for y in range(0, h, 7 * PX):  # plank lines
        d.line([(0, y), (w, y)], fill=ramp[1] + (255,), width=PX)
    for x in range(0, w, 61 * PX):
        d.line([(x, 0), (x, h)], fill=ramp[1] + (255,), width=PX)
    d.rectangle([0, 0, w - 1, h - 1], outline=P.INK + (255,), width=PX * 2)
    d.rectangle([PX * 2, PX * 2, w - 1 - PX * 2, h - 1 - PX * 2],
                outline=ramp[4] + (140,), width=PX)
    return im


def carved_button(text_w, label_dots, gold=False):
    w, h = text_w, 44 * PX
    ramp = P.GOLD if gold else P.STONE
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([0, PX * 3, w - 1, h - 1], radius=10 * PX, fill=P.INK + (255,))
    d.rounded_rectangle([0, 0, w - 1, h - PX * 3], radius=10 * PX,
                        fill=ramp[2] + (255,), outline=P.INK + (255,), width=PX * 2)
    d.rounded_rectangle([PX * 2, PX * 2, w - PX * 3, h - PX * 5], radius=8 * PX,
                        outline=ramp[3] + (200,), width=PX)
    return im


# ----------------------------------------------------------------- build ---
def build():
    im = table_surface(W, H + 60).crop((0, 0, W, H)).convert("RGBA")
    d = ImageDraw.Draw(im)

    RAIL = 176
    TRAY_H = 152
    field_x0 = RAIL + 12
    field_w = W - RAIL - 148 - field_x0
    lane_w = field_w // 4
    clash_y = (H - TRAY_H) // 2 + 4
    row_h = 218
    plot_w, plot_h = lane_w - 10, 168

    # clash channel
    d.rounded_rectangle([field_x0 - 20, clash_y - 30, field_x0 + field_w + 20, clash_y + 30],
                        radius=14, fill=TABLE[0] + (255,), outline=(15, 16, 24, 255), width=PX * 2)
    for i in range(4):
        cx = field_x0 + i * lane_w + lane_w // 2
        rune_ring(d, cx, clash_y, 20)

    # faint lane guides on the table
    for i in range(4):
        cx = field_x0 + i * lane_w + lane_w // 2
        for yy in range(clash_y - 120, clash_y + 120, 14 * PX):
            d.rectangle([cx - PX, yy, cx + PX, yy + 4 * PX], fill=TABLE_LINE + (70,))

    # --- lands: player has 3 grove plots, rival 2 cinder plots
    built = {(0, 0): "grove", (0, 1): "grove", (0, 2): "grove",
             (1, 1): "cinder", (1, 2): "cinder"}
    plot_pos = {}
    for (side, lane), el in sorted(built.items(), key=lambda kv: -kv[0][0]):
        x = field_x0 + lane * lane_w + (lane_w - plot_w) // 2
        y = clash_y + 44 if side == 0 else clash_y - 44 - plot_h - 22
        p = plot(el, plot_w, plot_h, seed=side * 7 + lane * 3)
        im.alpha_composite(p, (x, y))
        plot_pos[(side, lane)] = (x, y)
    for side in (0, 1):
        for lane in range(4):
            if (side, lane) in built: continue
            x = field_x0 + lane * lane_w + (lane_w - plot_w) // 2
            y = clash_y + 44 if side == 0 else clash_y - 44 - plot_h - 22
            socket(d, x, y, plot_w, plot_h + 22)

    # --- creatures standing on plots
    def stand(side, lane, path, k, dx=0, dy=0, pw=None, hp=None, flip=False):
        x, y = plot_pos[(side, lane)]
        spr = scale(A(path), k)
        if flip: spr = spr.transpose(Image.FLIP_LEFT_RIGHT)
        cx = x + plot_w // 2 + dx
        foot = y + plot_h - 16 + dy
        shadow(im, cx, foot + 6, spr.width - 16, 26)
        im.alpha_composite(spr, (cx - spr.width // 2, foot - spr.height + 10))
        if pw is not None:
            t1, t2 = token("power", pw), token("health", hp)
            off = min(spr.width // 2, 52)
            im.alpha_composite(t1, (cx - off - t1.width // 2, foot - 14))
            im.alpha_composite(t2, (cx + off - t2.width // 2, foot - 14))

    # places at back of plots
    def place(side, lane, path, k=1.4):
        x, y = plot_pos[(side, lane)]
        spr = scale(A(path), k)
        cx = x + 52
        foot = y + 66
        shadow(im, cx, foot + 4, spr.width - 20, 20, 70)
        im.alpha_composite(spr, (cx - spr.width // 2, foot - spr.height + 8))

    place(0, 1, "board/landmarks/life/life_herbalist_hut.png")
    place(1, 2, "board/landmarks/fire/fire_blacksmith_nook.png")

    stand(0, 0, "board/creatures/life/life_sproutling.png", 1.7, dx=8, pw=1, hp=3)
    stand(0, 1, "board/creatures/life/life_great_stag.png", 2.0, dx=30, pw=5, hp=7)
    stand(0, 2, "board/creatures/life/life_garden_dragon.png", 2.0, pw=6, hp=8)
    stand(1, 1, "board/creatures/fire/fire_blazewing_drake.png", 2.0, pw=7, hp=4)
    stand(1, 2, "board/creatures/fire/fire_magma_turtle.png", 1.8, dx=-20, pw=4, hp=6)

    # --- sanctuaries on their own big plots (left rail)
    for side, el, sanc, cmd, hp in (
            (1, "cinder", "board/sanctuaries/sanctuary_fire.png",
             "commanders/cmd_poppy_cinder_board.png", 20),
            (0, "grove", "board/sanctuaries/sanctuary_life.png",
             "commanders/cmd_mossy_mae_board.png", 14)):
        py = 26 if side == 1 else H - TRAY_H - 322
        p = plot(el, RAIL - 20, 250, seed=side + 11)
        im.alpha_composite(p, (8, py))
        sanc_im = scale(A(sanc), 1.35)
        im.alpha_composite(sanc_im, (8 + (RAIL - 20 - sanc_im.width) // 2, py + 26))
        cmd_im = scale(A(cmd), 1.25)
        shadow(im, 52, py + 236, 60, 18)
        im.alpha_composite(cmd_im, (52 - cmd_im.width // 2, py + 236 - cmd_im.height))
        hc = heart_crystal(hp, big=(side == 0))
        im.alpha_composite(hc, (RAIL - 44 - hc.width // 2, py + 156 - hc.height // 2))

    # --- right rail: decks + realm stacks
    for side in (0, 1):
        y = H - TRAY_H - 130 if side == 0 else 34
        back = scale(A("ui/card_back_fire.png" if side else "ui/card_back_life.png"), 0.62)
        for i in range(3):
            im.alpha_composite(back, (W - 128 + i * 3, y - i * 3))
        # realm stack: little stack of land tiles
        el = "grove" if side == 0 else "cinder"
        for i in range(3):
            t = plot(el, 64, 26, seed=40 + i)
            im.alpha_composite(t, (W - 122 + i * 2, y + 118 - i * 8))

    # rival aether orbs near their deck
    im.alpha_composite(orb_row(2, 4), (W - 140, 150))

    # --- hand tray
    tray = wood_panel(W, TRAY_H + 8)
    im.alpha_composite(tray, (0, H - TRAY_H))
    # hand cards: new style, drawn fresh
    def hand_card(x, y, art_p, cost, pw=None, hp=None, kind="creature", afford=True):
        cw, ch = 118, 136
        d2 = ImageDraw.Draw(im)
        d2.rounded_rectangle([x + 3, y + 5, x + cw + 3, y + ch + 5],
                             radius=10, fill=(10, 8, 12, 160))
        ramp = P.WOOD if kind != "spell" else P.UI_DARK
        d2.rounded_rectangle([x, y, x + cw, y + ch], radius=10,
                             fill=P.CREAM[1] + (255,), outline=P.INK + (255,), width=PX)
        d2.rounded_rectangle([x + PX, y + PX, x + cw - PX, y + ch - PX], radius=9,
                             outline=P.CREAM[3] + (255,), width=PX)
        # art window: most of the card
        win = [x + 7, y + 7, x + cw - 7, y + ch - 34]
        d2.rounded_rectangle(win, radius=6, fill=P.GROVE[1] + (255,),
                             outline=P.INK + (255,), width=PX)
        if art_p:
            a = A(art_p)
            k = min((win[2] - win[0] - 8) / a.width, (win[3] - win[1] - 8) / a.height)
            a = scale(a, k)
            im.alpha_composite(a, (x + cw // 2 - a.width // 2, win[3] - a.height - 2))
        # name band
        d2.rectangle([x + 7, y + ch - 30, x + cw - 7, y + ch - 20],
                     fill=P.CREAM[0] + (110,))
        # cost crystal top-left (aether purple)
        d2.ellipse([x - 8, y - 8, x + 22, y + 22], fill=P.AETHER[2] + (255,),
                   outline=P.INK + (255,), width=PX)
        _digit(d2, str(cost), x + 7, y + 7, P.INK)
        if pw is not None:
            t1, t2 = token("power", pw), token("health", hp)
            t1 = t1.resize((36, 36), Image.NEAREST); t2 = t2.resize((36, 36), Image.NEAREST)
            im.alpha_composite(t1, (x + 6, y + ch - 20))
            im.alpha_composite(t2, (x + cw - 42, y + ch - 20))
        if not afford:
            veil = Image.new("RGBA", (cw + 1, ch + 1), (16, 14, 20, 130))
            m2 = rounded_mask(cw + 1, ch + 1, 10)
            im.paste(Image.alpha_composite(im.crop((x, y, x + cw + 1, y + ch + 1)), veil),
                     (x, y), m2)
    hy = H - TRAY_H + 8
    hand_card(330, hy, "board/creatures/life/life_bloom_bear.png", 4, 4, 6)
    hand_card(464, hy, "board/creatures/life/life_petal_deer.png", 3, 3, 4)
    hand_card(598, hy, "board/creatures/life/life_rootback_boar.png", 3, 2, 6, afford=False)
    hand_card(732, hy, None, 2, kind="realm")
    hand_card(866, hy, None, 2, kind="spell", afford=False)
    # player aether orbs on the tray, left of the hand
    im.alpha_composite(orb_row(3, 5), (96, H - TRAY_H + 22))
    # realm-stack build token on tray left
    for i in range(3):
        t = plot("grove", 74, 28, seed=60 + i)
        im.alpha_composite(t, (100 + i * 2, H - 84 - i * 9))
    # end turn button
    btn = carved_button(200, None, gold=True)
    im.alpha_composite(btn, (W - 236, H - TRAY_H + 36))

    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mock_master_v1.png")
    im.convert("RGB").save(out)
    print("saved", out)


if __name__ == "__main__":
    build()
