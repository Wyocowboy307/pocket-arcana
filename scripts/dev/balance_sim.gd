extends Node
## Batch AI-vs-AI playtester. Reports who wins, how, and how long matches run.
##
##   Godot --headless --path . --scene res://scenes/dev/balance.tscn -- \
##         --matches=200 [--deck0=starter_life] [--deck1=starter_fire] [--verbose]

var db := ContentDatabase.new()
var matches := 200
var deck0 := "starter_life"
var deck1 := "starter_fire"
var verbose := false

func _ready() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--matches="): matches = int(arg.trim_prefix("--matches="))
        elif arg.begins_with("--deck0="): deck0 = arg.trim_prefix("--deck0=")
        elif arg.begins_with("--deck1="): deck1 = arg.trim_prefix("--deck1=")
        elif arg == "--verbose": verbose = true
    if not db.load_all():
        push_error("BALANCE: content failed to load")
        get_tree().quit(1)
        return

    var wins := [0, 0]
    var reasons := {}
    var reasons_by_winner := [{}, {}]
    var unfinished := 0
    var total_actions := 0
    var total_chapters := 0
    var heart_totals := [0, 0]
    var wonder_totals := [0, 0]
    var heart_attacks := 0
    var recipes := 0
    var kept := {"total": 0, "samples": 0}
    var solo_actions := 0
    var solo_shapes := 0
    var chapter_hist := {}

    for i in range(matches):
        var engine := MatchEngine.new()
        add_child(engine)
        var counters := {"heart_attacks": 0, "recipes": 0}
        engine.event_emitted.connect(func(event: Dictionary) -> void:
            var t := String(event.get("type", ""))
            if t == "heart_attack": counters["heart_attacks"] += 1
            elif t == "recipe": counters["recipes"] += 1)
        engine.chapter_resolved.connect(func(summary: Dictionary) -> void:
            kept["total"] = int(kept["total"]) + int(summary["hand_sizes"][0]) + int(summary["hand_sizes"][1])
            kept["samples"] = int(kept["samples"]) + 2)
        engine.setup(db, deck0, deck1, 1000 + i)
        var steps := 0
        while not engine.match_over and steps < 1200:
            var actor: int = engine.current_player
            # Is the opponent already out of this Chapter?
            var alone: bool = bool(engine.players[1 - actor]["passed"])
            var act: Dictionary = engine.ai.choose_action(engine, actor)
            if alone and String(act.get("kind", "")) != "pass":
                solo_actions += 1
                if String(act.get("kind", "")) == "shape": solo_shapes += 1
            engine.perform(actor, act)
            steps += 1
        if not engine.match_over:
            unfinished += 1
        else:
            wins[engine.winner] += 1
            reasons[engine.win_reason] = int(reasons.get(engine.win_reason, 0)) + 1
            var bucket: Dictionary = reasons_by_winner[engine.winner]
            bucket[engine.win_reason] = int(bucket.get(engine.win_reason, 0)) + 1
        total_actions += steps
        total_chapters += engine.chapter
        chapter_hist[engine.chapter] = int(chapter_hist.get(engine.chapter, 0)) + 1
        heart_totals[0] += int(engine.players[0]["heart"])
        heart_totals[1] += int(engine.players[1]["heart"])
        wonder_totals[0] += int(engine.players[0]["wonder"])
        wonder_totals[1] += int(engine.players[1]["wonder"])
        heart_attacks += int(counters["heart_attacks"])
        recipes += int(counters["recipes"])
        if verbose:
            print("seed %d: P%d by %s in %d actions" % [1000 + i, engine.winner + 1, engine.win_reason, steps])
        engine.queue_free()

    var n := float(max(1, matches))
    print("")
    print("=== %s vs %s — %d matches ===" % [deck0, deck1, matches])
    print("P1 (%s) wins: %d (%.1f%%)" % [deck0, wins[0], 100.0 * wins[0] / n])
    print("P2 (%s) wins: %d (%.1f%%)" % [deck1, wins[1], 100.0 * wins[1] / n])
    if unfinished > 0: print("UNFINISHED: %d  <-- simulation problem" % unfinished)
    print("win reasons: %s" % str(reasons))
    print("  P1 (%s) wins by: %s" % [deck0, str(reasons_by_winner[0])])
    print("  P2 (%s) wins by: %s" % [deck1, str(reasons_by_winner[1])])
    print("avg actions/match: %.1f   avg final chapter: %.2f" % [total_actions / n, total_chapters / n])
    print("chapters reached: %s" % str(chapter_hist))
    print("avg final Heart: P1 %.1f  P2 %.1f" % [heart_totals[0] / n, heart_totals[1] / n])
    print("avg final Wonder: P1 %.1f  P2 %.1f" % [wonder_totals[0] / n, wonder_totals[1] / n])
    print("avg Heart strikes/match: %.1f   avg recipes/match: %.2f" % [heart_attacks / n, recipes / n])
    print("avg cards still in hand when a Chapter scores: %.2f" % (float(kept["total"]) / float(max(1, int(kept["samples"])))))
    print("avg free actions taken after the rival passed: %.2f (of which %.2f were Shapes)" % [solo_actions / n, solo_shapes / n])
    get_tree().quit(0)
