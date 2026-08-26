#!/usr/bin/env python3
"""Author the V3 Life/Fire card set.

V3 costs are element-specific and you hold at most four Landscapes, so nothing
can cost more than 4 — the V1/V2 curve ran to 8 and had to be re-tuned rather
than reused. Card IDs are deliberately kept from the existing set so every
sprite, frame and portrait already produced carries straight over.

    python3 tools/build_v3_content.py
"""
import json
from pathlib import Path

ROOT = Path(__file__).parent.parent

LANDSCAPES = [
    {"id": "land_grove", "name": "Grove", "element": "life", "terrain": "grove",
     "rules": "Generates 1 Life each turn."},
    {"id": "land_cinder", "name": "Cinder", "element": "fire", "terrain": "cinder",
     "rules": "Generates 1 Fire each turn."},
]

# cost, power, health, rules, effect
CREATURES = {
    "life": [
        ("life_sproutling", "Sproutling", 1, 1, 3, "", None),
        ("life_moss_frog", "Moss Frog", 1, 2, 4, "", None),
        ("life_berrycap_bunny", "Berrycap Bunny", 2, 1, 4, "When played, draw 1.", {"kind": "draw", "amount": 1}),
        ("life_petal_deer", "Petal Deer", 2, 3, 4, "", None),
        ("life_rootback_boar", "Rootback Boar", 3, 2, 6, "When played, heal your Heart 2.", {"kind": "heal_heart", "amount": 2}),
        ("life_bloom_bear", "Bloom Bear", 3, 4, 6, "", None),
        ("life_great_stag", "Great Stag", 4, 5, 7, "", None),
        ("life_garden_dragon", "Garden Dragon", 4, 6, 8, "", None),
        ("life_elaria_mother_of_groves", "Elaria, Mother of Groves", 3, 8, 10,
         "Fusion only. When played, heal your Heart 4.", {"kind": "heal_heart", "amount": 4}),
    ],
    "fire": [
        ("fire_cinder_pup", "Cinder Pup", 1, 2, 1, "", None),
        ("fire_emberbug", "Emberbug", 1, 2, 1, "", None),
        ("fire_coal_chick", "Coal Chick", 2, 2, 2, "When played, draw 1.", {"kind": "draw", "amount": 1}),
        ("fire_ashcat", "Ashcat", 2, 3, 2, "", None),
        ("fire_cinder_hound", "Cinder Hound", 3, 3, 3, "When played, deal 1 to the rival Heart.", {"kind": "damage_heart", "amount": 1}),
        ("fire_forge_ram", "Forge Ram", 3, 4, 3, "", None),
        ("fire_magma_turtle", "Magma Turtle", 3, 4, 6, "", None),
        ("fire_blazewing_drake", "Blazewing Drake", 4, 6, 4, "", None),
        ("fire_rax_the_laughing_inferno", "Rax, the Laughing Inferno", 3, 9, 6,
         "Fusion only. When played, deal 3 to the rival Heart.", {"kind": "damage_heart", "amount": 3}),
    ],
}

SUPPORTS = {
    "life": [
        ("life_herbalist_hut", "Herbalist Hut", 2, "Creatures here heal 1 at end of turn.",
         {"kind": "heal_here", "amount": 1}),
        ("life_bee_garden", "Bee Garden", 3, "The creature here has +1 Power.",
         {"kind": "power_here", "amount": 1}),
    ],
    "fire": [
        ("fire_blacksmith_nook", "Blacksmith Nook", 2, "The creature here has +1 Power.",
         {"kind": "power_here", "amount": 1}),
        ("fire_ember_kitchen", "Ember Kitchen", 3, "When the creature here attacks, deal 1 to the rival Heart.",
         {"kind": "sear_on_attack", "amount": 1}),
    ],
}

SPELLS = {
    "life": [
        ("life_grow", "Grow", 1, "Heal a creature 3.", {"kind": "heal_creature", "amount": 3}, "creature"),
        ("life_warm_sun", "Warm Sun", 2, "Heal your Heart 4.", {"kind": "heal_heart", "amount": 4}, "none"),
    ],
    "fire": [
        ("fire_little_flame", "Little Flame", 1, "Deal 2 to a creature.", {"kind": "damage_creature", "amount": 2}, "creature"),
        ("fire_dragon_breath", "Dragon Breath", 3, "Deal 3 to the rival Heart.", {"kind": "damage_heart", "amount": 3}, "none"),
    ],
}

FUSIONS = [
    {"id": "fuse_great_stag", "name": "Antler Communion", "element": "life",
     "sources": ["life_sproutling", "life_petal_deer"], "result": "life_great_stag", "cost": 2,
     "flavour": "The sprout climbs the deer's antlers and they grow together."},
    {"id": "fuse_elaria", "name": "Mother of Groves", "element": "life",
     "sources": ["life_bloom_bear", "life_great_stag"], "result": "life_elaria_mother_of_groves", "cost": 3,
     "flavour": "Bear and stag kneel; the grove itself stands up."},
    {"id": "fuse_cinder_hound", "name": "Kindled Pack", "element": "fire",
     "sources": ["fire_cinder_pup", "fire_coal_chick"], "result": "fire_cinder_hound", "cost": 2,
     "flavour": "Two small fires agree to be one big one."},
    {"id": "fuse_rax", "name": "The Laughing Inferno", "element": "fire",
     "sources": ["fire_forge_ram", "fire_blazewing_drake"], "result": "fire_rax_the_laughing_inferno", "cost": 3,
     "flavour": "The ram charges into the drake's fire and something laughs back out."},
]

COMMANDERS = [
    {"id": "cmd_mossy_mae", "name": "Mossy Mae", "element": "life",
     "passive_name": "Verdant Care",
     "passive_text": "At the end of your turn, each of your creatures on Grove heals 2.",
     "passive": {"kind": "heal_on_terrain", "terrain": "grove", "amount": 2},
     "power_name": "Wild Spring", "power_text": "Once per match: draw 2 cards.",
     "power": {"kind": "draw", "amount": 2}, "power_target": "none"},
    {"id": "cmd_poppy_cinder", "name": "Poppy Cinder", "element": "fire",
     "passive_name": "Forge Heat",
     "passive_text": "Your creatures on Cinder have +1 Power.",
     "passive": {"kind": "power_on_terrain", "terrain": "cinder", "amount": 1},
     "power_name": "Ember Rush",
     "power_text": "Once per match: deal 3 to one enemy creature, or to the rival Heart.",
     "power": {"kind": "burst", "amount": 3}, "power_target": "enemy_lane"},
]

TERRAIN_FOR = {"life": "grove", "fire": "cinder"}


def build():
    cards = []
    for land in LANDSCAPES:
        cards.append({
            "id": land["id"], "name": land["name"], "type": "landscape",
            "element": land["element"], "terrain": land["terrain"],
            "cost": 0, "rules": land["rules"], "play_on": "",
        })
    for element, rows in CREATURES.items():
        for cid, name, cost, power, health, rules, effect in rows:
            cards.append({
                "id": cid, "name": name, "type": "creature", "element": element,
                "cost": cost, "power": power, "health": health, "rules": rules,
                "play_on": TERRAIN_FOR[element],
                "effect": effect, "fusion_only": "Fusion only" in rules,
            })
    for element, rows in SUPPORTS.items():
        for cid, name, cost, rules, effect in rows:
            cards.append({
                "id": cid, "name": name, "type": "support", "element": element,
                "cost": cost, "rules": rules, "play_on": TERRAIN_FOR[element],
                "effect": effect,
            })
    for element, rows in SPELLS.items():
        for cid, name, cost, rules, effect, target in rows:
            cards.append({
                "id": cid, "name": name, "type": "spell", "element": element,
                "cost": cost, "rules": rules, "play_on": "",
                "effect": effect, "target": target,
            })
    return cards


def decks(cards):
    by_id = {c["id"]: c for c in cards}
    out = []
    for element, land_id, commander in (("life", "land_grove", "cmd_mossy_mae"),
                                        ("fire", "land_cinder", "cmd_poppy_cinder")):
        entries = [{"card_id": land_id, "count": 10}]
        for c in cards:
            if c.get("element") != element or c["id"] == land_id:
                continue
            if c.get("fusion_only"):
                continue                      # only reachable through Fusion
            count = 3 if c["cost"] <= 2 else 2
            entries.append({"card_id": c["id"], "count": count})
        out.append({"id": "v3_%s" % element, "name": "%s Starter" % element.title(),
                    "element": element, "commander_id": commander, "cards": entries})
    return out


def main():
    cards = build()
    (ROOT / "data/v3_set.json").write_text(json.dumps(cards, indent=2) + "\n")
    (ROOT / "data/v3_fusions.json").write_text(json.dumps(FUSIONS, indent=2) + "\n")
    (ROOT / "data/v3_commanders.json").write_text(json.dumps(COMMANDERS, indent=2) + "\n")
    built = decks(cards)
    (ROOT / "data/v3_decks.json").write_text(json.dumps(built, indent=2) + "\n")
    for deck in built:
        total = sum(e["count"] for e in deck["cards"])
        lands = sum(e["count"] for e in deck["cards"] if e["card_id"].startswith("land_"))
        print(f"  {deck['id']:10} {total:3} cards ({lands} landscapes)")
    print(f"cards: {len(cards)}  fusions: {len(FUSIONS)}  commanders: {len(COMMANDERS)}")


if __name__ == "__main__":
    main()
