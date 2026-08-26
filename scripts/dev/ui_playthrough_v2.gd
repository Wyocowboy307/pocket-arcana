extends Node
## Drives whole V2 matches through the real V2 screen entry points, so the
## selection/attack/fusion state machine is covered, not just the simulation.
##
##   Godot --headless --path . --scene res://scenes/dev/ui_playthrough_v2.tscn -- --matches=4

var matches := 4
var failures: Array[String] = []

func _ready() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--matches="): matches = int(arg.trim_prefix("--matches="))
    for i in range(matches):
        await _play(i)
    print("")
    if failures.is_empty():
        print("V2 UI PLAYTHROUGH PASS — %d matches driven through the screen." % matches)
        get_tree().quit(0)
    else:
        print("V2 UI PLAYTHROUGH FAILED:")
        for f in failures: print("  ✗ ", f)
        get_tree().quit(1)

func _play(index: int) -> void:
    var main: Node = load("res://scenes/v2/main_v2.tscn").instantiate()
    add_child(main)
    await get_tree().process_frame
    var engine: MatchV2 = main.engine
    var ai := SimpleAIV2.new()
    main.ai_busy = true                     # this harness drives both sides
    main.tutorial_active = false
    engine.setup(engine.db, "starter_life", "starter_fire", 3000 + index)
    main.call("_clear")

    var human_actions := 0
    var guard := 0
    while not engine.match_over and guard < 400:
        if engine.current_player == 0:
            human_actions += _drive_human(main, engine)
        else:
            ai.take_turn(engine, 1)
        guard += 1
        if guard % 12 == 0: await get_tree().process_frame

    if not engine.match_over:
        failures.append("match %d never finished (%d turns)" % [index, guard])
    if human_actions < 4:
        failures.append("match %d drove only %d screen actions" % [index, human_actions])
    if main.mode != "":
        failures.append("match %d left the screen in mode '%s'" % [index, main.mode])
    main.queue_free()
    await get_tree().process_frame

## Take one human turn using only the screen's own click handlers.
func _drive_human(main: Node, engine: MatchV2) -> int:
    var acted := 0
    # Build land when we can — this is the V2 ramp.
    if int(engine.players[0]["realm_stack"]) > 0 and not bool(engine.players[0]["played_card"]):
        for i in range(MatchV2.LANES):
            if String(engine.lane(0, i)["land"]) == "":
                main.call("_choose_realm")
                main.call("_on_lane_clicked", 0, i)
                acted += 1
                break
    # Otherwise play the first card that has a legal destination.
    if not bool(engine.players[0]["played_card"]):
        for card_any in engine.players[0]["hand"].duplicate():
            var cid := String(card_any)
            var targets: Array = engine.legal_targets(0, cid)
            if targets.is_empty(): continue
            main.call("_select_card", cid)
            var t: Dictionary = targets[0]
            main.call("_on_lane_clicked", int(t["side"]), int(t["lane"]))
            acted += 1
            break
    # Attack through the two-click path: pick the lane, then confirm opposite.
    if not bool(engine.players[0]["attacked"]):
        var lanes: Array = engine.legal_attacks(0)
        if not lanes.is_empty():
            var l := int(lanes[0])
            main.call("_on_lane_clicked", 0, l)
            main.call("_on_lane_clicked", 1, l)
            acted += 1
    main.call("_do_end_turn")
    return acted
