#!/usr/bin/env python3
"""Generate the pieces that genuinely need a generator's character.

Ground, rims, props, frames and VFX are hand-authored in tools/pixelart — they
need exact palettes, seamless tiling and crisp geometry, which a generator is
bad at. What a generator *is* good at is a characterful one-off building, so
this covers Sanctuaries and Place buildings only.

    python3 tools/generate_hero_art.py --list
    python3 tools/generate_hero_art.py --id sanctuary_life_hall --variations 3
    python3 tools/generate_hero_art.py --promote sanctuary_life_hall:2

Candidates land in .art_candidates/<id>/ so re-picking never costs credits.
Auth reads ~/.spritecook_key; the key is never printed or written anywhere.
"""
import argparse, io, json, os, sys, time, urllib.request, urllib.error
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).parent.parent
API = "https://api.spritecook.ai"
CANDIDATES = ROOT / ".art_candidates"
LEDGER = ROOT / "data/art_generation_log.json"

STYLE = ("Chunky readable silhouette, bold dark outline all the way round, flat blocky "
         "shading in three tones, high contrast, tight limited palette, one light source "
         "from the upper left, transparent background, "
         "no text, no letters, no border, no frame, no anti-aliasing, no smooth vector edges, "
         "no 3D render, no painterly texture, no gradient, no miniature display base, "
         "no drop shadow on the background.")

JOBS = {
    "sanctuary_life_hall": {
        "size": (160, 128), "kind": "sanctuary", "element": "life",
        "prompt": "Pocket Arcana pixel art game asset. A magical overgrown tree shrine that is "
                  "a player's home base, slight three-quarter overhead board perspective. One huge "
                  "gnarled tree with a small wooden shrine built into its roots, layered leafy "
                  "canopy above, hanging lanterns, hanging cloth banners, flower beds and "
                  "mushrooms round the base, a glowing green heart-altar recess in the trunk, "
                  "a clear flat standing area in front of the door. " + STYLE,
    },
    "sanctuary_fire_forge": {
        "size": (160, 128), "kind": "sanctuary", "element": "fire",
        "prompt": "Pocket Arcana pixel art game asset. A chunky magical forge fortress that is a "
                  "player's home base, slight three-quarter overhead board perspective. Black stone "
                  "and dark iron walls, a big furnace mouth glowing hot orange, a tall chimney with "
                  "smoke, hanging metal charms, an ember-lit heart chamber recess, anvils and coal "
                  "piles round the base, a clear flat standing area in front of the door. " + STYLE,
    },
    "life_herbalist_hut_built": {
        "size": (96, 96), "kind": "landmark", "element": "life",
        "prompt": "Pocket Arcana pixel art game asset. A small finished herbalist hut, slight "
                  "three-quarter overhead board perspective. Round mossy thatched roof, wooden "
                  "walls, drying herb bundles hanging outside, a window with warm light, potted "
                  "seedlings and flower boxes. " + STYLE,
    },
    "life_bee_garden_built": {
        "size": (96, 96), "kind": "landmark", "element": "life",
        "prompt": "Pocket Arcana pixel art game asset. A small enchanted bee garden, slight "
                  "three-quarter overhead board perspective. Round woven straw beehives on a low "
                  "wooden stand, flowering plants around the base, a few fat glowing bees, a "
                  "little honey pot. " + STYLE,
    },
    "fire_ember_kitchen_built": {
        "size": (96, 96), "kind": "landmark", "element": "fire",
        "prompt": "Pocket Arcana pixel art game asset. A small open-air ember kitchen, slight "
                  "three-quarter overhead board perspective. A dark stone hearth with a glowing "
                  "coal bed, an iron cooking pot on a hook, hanging pans and chilli strings, a "
                  "stack of firewood. " + STYLE,
    },
    # --- 2026-08-30 art pass: the fusion showcase, spells and portraits ----
    "dual_ashbloom_fox": {
        "size": (64, 64), "kind": "creature", "element": "dual",
        "dest": "assets/art/board/creatures/dual/dual_ashbloom_fox.png",
        "prompt": "Pocket Arcana pixel art game asset. A strange mischievous fox creature born "
                  "of fire and flowers fused together: left half charred soot-black fur with "
                  "tiny live embers and one glowing orange eye, right half mossy green fur "
                  "blooming with pink flowers and one bright leaf-green eye, a wide crooked "
                  "grin full of mismatched teeth, two tails — one tipped with flame, one a "
                  "flowering vine. Standing three-quarter view, big head, short legs, strong "
                  "silhouette. " + STYLE,
    },
    "life_rebloom": {
        "size": (256, 160), "kind": "spell", "element": "life",
        "dest": "assets/art/cards/life/life_rebloom.png",
        "prompt": "Pocket Arcana pixel art spell illustration, landscape scene. A burnt black "
                  "tree stump in a scorched clearing bursting back to life: fat pink and cream "
                  "flowers snapping open, bright green shoots spiralling out of the char, "
                  "petals mid-air, one thick shaft of warm light. Bold shapes, big readable "
                  "flowers, no tiny detail. " + STYLE,
    },
    "life_wild_flourish": {
        "size": (256, 160), "kind": "spell", "element": "life",
        "dest": "assets/art/cards/life/life_wild_flourish.png",
        "prompt": "Pocket Arcana pixel art spell illustration, landscape scene. An explosion "
                  "of oversized plant growth: giant curling vines, fat mushrooms and huge "
                  "leaves erupting upward and outward from one point in the ground, comically "
                  "too big, flinging soil and petals. Bold silhouettes, playful energy. " + STYLE,
    },
    "fire_scorch_mark": {
        "size": (256, 160), "kind": "spell", "element": "fire",
        "dest": "assets/art/cards/fire/fire_scorch_mark.png",
        "prompt": "Pocket Arcana pixel art spell illustration, landscape scene. A huge burning "
                  "claw mark being seared into dark ground: three glowing molten gouges with "
                  "cracked black edges, embers spraying up, small flames licking the rims. "
                  "Bold graphic composition, the claw mark fills the frame. " + STYLE,
    },
    "fire_wildfire_waltz": {
        "size": (256, 160), "kind": "spell", "element": "fire",
        "dest": "assets/art/cards/fire/fire_wildfire_waltz.png",
        "prompt": "Pocket Arcana pixel art spell illustration, landscape scene. Two ribbons of "
                  "living flame dancing together in a spiral like waltzing partners, trailing "
                  "sparks in curved arcs over scorched ground, one taller flame dipping the "
                  "smaller one. Playful, mischievous fire with character, not an explosion. " + STYLE,
    },
    "cmd_mossy_mae_portrait": {
        "size": (256, 256), "kind": "portrait", "element": "life",
        "dest": "assets/art/commanders/cmd_mossy_mae_portrait.png",
        "prompt": "Pocket Arcana pixel art character portrait, chest-up. A tiny kind old "
                  "grandmother druid with a huge mossy hood shaped like a mushroom cap, warm "
                  "smiling eyes, a gnarled staff sprouting live flowers, leaf-green cloak with "
                  "cream trim, a fat glowing snail perched on her shoulder. Bold friendly "
                  "shapes, big silhouette. " + STYLE,
    },
    "cmd_poppy_cinder_portrait": {
        "size": (256, 256), "kind": "portrait", "element": "fire",
        "dest": "assets/art/commanders/cmd_poppy_cinder_portrait.png",
        "prompt": "Pocket Arcana pixel art character portrait, chest-up. A fierce gleeful "
                  "young blacksmith girl with wild flame-orange hair that IS partly fire, "
                  "soot-smudged cheeks, oversized leather gloves, a small hammer over her "
                  "shoulder, a little flame imp peeking from her apron pocket. Bold friendly "
                  "shapes, big silhouette. " + STYLE,
    },
    "fire_blacksmith_nook_built": {
        "size": (96, 96), "kind": "landmark", "element": "fire",
        "prompt": "Pocket Arcana pixel art game asset. A small finished blacksmith nook, slight "
                  "three-quarter overhead board perspective. Dark stone forge with a glowing coal "
                  "bed, a small chimney, an anvil outside, hanging tongs and horseshoes, a barrel "
                  "of water. " + STYLE,
    },
}


def key():
    env = os.environ.get("SPRITECOOK_API_KEY")
    if env:
        return env.strip()
    path = Path.home() / ".spritecook_key"
    if not path.is_file():
        sys.exit("No SpriteCook key. Set SPRITECOOK_API_KEY or create ~/.spritecook_key")
    return path.read_text().strip()


def call(method, path, payload=None, timeout=300):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(API + path, data=data, method=method, headers={
        "Authorization": "Bearer " + key(), "Accept": "application/json",
        "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        raise SystemExit(f"HTTP {e.code} on {method} {path}: {e.read().decode('utf-8','replace')[:300]}")


def download(url):
    req = urllib.request.Request(url, headers={"Authorization": "Bearer " + key()})
    with urllib.request.urlopen(req, timeout=180) as r:
        return r.read()


def conform(raw, target):
    """Trim the transparent margin and fit the authored canvas, nearest-neighbour.
    Never upscale: a fractional enlargement doubles some pixel rows and not
    others, which visibly wrecks the grid."""
    tw, th = target
    im = Image.open(io.BytesIO(raw)).convert("RGBA")
    # Binary alpha: a soft edge reads as a halo once Godot draws it over ground.
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            px[x, y] = (r, g, b, 255 if a > 128 else 0)
    bbox = im.getbbox()
    if bbox:
        im = im.crop(bbox)
    # Integer upscale is grid-safe (every pixel doubles evenly); only the
    # fractional kind wrecks the grid. A tiny generation should still fill
    # its authored canvas.
    k = min(tw // max(1, im.width), th // max(1, im.height))
    if k > 1:
        im = im.resize((im.width * k, im.height * k), Image.NEAREST)
    if im.width > tw or im.height > th:
        sc = min(tw / im.width, th / im.height)
        im = im.resize((max(1, round(im.width * sc)), max(1, round(im.height * sc))), Image.NEAREST)
    out = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    out.paste(im, ((tw - im.width) // 2, th - im.height))     # sit on the canvas floor
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--id", action="append", dest="ids")
    ap.add_argument("--variations", type=int, default=3)
    ap.add_argument("--promote")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--out", default="assets/art/board/hero")
    args = ap.parse_args()

    if args.list:
        for name, job in JOBS.items():
            print(f"  {name:32} {job['size']}  {job['kind']}")
        return

    ledger = json.loads(LEDGER.read_text()) if LEDGER.is_file() else {"assets": {}, "masters": {}}

    if args.promote:
        name, _, idx = args.promote.partition(":")
        job = JOBS[name]
        src = CANDIDATES / name / f"{int(idx)}.png"
        if not src.is_file():
            sys.exit(f"no candidate {idx} for {name}")
        dest = ROOT / job.get("dest", f"{args.out}/{name}.png")
        dest.parent.mkdir(parents=True, exist_ok=True)
        conform(src.read_bytes(), job["size"]).save(dest)
        print(f"  promoted {name} candidate {idx} -> {dest.relative_to(ROOT)}")
        return

    names = args.ids or list(JOBS)
    style_ids = [v for v in ledger.get("masters", {}).values() if v]
    print(f"credits before: {call('GET', '/v1/api/credits').get('total')}")
    for name in names:
        job = JOBS[name]
        w, h = job["size"]
        payload = {"prompt": job["prompt"], "width": w, "height": h,
                   "variations": args.variations, "pixel": True,
                   "bg_mode": "transparent", "smart_crop": True,
                   "smart_crop_mode": "tightest", "mode": "assets"}
        if style_ids:
            payload["style_asset_ids"] = style_ids[:10]
        started = time.time()
        result = call("POST", "/v1/api/generate-sync", payload)
        assets = result.get("assets") or []
        if not assets:
            recent = call("GET", f"/v1/api/assets/recent?limit={args.variations}")
            assets = recent.get("assets") or []
        if not assets:
            print(f"  x {name}: no asset returned")
            continue
        d = CANDIDATES / name
        d.mkdir(parents=True, exist_ok=True)
        for i, a in enumerate(assets):
            (d / f"{i}.png").write_bytes(download(a["url"]))
        print(f"  ok {name:32} {len(assets)} candidates  {result.get('credits_used')}cr  "
              f"{time.time() - started:.0f}s  -> {d.relative_to(ROOT)}")
    print(f"credits after: {call('GET', '/v1/api/credits').get('total')}")


if __name__ == "__main__":
    main()
