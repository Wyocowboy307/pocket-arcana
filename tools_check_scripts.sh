#!/usr/bin/env bash
# Pocket Arcana — parse-check every GDScript file with the real Godot binary.
# Usage: ./tools_check_scripts.sh   (set GODOT=/path/to/Godot to override)
cd "$(dirname "$0")"
GODOT="${GODOT:-$HOME/godot-editor/Godot.app/Contents/MacOS/Godot}"
if [ ! -x "$GODOT" ]; then
  if command -v godot4 >/dev/null 2>&1; then GODOT=godot4
  elif command -v godot >/dev/null 2>&1; then GODOT=godot
  else echo "Godot executable not found. Set GODOT=/path/to/Godot" >&2; exit 127; fi
fi
fail=0
while IFS= read -r f; do
  out="$("$GODOT" --headless --path . --check-only --script "res://$f" 2>&1 \
        | grep -E "SCRIPT ERROR|Parse Error|Compile Error|at: GDScript" | grep -v "^WARNING")"
  if [ -n "$out" ]; then
    echo "FAIL  $f"
    echo "$out" | sed 's/^/      /'
    fail=1
  else
    echo "ok    $f"
  fi
done < <(find scripts -name '*.gd' | sort)
if [ "$fail" -eq 0 ]; then echo "All GDScript files parse cleanly."; fi
exit "$fail"
