#!/usr/bin/env python3
"""Emit the Life/Fire landscape kit: ground tiles, rims, corners, seams, props.

    python3 tools/build_land_kit.py            # write every asset
    python3 tools/build_land_kit.py --sheet    # also write a review contact sheet

Regenerating is deterministic: same code, same pixels. Restyling the land is a
re-run of this script, not a re-generation spend.
"""
import argparse, json, os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__)))

from PIL import Image
from pixelart import land, props, table, palette as P
from pixelart.canvas import Canvas

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LAND_DIR = os.path.join(ROOT, "assets/art/board/land")
PROP_DIR = os.path.join(ROOT, "assets/art/board/props")
TABLE_DIR = os.path.join(ROOT, "assets/art/board/table")

ELEMENTS = ["grove", "cinder", "ashbloom", "neutral"]
EDGES = ["n", "s", "e", "w"]
CORNERS = ["nw", "ne", "sw", "se"]
FILL_VARIANTS = 4


RIM_VARIANTS = 3


def build_land():
    written = []
    for el in ELEMENTS:
        d = os.path.join(LAND_DIR, el)
        written.append(land.field(el).save(f"{d}/field.png"))
        for e in EDGES:
            for v in range(RIM_VARIANTS):
                written.append(land.rim(el, e, v).save(f"{d}/rim_{e}_{v}.png"))
        for k in CORNERS:
            written.append(land.rim_corner(el, k, 0).save(f"{d}/corner_{k}.png"))
        written.append(land.face(el, 0).save(f"{d}/face.png"))
        written.append(land.face(el, 1).save(f"{d}/face_b.png"))
    for a, b in (("grove", "cinder"), ("cinder", "grove"),
                 ("grove", "neutral"), ("neutral", "grove"),
                 ("cinder", "neutral"), ("neutral", "cinder"),
                 ("grove", "ashbloom"), ("cinder", "ashbloom")):
        written.append(land.transition(a, b, 0).save(f"{LAND_DIR}/seam/{a}_{b}.png"))
    return written


def build_props():
    written = []
    for el, prop_table in (("grove", props.GROVE_PROPS), ("cinder", props.CINDER_PROPS)):
        for name, fn in prop_table.items():
            for v in range(3):
                written.append(fn(v).save(f"{PROP_DIR}/{el}/{name}_{v}.png"))
    return written


def build_table():
    """The arcane table the battlefield is built on (pixelart/table.py)."""
    os.makedirs(TABLE_DIR, exist_ok=True)
    written = []
    for v in range(2):
        written.append(table.table_field(v).save(f"{TABLE_DIR}/field_{v}.png"))
    written.append(table.channel_field().save(f"{TABLE_DIR}/channel.png"))
    for v in range(4):
        written.append(table.medallion(v).save(f"{TABLE_DIR}/medallion_{v}.png"))
    return written


def contact_sheet(paths, out, cols=14, cell=52, bg=(24, 22, 28)):
    rows = (len(paths) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cell, rows * cell), bg + (255,))
    for i, p in enumerate(paths):
        im = Image.open(p).convert("RGBA")
        x = (i % cols) * cell + (cell - im.width) // 2
        y = (i // cols) * cell + (cell - im.height) // 2
        sheet.alpha_composite(im, (max(0, x), max(0, y)))
    sheet = sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST)
    sheet.save(out)
    return out


def tiled_preview(element, out, across=4, down=2):
    """Proof the field tiles: no grid, no banding, no feature cut in half."""
    f = land.FIELD
    im = Image.new("RGBA", (across * f, down * f))
    fld = Image.open(f"{LAND_DIR}/{element}/field.png")
    for y in range(down):
        for x in range(across):
            im.alpha_composite(fld, (x * f, y * f))
    im.save(out)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheet", action="store_true")
    ap.add_argument("--outdir", default=None)
    args = ap.parse_args()

    lp = build_land()
    pp = build_props()
    tp = build_table()
    print(f"land tiles: {len(lp)}   props: {len(pp)}   table: {len(tp)}")

    manifest = {"tile": land.TILE, "field": land.FIELD, "rim": land.RIM,
                "rim_variants": RIM_VARIANTS, "face_h": land.FACE_H,
                "table_fields": 2, "medallions": 4,
                "elements": ELEMENTS, "edges": EDGES, "corners": CORNERS,
                "grove_props": sorted(props.GROVE_PROPS), "cinder_props": sorted(props.CINDER_PROPS)}
    with open(os.path.join(ROOT, "data/land_kit_manifest.json"), "w") as f:
        json.dump(manifest, f, indent=2)

    if args.sheet:
        out = args.outdir or "/tmp"
        os.makedirs(out, exist_ok=True)
        print(contact_sheet(pp, f"{out}/props_sheet.png"))
        print(contact_sheet(lp, f"{out}/land_sheet.png", cols=17, cell=38))
        for el in ("grove", "cinder"):
            print(tiled_preview(el, f"{out}/tiled_{el}.png"))


if __name__ == "__main__":
    main()
