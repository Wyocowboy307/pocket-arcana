"""Compose locked generation prompts for the Life/Fire vertical slice.

Every prompt is built from data/vertical_slice_art_manifest.json plus the
mandatory clauses in docs/ART_BIBLE.md, so the style lock cannot drift between
assets. Writes data/art_prompts_vertical_slice.json.

    python3 tools_build_art_prompts.py
"""
from pathlib import Path
import json

ROOT = Path(__file__).parent
MANIFEST = json.loads((ROOT / "data/vertical_slice_art_manifest.json").read_text())

# ART_BIBLE.md "AI generation rules" — required in every prompt.
NEGATIVE = ("no text, no letters, no numbers, no watermark, no frame, no border, "
            "no anti-aliasing, no smooth vector edges, no gradients, no 3D render, "
            "no painterly texture, no photorealism, no drop shadow")
BASE = ("Pocket Arcana pixel art. Cute magical storybook fantasy, chunky readable "
        "silhouette, clean pixel clusters, 1px dark coloured outline (not pure black), "
        "single light source from the upper left, limited harmonious palette, "
        "crisp hard pixel edges")
WORLD_VIEW = "top-down with a slight 3/4 overhead board perspective, never a side-view battle sprite"

ELEMENT = {
    "life": {
        "palette": "spring green with warm cream and petal accents",
        "motifs": "leaves, sprouts, berries, flowers, antlers, mushrooms",
        "terrain": "lush grove, flowers, roots, tiny grass",
    },
    "fire": {
        "palette": "orange-red with hot cream and yellow cores and charcoal accents",
        "motifs": "flames, embers, triangular aggressive shapes",
        "terrain": "cinder soil, scorched grass, glowing cracks",
    },
}

# Corrections learned from reviewing real generations. Kept here so a prompt
# rebuild never silently reverts them.
MOTIF_OVERRIDE = {
    # Antlers and twigs became noisy 1px detail that vanished at board scale.
    "life_sproutling": ("leaves and sprouts only. Two big bold leaves are the whole "
                        "silhouette — no antlers, no twigs, no thin branches"),
}

# The eight Phase-A references that lock the master look.
PHASE_A = {
    "cmd_mossy_mae", "cmd_poppy_cinder",
    "life_sproutling", "fire_cinder_pup",
    "life_garden_dragon", "fire_blazewing_drake",
    "grove", "cinder",
}


def el(element, key):
    return ELEMENT.get(element, {}).get(key, "")


def sprite_prompt(name, element, size, silhouette, card_id=None):
    motifs = MOTIF_OVERRIDE.get(card_id, el(element, "motifs"))
    return (f"{BASE}, {el(element,'palette')}. "
            f"Subject: {name} — {silhouette}. "
            f"Element motifs: {motifs}. "
            f"View: {WORLD_VIEW}. "
            f"Exactly {size[0]}x{size[1]} pixels, fully transparent background, "
            f"single centred object with nothing baked behind it, "
            f"must stay readable at {size[0]}px on a dark game board. {NEGATIVE}.")


def terrain_prompt(tid, elements, size, description):
    if len(elements) == 2:
        # ART_BIBLE: a reaction terrain must read as both parents, not an average.
        blend = (f"Must clearly read as BOTH {elements[0]} and {elements[1]} at once — "
                 f"do not average the two colours together.")
        palette = f"{el(elements[0],'palette')} combined with {el(elements[1],'palette')}"
    elif len(elements) == 1:
        blend = f"Terrain language: {el(elements[0],'terrain')}."
        palette = el(elements[0], "palette")
    else:
        blend = "Neutral ground with no element dominance."
        palette = "muted slate and soft stone greys"
    # These clauses exist because the first pass produced framed, high-contrast
    # plates that fought the creatures standing on them.
    return (f"{BASE}, {palette}. "
            f"Flat overhead ground texture: {description}. {blend} "
            f"This is BACKGROUND. Keep it low contrast, muted and quiet — much flatter "
            f"and duller than a character sprite, so creatures stand out on top of it. "
            f"Completely even flat lighting across the whole image: the edges must be "
            f"exactly as bright as the middle. "
            f"Absolutely no vignette, no darkened edges, no border, no frame, no outer "
            f"rim, no shadow around the outside, no glow. "
            f"Detail belongs near the corners and edges; keep the middle open and plain "
            f"because a creature sprite is drawn on top of it. "
            f"Fills the entire image edge to edge like a seamless repeating floor tile. "
            f"Exactly {size[0]}x{size[1]} pixels, fully opaque. {NEGATIVE}.")


def build():
    out = []

    for c in MANIFEST["commanders"]:
        element = c["element"]
        out.append({
            "id": c["id"], "kind": "commander_board", "element": element,
            "path": c["board_avatar"], "size": c["board_size"],
            "phase": "A" if c["id"] in PHASE_A else "B",
            "prompt": sprite_prompt(c["name"], element, c["board_size"], c["signature"]),
        })
        out.append({
            "id": c["id"], "kind": "commander_portrait", "element": element,
            "path": c["portrait"], "size": c["portrait_size"], "phase": "B",
            "prompt": (f"{BASE}, {el(element,'palette')}. "
                       f"Pixel-art character portrait of {c['name']} — {c['signature']}. "
                       f"Head and shoulders, facing the viewer, one signature prop clearly visible, "
                       f"simple face readable when shrunk to 64px. "
                       f"Exactly {c['portrait_size'][0]}x{c['portrait_size'][1]} pixels, "
                       f"simple flat element-coloured backdrop. {NEGATIVE}."),
        })

    for group, kind in (("creatures", "creature"), ("landmarks", "landmark")):
        for a in MANIFEST[group]:
            out.append({
                "id": a["card_id"], "kind": kind, "element": a["element"],
                "path": a["path"], "size": a["size"],
                "phase": "A" if a["card_id"] in PHASE_A else "B",
                "prompt": sprite_prompt(a["name"], a["element"], a["size"], a["silhouette"], a["card_id"]),
            })

    for t in MANIFEST["terrain"]:
        out.append({
            "id": t["id"], "kind": "terrain", "element": "+".join(t["elements"]),
            "path": t["path"], "size": t["size"],
            "phase": "A" if t["id"] in PHASE_A else "B",
            "prompt": terrain_prompt(t["id"], t["elements"], t["size"], t["description"]),
        })

    for s in MANIFEST["sanctuaries"]:
        element = s["id"].replace("sanctuary_", "")
        out.append({
            "id": s["id"], "kind": "sanctuary", "element": element,
            "path": s["path"], "size": s["size"], "phase": "B",
            "prompt": (f"{BASE}, {el(element,'palette')}. "
                       f"Top-down magical home tile: {s['description']}. "
                       f"View: {WORLD_VIEW}. Leave the centre open — a Heart number and an "
                       f"attack-target highlight are drawn on top. "
                       f"Exactly {s['size'][0]}x{s['size'][1]} pixels, opaque, fills the tile. {NEGATIVE}."),
        })

    for sp in MANIFEST["spell_visuals"]:
        element = "life" if sp["card_id"].startswith("life_") else "fire"
        out.append({
            "id": sp["card_id"], "kind": "spell_art", "element": element,
            "path": sp["path"], "size": [256, 160], "phase": "C",
            "prompt": (f"{BASE}, {el(element,'palette')}. "
                       f"Pixel-art card illustration for the spell {sp['name']}: {sp['motif']}. "
                       f"One clear focal action, expressive storybook scene, "
                       f"readable when shrunk into a 126x58 card window. "
                       f"Exactly 256x160 pixels. {NEGATIVE}."),
        })

    out.sort(key=lambda e: (e["phase"], e["kind"], e["id"]))
    (ROOT / "data/art_prompts_vertical_slice.json").write_text(
        json.dumps(out, indent=2, ensure_ascii=False) + "\n")
    by_phase = {}
    for e in out:
        by_phase[e["phase"]] = by_phase.get(e["phase"], 0) + 1
    print(f"wrote {len(out)} prompts -> data/art_prompts_vertical_slice.json")
    print("by phase:", dict(sorted(by_phase.items())))
    print("\nPhase A (the eight that lock the master look):")
    for e in out:
        if e["phase"] == "A":
            print(f"  {e['id']:<24} {e['kind']:<17} {e['size']}")


if __name__ == "__main__":
    build()
