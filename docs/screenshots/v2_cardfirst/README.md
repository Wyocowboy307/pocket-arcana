# Card-first battlefield — review captures

The card is the permanent battlefield piece. Creatures live inside their frame
and only come out to act.

Captured from the running game at 1280x720:

    Godot --path . --scene res://scenes/dev/screenshot_v2.tscn --resolution 1280x720 \
        -- --out=<abs>.png --scenario=<name> [--beat=<0..1> --hold=<act kind>]

`--beat` freezes the choreography at an exact fraction of a named act instead of
guessing with `--delay`. Acts are scheduled some way into the future and their
durations differ by kind, so timing an animation capture by wall-clock delay is
unreliable; `--hold` names which act to freeze, because the opening Realm build
fires before any attack and was otherwise the one being caught.

| File | Scenario | Beat | Shows |
| --- | --- | --- | --- |
| `01_opening.png` | `v2_opening` | — | Opening board |
| `02_land_transform.png` | `v2_land_grow` | `land_build` 0.66 | A Realm card transforming its lane |
| `03_three_each.png` | `v2_three_each` | — | Three cards deployed a side |
| `04_creature_attack.png` | `v2_attack` | `attack` 0.42 | Great Stag charging out of its card |
| `05_dragon_attack.png` | `v2_dragon` | `attack` 0.52 | Garden Dragon rearing over its card |
| `06_place_support.png` | `v2_place_built` | — | A Place supporting its lane |
| `07_fusion.png` | `v2_fusion` | `fusion` 0.40 | Two cards converging into light |
| `08_late.png` | `v2_late_clear` | — | Late-game full battlefield |
| `09_select_glow.png` | `v2_select_grove` | — | Valid Grove land lit for a selected card |
| `10_sanctuaries.png` | `v2_sanctuaries` | — | Both homes framing from the rail |
| `11_heart_strike.png` | `v2_heart` | `heart_attack` 0.62 | Heart strike |
| `12_summon.png` | `v2_summon` | `summon` 0.70 | A card arriving on the battlefield |

Scenarios ending in `_clear`, plus `v2_sanctuaries` and `v2_three_each`, hide the
tutorial coach, which otherwise covers the top of the board.
