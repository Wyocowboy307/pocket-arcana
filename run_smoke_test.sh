#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if command -v godot4 >/dev/null 2>&1; then GODOT=godot4
elif command -v godot >/dev/null 2>&1; then GODOT=godot
else
  echo "Godot executable not found. Open scenes/self_test.tscn manually in Godot." >&2
  exit 127
fi
"$GODOT" --headless --path . --scene res://scenes/self_test.tscn
