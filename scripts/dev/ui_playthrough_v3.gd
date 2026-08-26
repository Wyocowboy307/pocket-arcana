extends Node
## Drive complete V3 matches through the real screen.
##
##   Godot --path . --scene res://scenes/dev/ui_playthrough_v3.tscn -- --matches=3
##
## The rule tests prove the simulation; this proves the *view* survives a whole
## match — every event handler, every choreography act, fusion, commander powers
## and the end-of-match state. It needs a window, because the board draws.

var matches := 3
var main: Node
var failures: Array[String] = []

func _ready() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--matches="): matches = int(arg.trim_prefix("--matches="))
    main = load("res://scenes/v3/main_v3.tscn").instantiate()
    add_child(main)
    # The screen drives the rival itself on a timer. This harness drives both
    # seats explicitly, so hand it the wheel — otherwise the screen takes the
    # rival's turn during our settle frame and it looks like the turn bounced
    # straight back to the player.
    main.ai_busy = true
    await _settle(20)
    for i in range(matches):
        await _one_match(20250826 + i * 31)
    print("")
    if failures.is_empty():
        print("V3 UI PLAYTHROUGH PASS — %d matches driven through the screen." % matches)
        get_tree().quit(0)
    else:
        print("V3 UI PLAYTHROUGH FAILED:")
        for f in failures: print("  ✗ ", f)
        get_tree().quit(1)

func _settle(n: int) -> void:
    for _i in range(n): await get_tree().process_frame

func _one_match(seed_value: int) -> void:
    var engine: MatchV3 = main.engine
    engine.setup(main.db, "v3_life", "v3_fire", seed_value)
    main.ai.setup(engine, seed_value + 1)
    # A second brain for the human seat, so both sides are actually played.
    var human_ai := SimpleAIV3.new()
    human_ai.setup(engine, seed_value + 2)
    main.call("_clear")

    var guard := 0
    while not engine.match_over and guard < 300:
        guard += 1
        var actor: int = engine.current_player
        if actor == 0: human_ai.take_turn(0)
        else: main.ai.take_turn(1)
        _flush()
        main.call("_refresh")
        await _settle(1)
        # A turn that ends the match legitimately does not pass the seat on.
        if engine.match_over: break
        if engine.current_player == actor:
            failures.append("turn %d did not pass for player %d" % [engine.turn, actor])
            return
    if not engine.match_over:
        failures.append("match with seed %d never finished (%d turns)" % [seed_value, engine.turn])
        return
    if engine.winner < 0:
        failures.append("match with seed %d finished with no winner" % seed_value)

## Run the queued choreography now instead of over the next few seconds. The
## handlers have already run; this exercises the board.play() calls they queued.
func _flush() -> void:
    var guard := 0
    while not main._queue.is_empty() and guard < 400:
        guard += 1
        var step: Dictionary = main._queue.pop_front()
        var fn: Callable = step["run"]
        fn.call()
