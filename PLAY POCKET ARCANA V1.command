#!/usr/bin/env bash
# Legacy V1 comparison launcher. Normal Pocket Arcana launch now opens V2.
cd "$(dirname "$0")"
GODOT="${GODOT:-$HOME/godot-editor/Godot.app/Contents/MacOS/Godot}"
if [ ! -x "$GODOT" ]; then
  echo "Godot not found at $GODOT" >&2
  read -n 1 -s -r -p "Press any key to close."
  exit 1
fi
exec "$GODOT" --path . --scene res://scenes/main.tscn
