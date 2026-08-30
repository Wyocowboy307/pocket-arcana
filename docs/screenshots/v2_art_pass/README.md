# V2 art pass — final capture set (2026-08-30)

Every capture is shot through the deterministic harness (the rival is frozen
before its opening turn and the opening ceremony is flushed):

    Godot --path . --scene res://scenes/dev/screenshot_v2.tscn --resolution 1280x720 \
        -- --out=/abs/shot.png --scenario=v2_late

Held action beats use `--beat=<0..1> --hold=<kind>`. The full set is scripted
in the session scratchpad's capture_final.sh; the scenario list lives in
scripts/dev/screenshot_v2.gd (including the new v2_victory / v2_defeat).

The set walks the whole visual language locked in docs/V2_ART_PASS_TRIAGE.md:
table + sockets (01), slabs built and merging (02-03, 21-22), targeting with
the ghost preview (04-05), pieces standing on the world (06-09, 17-19),
combat and the Heart strike chain (10-12, 16), the fusion ceremony (13-14),
spells (15), homes and Hearts (20), and the match end with the winner's
portrait (23-24).
