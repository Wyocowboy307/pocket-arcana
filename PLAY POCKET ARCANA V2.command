#!/usr/bin/env bash
cd "$(dirname "$0")"
GODOT="${GODOT:-$HOME/godot-editor/Godot.app/Contents/MacOS/Godot}"
if [ ! -x "$GODOT" ]; then
  echo "Godot not found at $GODOT" >&2
  read -n 1 -s -r -p "Press any key to close."
  exit 1
fi
# Previous milestone, kept for comparison until V3 proves itself.
exec "$GODOT" --path . --scene res://scenes/v2/main_v2.tscn
