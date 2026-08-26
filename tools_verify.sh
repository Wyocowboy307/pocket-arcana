#!/usr/bin/env bash
# Pocket Arcana — run every check in one go.
#   ./tools_verify.sh            fast checks
#   ./tools_verify.sh --balance  also run the 200-match balance sim (slow)
#
# Set GODOT=/path/to/Godot to override the binary.
cd "$(dirname "$0")"
GODOT="${GODOT:-$HOME/godot-editor/Godot.app/Contents/MacOS/Godot}"
if [ ! -x "$GODOT" ]; then
  if command -v godot4 >/dev/null 2>&1; then GODOT=godot4
  elif command -v godot >/dev/null 2>&1; then GODOT=godot
  else echo "Godot executable not found. Set GODOT=/path/to/Godot" >&2; exit 127; fi
fi
export GODOT
fail=0
step() { echo; echo "=== $* ==="; }

step "content validation"
python3 tools_validate_content.py || fail=1
python3 tools_content_audit.py || fail=1

step "GDScript parse check"
./tools_check_scripts.sh | tail -1 || fail=1

step "simulation regression suite"
"$GODOT" --headless --path . --scene res://scenes/dev/tests.tscn 2>&1 | grep -E "TESTS|✗" || fail=1
"$GODOT" --headless --path . --scene res://scenes/dev/tests.tscn 2>&1 | grep -q "TESTS PASS" || fail=1

step "AI-vs-AI smoke test"
./run_smoke_test.sh 2>&1 | grep -E "SELF TEST|Winner" || fail=1

step "full match driven through the UI"
"$GODOT" --headless --path . --scene res://scenes/dev/ui_playthrough.tscn -- --matches=5 2>&1 | grep -E "UI PLAYTHROUGH|✗" || fail=1
"$GODOT" --headless --path . --scene res://scenes/dev/ui_playthrough.tscn -- --matches=5 2>&1 | grep -q "UI PLAYTHROUGH PASS" || fail=1

step "V2 prototype simulation"
"$GODOT" --headless --path . --scene res://scenes/dev/tests_v2.tscn 2>&1 | grep -E "V2 TESTS|✗" || fail=1
"$GODOT" --headless --path . --scene res://scenes/dev/tests_v2.tscn 2>&1 | grep -q "V2 TESTS PASS" || fail=1

step "V2 match driven through the V2 screen"
"$GODOT" --headless --path . --scene res://scenes/dev/ui_playthrough_v2.tscn -- --matches=3 2>&1 | grep -E "V2 UI PLAYTHROUGH|✗" || fail=1
"$GODOT" --headless --path . --scene res://scenes/dev/ui_playthrough_v2.tscn -- --matches=3 2>&1 | grep -q "V2 UI PLAYTHROUGH PASS" || fail=1

if [ "${1:-}" = "--balance" ]; then
  step "slice balance, both seatings (slow)"
  "$GODOT" --headless --path . --scene res://scenes/dev/balance.tscn -- --matches=200 2>&1 | grep -E "wins:|wins by|UNFINISHED"
  "$GODOT" --headless --path . --scene res://scenes/dev/balance.tscn -- --matches=200 --deck0=starter_fire --deck1=starter_life 2>&1 | grep -E "wins:|wins by|UNFINISHED"
fi

echo
if [ "$fail" -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "SOMETHING FAILED"; fi
exit "$fail"
