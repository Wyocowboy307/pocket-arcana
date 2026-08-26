#!/usr/bin/env bash
cd "$(dirname "$0")"
GODOT="${GODOT:-$HOME/godot-editor/Godot.app/Contents/MacOS/Godot}"
if [ ! -x "$GODOT" ]; then
  echo "Godot not found at $GODOT" >&2
  read -n 1 -s -r -p "Press any key to close."
  exit 1
fi
# Double-click to play Pocket Arcana (V3 lane battler). Drag me to the Desktop if you like.
exec "$GODOT" --path . --scene res://scenes/v3/main_v3.tscn
