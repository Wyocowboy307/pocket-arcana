extends Node
## Headless AI-vs-AI smoke test. Run with:
##   ./run_smoke_test.sh

var db := ContentDatabase.new()
var engine := MatchEngine.new()
var max_steps := 500

func _ready() -> void:
    if not db.load_all():
        push_error("SELF TEST: content failed to load")
        get_tree().quit(1)
        return
    add_child(engine)
    engine.setup(db, "starter_life", "starter_fire")
    var steps := 0
    while not engine.match_over and steps < max_steps:
        var player := engine.current_player
        engine.perform(player, engine.ai.choose_action(engine, player))
        steps += 1
    if not engine.match_over:
        push_error("SELF TEST: match failed to finish in %d actions" % max_steps)
        get_tree().quit(2)
        return
    print("SELF TEST PASS: completed in %d actions" % steps)
    print("Winner: P%d (%s)" % [engine.winner + 1, engine.win_reason])
    print("Hearts: %d / %d   Seals: %d / %d   Wonder: %d / %d" % [
        engine.players[0]["heart"], engine.players[1]["heart"],
        engine.players[0]["seals"], engine.players[1]["seals"],
        engine.players[0]["wonder"], engine.players[1]["wonder"]])
    print("Last events:")
    for line in engine.event_log:
        print("  ", line)
    get_tree().quit(0)
