# V2 battlefield screenshots

    GODOT=~/godot-editor/Godot.app/Contents/MacOS/Godot
    "$GODOT" --path . --resolution 1280x720 \
        --scene res://scenes/dev/screenshot_v2.tscn -- \
        --out="$PWD/docs/screenshots/v2/<name>.png" --scenario=<name> [--delay=<s>]

Animation beats need `--delay` to land on a phase, e.g.
`--scenario=v2_attack --delay=0.44 --frames=1`.

| file | what it shows |
| --- | --- |
| `v2_opening.png` | match opening — both signature lands growing |
| `v2_one_grove.png` | a single Grove built, the rest dormant ground |
| `v2_three_lands.png` | three lands built, plots merging into one realm |
| `v2_facing.png` | creatures from opposing realms facing across the clash space |
| `v2_attack.png` | an attacker out in the clash space at the impact beat |
| `v2_heart.png` | an open lane reaching the Sanctuary; Heart shaking |
| `v2_place_built.png` | a Place constructed, linked to the creature it supports |
| `v2_fusion.png` | Fusion at the slam and name reveal |
| `v2_late.png` | late game — two fully developed realms |
| `v2_land_build.png` | vines crawling out as a Grove forms |
| `v2_card_selected.png` | a card selected: only its land lights, the rest darkens |

Play V2: `Godot --path .` (V2 is the default scene).
V1 remains at `res://scenes/main.tscn`.
