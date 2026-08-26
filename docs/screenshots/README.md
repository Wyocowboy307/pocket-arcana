# Match screen screenshots

Regenerate any of these with the screenshot harness:

    GODOT=~/godot-editor/Godot.app/Contents/MacOS/Godot
    "$GODOT" --path . --resolution 1280x720 \
        --scene res://scenes/dev/screenshot.tscn -- \
        --out="$PWD/docs/screenshots/<name>.png" --scenario=<name>

| file | what it shows |
| --- | --- |
| `opening.png` | empty battlefield at the start of a match |
| `art_review.png` | Phase-A capture: Life on Grove, Fire on Cinder, a dragon a side, Ashbloom |
| `midgame.png` | a real AI-vs-AI position |
| `hand_hover.png` | the hand behaving like a card game — pointed-at card raised and enlarged |
| `heart_strike.png` | targeting state: indicators appear only while aiming |
| `chapter_overlay.png` | Chapter result overlay |
