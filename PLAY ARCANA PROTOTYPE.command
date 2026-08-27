#!/usr/bin/env bash
cd "$(dirname "$0")"
GODOT="${GODOT:-$HOME/godot-editor/Godot.app/Contents/MacOS/Godot}"
if [ ! -x "$GODOT" ]; then
  echo "Godot not found at $GODOT" >&2
  read -n 1 -s -r -p "Press any key to close."
  exit 1
fi
# The 2.5D visual prototype. Separate from the V1/V2/V3 game scenes.
exec "$GODOT" --path . --scene res://scenes/proto/arcana_visual_prototype.tscn
