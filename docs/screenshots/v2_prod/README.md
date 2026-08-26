# V2 production battlefield — review captures

Captured from the running game at 1280x720 with:

    Godot --path . --scene res://scenes/dev/screenshot_v2.tscn --resolution 1280x720 \
        -- --out=<abs>.png --scenario=<name> --delay=<seconds>

| File | Scenario | Shows |
| --- | --- | --- |
| `opening.png` | `v2_opening` | Opening battlefield |
| `grove_pair.png` | `v2_grove_pair` | Neighbouring Grove lands as one region |
| `cinder_pair.png` | `v2_cinder_pair` | Neighbouring Cinder lands as one region |
| `sanctuaries.png` | `v2_sanctuaries` | Both Sanctuaries, coach hidden |
| `midgame.png` | `v2_board` | Mid-match board with Places |
| `late.png` / `late_clear.png` | `v2_late` / `v2_late_clear` | Late-game fully built battlefield |
| `combat.png` | `v2_attack` | Creature combat: card lunge, death, damage |
| `dragon.png` | `v2_dragon` | A heavy attacker's contact beat |
| `spell.png` | `v2_spell` | Spell impact |
| `place_building.png` | `v2_place_building` | Place mid-construction |
| `place_done.png` | `v2_place_built` | Finished Place beside its creature |
| `fusion.png` | `v2_fusion` | Fusion core |
| `heart.png` | `v2_heart` | Heart strike |

`v2_sanctuaries` and `v2_late_clear` hide the tutorial coach, which otherwise
covers the rival's Sanctuary in every capture.
