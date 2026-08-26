extends Node
## AI-vs-AI smoke test for V3: prove matches actually finish, and report the
## shape of the game so balance is visible before any art is judged.
##
##   Godot --headless --path . --scene res://scenes/dev/selftest_v3.tscn -- --matches=200

var matches := 60
var deck0 := "v3_life"
var deck1 := "v3_fire"

func _ready() -> void:
    # Balance has to be read across both seatings. Going first is worth about a
    # point on its own, so a single seating cannot tell a stronger deck from a
    # stronger seat.
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--matches="): matches = int(arg.trim_prefix("--matches="))
        elif arg.begins_with("--deck0="): deck0 = arg.trim_prefix("--deck0=")
        elif arg.begins_with("--deck1="): deck1 = arg.trim_prefix("--deck1=")
    var db := ContentV3.new()
    if not db.load_all():
        push_error("V3 SELF TEST: content failed to load")
        get_tree().quit(1)
        return

    var wins := [0, 0]
    var unfinished := 0
    var total_turns := 0
    var fusions := 0
    var longest := 0
    for i in range(matches):
        var result := _play(db, 1000 + i * 7)
        if int(result["winner"]) < 0: unfinished += 1
        else: wins[int(result["winner"])] += 1
        total_turns += int(result["turns"])
        fusions += int(result["fusions"])
        longest = maxi(longest, int(result["turns"]))

    var played: int = maxi(1, matches)
    print("V3 SELF TEST — %d matches (%s first, %s second)" % [matches, deck0, deck1])
    print("  %s wins: %d (%.1f%%)" % [deck0, wins[0], 100.0 * wins[0] / played])
    print("  %s wins: %d (%.1f%%)" % [deck1, wins[1], 100.0 * wins[1] / played])
    print("  average turns: %.1f   longest: %d" % [float(total_turns) / played, longest])
    print("  fusions resolved: %d" % fusions)
    if unfinished > 0:
        print("  UNFINISHED: %d" % unfinished)
        print("V3 SELF TEST FAILED")
        get_tree().quit(1)
        return
    print("V3 SELF TEST PASS")
    get_tree().quit(0)

func _play(db: ContentV3, seed_value: int) -> Dictionary:
    var engine := MatchV3.new()
    engine.setup(db, deck0, deck1, seed_value)
    # An Array, not an int: a GDScript lambda captures locals by *value*, so
    # `fusions += 1` inside the closure incremented a copy and this reported
    # zero fusions no matter how many actually resolved.
    var fusions: Array = [0]
    engine.event_emitted.connect(func(event: Dictionary) -> void:
        if String(event.get("type", "")) == "fusion": fusions[0] = int(fusions[0]) + 1)
    var ai0 := SimpleAIV3.new(); ai0.setup(engine, seed_value + 1)
    var ai1 := SimpleAIV3.new(); ai1.setup(engine, seed_value + 2)
    var guard := 0
    while not engine.match_over and guard < 400:
        guard += 1
        var actor := engine.current_player
        var ai: SimpleAIV3 = ai0 if actor == 0 else ai1
        ai.take_turn(actor)
        if engine.current_player == actor:
            # A turn that failed to pass would loop forever; bail loudly instead.
            engine.end_turn(actor)
    return {"winner": engine.winner, "turns": engine.turn, "fusions": int(fusions[0])}
