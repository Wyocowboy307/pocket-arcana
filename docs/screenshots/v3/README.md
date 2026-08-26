# V3 elemental lane battler — review captures

Captured from the running game at 1280x720:

    Godot --path . --scene res://scenes/dev/screenshot_v3.tscn --resolution 1280x720 \
        -- --out=<abs>.png --scenario=<name> [--beat=<0..1> --hold=<act kind>]

`--beat` freezes a named act at an exact fraction. Timing an animation capture by
wall-clock delay is guesswork: acts queue behind one another and durations differ
by kind, so `--hold` names which one to freeze.

| File | Scenario | Shows |
| --- | --- | --- |
| `1_opening.png` | `v3_opening` | Opening board: four empty lanes a side |
| `2_land.png` | `v3_land` (beat 0.55) | A Grove Landscape taking hold of a lane |
| `3_three_each.png` | `v3_three_each` | Three creatures deployed a side |
| `4_attack.png` | `v3_attack` (beat 0.40) | Bloom Bear rising out of its card to strike |
| `5_dragon.png` | `v3_dragon` (beat 0.48) | Garden Dragon rearing over its own card |
| `6_support.png` | `v3_support` | Supports attached to their lanes |
| `7_fusion.png` | `v3_fusion` (beat 0.45) | Two cards converging into light |
| `8_late.png` | `v3_late` | Late board: every lane built |
| `9_select.png` | `v3_select` | Selecting a Grove creature lights the legal lanes |
