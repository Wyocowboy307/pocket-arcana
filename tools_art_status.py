"""Report which vertical-slice art assets exist and which are still missing.

    python3 tools_art_status.py          summary
    python3 tools_art_status.py --phase A   only the Phase-A master references
"""
from pathlib import Path
import json, sys

ROOT = Path(__file__).parent
prompts = json.loads((ROOT / "data/art_prompts_vertical_slice.json").read_text())

phase_filter = None
if "--phase" in sys.argv:
    phase_filter = sys.argv[sys.argv.index("--phase") + 1].upper()

rows = [p for p in prompts if phase_filter is None or p["phase"] == phase_filter]
by_phase = {}
for entry in rows:
    path = ROOT / entry["path"]
    ok = path.is_file() and path.stat().st_size > 0
    by_phase.setdefault(entry["phase"], []).append((ok, entry))

print("Pocket Arcana vertical-slice art status")
total_ok = total = 0
for phase in sorted(by_phase):
    items = by_phase[phase]
    done = sum(1 for ok, _ in items if ok)
    total_ok += done
    total += len(items)
    print(f"\nPhase {phase}: {done}/{len(items)}")
    for ok, entry in items:
        mark = "✓" if ok else "·"
        print(f"  {mark} {entry['id']:<30} {entry['kind']:<17} {entry['size']}  {entry['path']}")
print(f"\nTotal: {total_ok}/{total} assets present")
if total_ok < total:
    print("Missing assets fall back to procedural rendering — this is not an error.")
