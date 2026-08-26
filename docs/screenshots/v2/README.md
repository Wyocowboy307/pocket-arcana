# V2 prototype screenshots

Regenerate any of these with the V2 review harness:

    GODOT=~/godot-editor/Godot.app/Contents/MacOS/Godot
    "$GODOT" --path . --resolution 1280x720 \
        --scene res://scenes/dev/screenshot_v2.tscn -- \
        --out="$PWD/docs/screenshots/v2/<name>.png" --scenario=<name> [--delay=<s>]

Animation beats need `--delay` to land on a specific phase, e.g.
`--scenario=v2_dragon --delay=0.44 --frames=1`.

| file | what it shows |
| --- | --- |
| `v2_opening.png` | match start: both signature lands growing, empty realm slots |
| `v2_board.png` | a mid-match position on both sides |
| `v2_card_selected.png` | a Creature selected — only its Groves light, everything else darkens |
| `v2_attack_targeting.png` | an attack chosen, showing the lane it will cross |
| `v2_land_build.png` | Realm card growing land, mid rune-circle |
| `v2_summon.png` | a creature arriving through its element portal |
| `v2_attack.png` | a melee lunge on its impact beat |
| `v2_dragon.png` | dragon breath crossing the front line |
| `v2_heart.png` | an open lane reaching the Sanctuary; Heart shaking |
| `v2_fusion.png` | Fusion at the flash/name-reveal beat |

Play V2 directly:

    "$GODOT" --path . --scene res://scenes/v2/main_v2.tscn

V1 is unchanged and still runs from `res://scenes/main.tscn`.
