#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
GODOT="${GODOT:-$HOME/godot-editor/Godot.app/Contents/MacOS/Godot}"
if [ ! -x "$GODOT" ]; then
  if command -v godot4 >/dev/null 2>&1; then GODOT=godot4
  elif command -v godot >/dev/null 2>&1; then GODOT=godot
  else
    echo "Godot executable not found. Set GODOT=/path/to/Godot" >&2
    exit 127
  fi
fi
"$GODOT" --headless --path . --scene res://scenes/self_test.tscn
