#!/usr/bin/env python3
"""Assets for the 2.5D visual prototype (Arcana Visual Prototype).

A deliberate break from the pixel pipeline: card faces are high-res painterly
renders with real type (Georgia), creatures are stylized illustration cutouts,
particles are soft alpha sprites. Nothing here touches the V2/V3 pixel assets.

    python3 tools/build_proto_assets.py
"""
import math, os
import numpy as np
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).parent.parent
OUT = ROOT / "assets/proto"
FONT_DIR = "/System/Library/Fonts/Supplemental"

PICKS = {
    "sprigget": ".art_candidates/proto_sprigget/1.png",
    "cinderbelly": ".art_candidates/proto_cinderbelly/1.png",
    "wild_bloom": ".art_candidates/proto_spell_bloom/0.png",
    "ember_storm": ".art_candidates/proto_spell_embers/1.png",
}

CARDS = [
    {"id": "sprigget", "name": "Sprigget", "sub": "the Pot-Sprout",
     "element": "life", "kind": "creature", "cost": 3, "atk": 3, "hp": 8,
     "type_line": "LIFE CREATURE · PLAY ON GROVE",
     "rules": "At the end of your turn, Sprigget blooms: heal 1."},
    {"id": "cinderbelly", "name": "Cinderbelly", "sub": "the Stove Imp",
     "element": "fire", "kind": "creature", "cost": 3, "atk": 4, "hp": 10,
     "type_line": "FIRE CREATURE · PLAY ON CINDER",
     "rules": "When Cinderbelly attacks, embers spill: +1 damage."},
    {"id": "wild_bloom", "name": "Wild Bloom", "sub": "",
     "element": "life", "kind": "spell", "cost": 2,
     "type_line": "LIFE SPELL",
     "rules": "Vines erupt across your Grove. Heal your creature 3."},
    {"id": "ember_storm", "name": "Ember Storm", "sub": "",
     "element": "fire", "kind": "spell", "cost": 2,
     "type_line": "FIRE SPELL",
     "rules": "A wave of embers sweeps the enemy lane. Deal 2."},
]

GOLD = (201, 163, 76)
GOLD_LIGHT = (240, 214, 130)
PARCH = (240, 230, 210)
INK = (13, 11, 16)


def font(name, size):
    return ImageFont.truetype(f"{FONT_DIR}/{name}", size)


def smooth_noise(w, h, cell, seed):
    rng = np.random.default_rng(seed)
    gw, gh = w // cell + 2, h // cell + 2
    coarse = rng.random((gh, gw))
    img = Image.fromarray((coarse * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
    return np.asarray(img).astype(np.float32) / 255.0


def radial(w, h, inner, outer, cx=0.5, cy=0.42, power=1.6):
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.sqrt(((xs / w - cx) * 1.0) ** 2 + ((ys / h - cy) * (h / w)) ** 2)
    d = np.clip(d / 0.62, 0, 1) ** power
    out = np.zeros((h, w, 3), np.float32)
    for c in range(3):
        out[..., c] = inner[c] * (1 - d) + outer[c] * d
    return out


def conform_creature(name, src, target_h=640):
    im = Image.open(ROOT / src).convert("RGBA")
    bbox = im.getbbox()
    if bbox: im = im.crop(bbox)
    sc = target_h / im.height
    im = im.resize((int(im.width * sc), target_h), Image.LANCZOS)
    d = OUT / "creatures"; d.mkdir(parents=True, exist_ok=True)
    im.save(d / f"{name}.png")
    return im


def rounded_mask(w, h, r):
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w - 1, h - 1], r, fill=255)
    return m


def gem(draw_im, cx, cy, r, tone_hi, tone_lo, ring=GOLD):
    """A rounded gem with a lit crown — the badge language of every number."""
    ys, xs = np.mgrid[0:draw_im.height, 0:draw_im.width].astype(np.float32)
    d = np.sqrt((xs - cx) ** 2 + (ys - cy) ** 2)
    lit = np.sqrt((xs - cx + r * 0.35) ** 2 + (ys - cy + r * 0.4) ** 2)
    t = np.clip(lit / (r * 1.9), 0, 1)
    base = np.asarray(draw_im).astype(np.float32)
    for c in range(3):
        col = tone_hi[c] * (1 - t) + tone_lo[c] * t
        base[..., c] = np.where(d <= r, col, base[..., c])
    base[..., 3] = np.where(d <= r, 255, base[..., 3])
    im = Image.fromarray(base.astype(np.uint8))
    dr = ImageDraw.Draw(im)
    dr.ellipse([cx - r, cy - r, cx + r, cy + r], outline=INK, width=5)
    dr.ellipse([cx - r + 4, cy - r + 4, cx + r - 4, cy + r - 4], outline=ring, width=3)
    return im


def crest(dr, cx, cy, element):
    if element == "life":
        dr.polygon([(cx, cy - 22), (cx + 15, cy - 4), (cx + 6, cy + 18),
                    (cx - 6, cy + 18), (cx - 15, cy - 4)], fill=(110, 190, 90))
        dr.line([(cx, cy - 18), (cx, cy + 16)], fill=(50, 110, 45), width=3)
    else:
        dr.polygon([(cx, cy - 24), (cx + 13, cy - 2), (cx + 7, cy + 18),
                    (cx - 7, cy + 18), (cx - 13, cy - 2)], fill=(250, 120, 40))
        dr.ellipse([cx - 6, cy - 2, cx + 6, cy + 14], fill=(255, 214, 120))


def centred(dr, xy, text, fnt, fill, shadow=True, anchor="mm"):
    if shadow:
        dr.text((xy[0] + 2, xy[1] + 3), text, font=fnt, fill=(0, 0, 0, 190), anchor=anchor)
    dr.text(xy, text, font=fnt, fill=fill, anchor=anchor)


def wrap(dr, text, fnt, max_w):
    words, lines, cur = text.split(), [], ""
    for w in words:
        trial = (cur + " " + w).strip()
        if dr.textlength(trial, font=fnt) <= max_w: cur = trial
        else: lines.append(cur); cur = w
    if cur: lines.append(cur)
    return lines


def build_card(card, art_im):
    W, H = 512, 717
    el = card["element"]
    if el == "life": win_in, win_out = (58, 112, 64), (14, 34, 22)
    else:            win_in, win_out = (122, 52, 26), (26, 13, 12)

    base = radial(W, H, (40, 36, 48), (22, 19, 27), cy=0.30, power=1.2)
    base += (smooth_noise(W, H, 38, hash(card["id"]) % 999)[..., None] - 0.5) * 10
    im = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8)).convert("RGBA")
    dr = ImageDraw.Draw(im)

    # Art window with an element-lit backdrop; the illustration gets the space.
    ax0, ay0, ax1, ay1 = 26, 88, W - 26, 452
    win = radial(ax1 - ax0, ay1 - ay0, win_in, win_out, cy=0.55, power=1.3)
    win += (smooth_noise(ax1 - ax0, ay1 - ay0, 26, 7)[..., None] - 0.5) * 14
    im.paste(Image.fromarray(np.clip(win, 0, 255).astype(np.uint8)), (ax0, ay0))

    art = art_im.copy()
    max_w, max_h = (ax1 - ax0) - 24, (ay1 - ay0) - 16
    sc = min(max_w / art.width, max_h / art.height)
    art = art.resize((int(art.width * sc), int(art.height * sc)), Image.LANCZOS)
    sh = Image.new("RGBA", art.size, (0, 0, 0, 0))
    sh.paste(Image.new("RGBA", art.size, (0, 0, 0, 140)), (0, 0), art)
    sh = sh.filter(ImageFilter.GaussianBlur(9))
    px = ax0 + ((ax1 - ax0) - art.width) // 2
    py = ay1 - art.height - 6
    im.alpha_composite(sh, (px + 6, py + 12))
    im.alpha_composite(art, (px, py))

    dr = ImageDraw.Draw(im)
    dr.rectangle([ax0, ay0, ax1, ay1], outline=INK, width=5)
    dr.rectangle([ax0 + 3, ay0 + 3, ax1 - 3, ay1 - 3], outline=GOLD, width=2)

    # Name — the sub-title carries the personality.
    name_y = 46
    centred(dr, (W / 2, name_y), card["name"], font("Georgia Bold.ttf", 46), PARCH)
    if card["sub"]:
        centred(dr, (W / 2, name_y + 34), card["sub"], font("Georgia Italic.ttf", 24), (190, 178, 156))
    centred(dr, (W / 2, 474), card["type_line"], font("Trebuchet MS Bold.ttf", 21), GOLD)

    for i, line in enumerate(wrap(dr, card["rules"], font("Georgia.ttf", 29), W - 120)):
        centred(dr, (W / 2, 520 + i * 38), line, font("Georgia.ttf", 29), (216, 210, 198), shadow=False)

    # Frame and corner accents.
    dr.rounded_rectangle([3, 3, W - 4, H - 4], 26, outline=INK, width=7)
    dr.rounded_rectangle([9, 9, W - 10, H - 10], 22, outline=GOLD, width=3)
    for cx, cy, sx, sy in ((16, 16, 1, 1), (W - 17, 16, -1, 1), (16, H - 17, 1, -1), (W - 17, H - 17, -1, -1)):
        dr.line([(cx, cy + sy * 34), (cx, cy), (cx + sx * 34, cy)], fill=GOLD_LIGHT, width=4)

    # Badges overlapping the frame.
    im = gem(im, 56, 58, 42, (140, 168, 250), (36, 48, 120))
    dr = ImageDraw.Draw(im)
    centred(dr, (56, 58), str(card["cost"]), font("Georgia Bold.ttf", 44), (255, 255, 255))
    dr.ellipse([W - 92, 24, W - 24, 92], fill=(26, 22, 32), outline=GOLD, width=3)
    crest(dr, W - 58, 58, el)
    if card["kind"] == "creature":
        im = gem(im, 62, H - 62, 46, (250, 200, 90), (120, 76, 16))
        im = gem(im, W - 62, H - 62, 46, (240, 110, 130), (110, 26, 44))
        dr = ImageDraw.Draw(im)
        centred(dr, (62, H - 62), str(card["atk"]), font("Georgia Bold.ttf", 48), (255, 252, 240))
        centred(dr, (W - 62, H - 62), str(card["hp"]), font("Georgia Bold.ttf", 48), (255, 244, 246))

    im.putalpha(rounded_mask(W, H, 26))
    d = OUT / "cards"; d.mkdir(parents=True, exist_ok=True)
    im.save(d / f"{card['id']}.png")


def build_card_back():
    W, H = 512, 717
    base = radial(W, H, (44, 38, 58), (20, 17, 26), cy=0.5, power=1.4)
    base += (smooth_noise(W, H, 30, 42)[..., None] - 0.5) * 12
    im = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8)).convert("RGBA")
    dr = ImageDraw.Draw(im)
    dr.rounded_rectangle([3, 3, W - 4, H - 4], 26, outline=INK, width=7)
    dr.rounded_rectangle([9, 9, W - 10, H - 10], 22, outline=GOLD, width=3)
    dr.rounded_rectangle([26, 26, W - 27, H - 27], 14, outline=(90, 76, 110), width=2)
    cx, cy = W // 2, H // 2
    for r, wdt, col in ((150, 5, GOLD), (128, 2, (120, 100, 140)), (94, 3, GOLD)):
        dr.ellipse([cx - r, cy - r, cx + r, cy + r], outline=col, width=wdt)
    for i in range(8):                       # eight elements, two lit
        a = i * math.tau / 8 - math.pi / 2
        px, py = cx + math.cos(a) * 111, cy + math.sin(a) * 111
        lit = (110, 190, 90) if i == 0 else ((250, 120, 40) if i == 1 else (70, 62, 84))
        dr.ellipse([px - 11, py - 11, px + 11, py + 11], fill=lit, outline=INK, width=3)
    for i in range(4):                       # inner star
        a = i * math.tau / 8
        dr.line([(cx + math.cos(a) * 82, cy + math.sin(a) * 82),
                 (cx - math.cos(a) * 82, cy - math.sin(a) * 82)], fill=(120, 100, 140), width=2)
    dr.ellipse([cx - 30, cy - 30, cx + 30, cy + 30], fill=(30, 25, 40), outline=GOLD, width=3)
    centred(dr, (cx, cy + 1), "A", font("Georgia Bold.ttf", 42), GOLD_LIGHT)
    im.putalpha(rounded_mask(W, H, 26))
    im.save(OUT / "cards/card_back.png")


def soft_sprite(name, size, painter):
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    painter(ImageDraw.Draw(im), size)
    im.save(OUT / "fx" / f"{name}.png")


def build_particles():
    (OUT / "fx").mkdir(parents=True, exist_ok=True)
    n = 96
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float32)
    d = np.sqrt((xs - n / 2) ** 2 + (ys - n / 2) ** 2) / (n / 2)
    a = np.clip(1 - d, 0, 1) ** 2.4
    dot = np.zeros((n, n, 4), np.uint8)
    dot[..., 0:3] = 255
    dot[..., 3] = (a * 255).astype(np.uint8)
    Image.fromarray(dot).save(OUT / "fx/soft_dot.png")

    puff = np.zeros((n, n, 4), np.float32)
    for cx, cy, r in ((36, 52, 26), (58, 46, 24), (48, 30, 20)):
        dd = np.sqrt((xs - cx) ** 2 + (ys - cy) ** 2) / r
        puff[..., 3] = np.maximum(puff[..., 3], np.clip(1 - dd, 0, 1) ** 1.6 * 190)
    puff[..., 0:3] = 235
    Image.fromarray(puff.astype(np.uint8)).save(OUT / "fx/puff.png")

    def leaf(dr, s):
        dr.polygon([(s * .5, s * .06), (s * .82, s * .42), (s * .5, s * .94), (s * .18, s * .42)],
                   fill=(255, 255, 255, 235))
    soft_sprite("leaf", 64, leaf)

    def spark(dr, s):
        dr.line([(s * .5, s * .04), (s * .5, s * .96)], fill=(255, 255, 255, 255), width=6)
        dr.line([(s * .3, s * .5), (s * .7, s * .5)], fill=(255, 255, 255, 190), width=4)
    soft_sprite("spark", 48, spark)


def build_ui():
    d = OUT / "ui"; d.mkdir(parents=True, exist_ok=True)
    W, H = 1280, 720
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    dd = np.sqrt(((xs / W - .5) * 1.25) ** 2 + ((ys / H - .5)) ** 2)
    a = np.clip((dd - 0.42) / 0.42, 0, 1) ** 1.8 * 150
    v = np.zeros((H, W, 4), np.uint8)
    v[..., 0:3] = (14, 10, 18)
    v[..., 3] = a.astype(np.uint8)
    Image.fromarray(v).save(d / "vignette.png")

    n = 128                                  # blob shadow for creatures
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float32)
    ddd = np.sqrt((xs - n / 2) ** 2 + ((ys - n / 2) * 1.0) ** 2) / (n / 2)
    s = np.zeros((n, n, 4), np.uint8)
    s[..., 3] = (np.clip(1 - ddd, 0, 1) ** 1.5 * 175).astype(np.uint8)
    Image.fromarray(s).save(d / "blob_shadow.png")

    scorch = np.zeros((n, n, 4), np.float32)  # a mark the fire spell leaves
    rng = np.random.default_rng(9)
    for _ in range(7):
        cx, cy, r = rng.uniform(30, 98), rng.uniform(30, 98), rng.uniform(12, 30)
        dd2 = np.sqrt((xs - cx) ** 2 + (ys - cy) ** 2) / r
        scorch[..., 3] = np.maximum(scorch[..., 3], np.clip(1 - dd2, 0, 1) ** 1.2 * 200)
    scorch[..., 0:3] = (16, 10, 8)
    Image.fromarray(scorch.astype(np.uint8)).save(d / "scorch.png")


def main():
    arts = {}
    for name, src in PICKS.items():
        arts[name] = conform_creature(name, src, 640 if name in ("sprigget", "cinderbelly") else 480)
        print(f"  {name:14} {arts[name].size}")
    for card in CARDS:
        build_card(card, arts[card["id"]])
    build_card_back()
    build_particles()
    build_ui()
    print("proto assets written to assets/proto/")


if __name__ == "__main__":
    main()
