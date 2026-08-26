extends Node

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
        var action := engine.ai.choose_action(engine, player)
        var kind := String(action.get("kind", "pass"))
        if kind == "play_card":
            engine.play_card(player, String(action["card_id"]), action["pos"])
        elif kind == "shape":
            engine.shape(player, String(action["element"]), action["pos"])
        else:
            engine.pass_chapter(player)
        steps += 1
    if not engine.match_over:
        push_error("SELF TEST: match failed to finish in %d actions" % max_steps)
        get_tree().quit(2)
        return
    print("SELF TEST PASS: completed in %d actions" % steps)
    print("Last events:")
    for line in engine.event_log:
        print("  ", line)
    get_tree().quit(0)
