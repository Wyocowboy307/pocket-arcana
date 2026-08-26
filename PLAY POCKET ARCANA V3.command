#!/bin/bash
# Double-click to play the V3 elemental lane battler.
cd "$(dirname "$0")"
"$HOME/godot-editor/Godot.app/Contents/MacOS/Godot" --path . --scene res://scenes/v3/main_v3.tscn
