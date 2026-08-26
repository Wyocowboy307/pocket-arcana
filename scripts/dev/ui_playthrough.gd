extends Node
## End-to-end check that the match screen itself survives a whole match.
##
##   Godot --headless --path . --scene res://scenes/dev/ui_playthrough.tscn -- [--matches=5]
##
## The human side is played through the real UI entry points (_select_card,
## _choose_shape, _on_tile_clicked, _do_pass), so this exercises the selection
## state machine, the two-step push flow and the overlays — not just the engine.

var matches := 5
var failures: Array[String] = []

func _ready() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--matches="): matches = int(arg.trim_prefix("--matches="))
    for i in range(matches):
        await _play_one(i)
    print("")
    if failures.is_empty():
        print("UI PLAYTHROUGH PASS — %d matches driven through the UI." % matches)
        get_tree().quit(0)
    else:
        print("UI PLAYTHROUGH FAILED:")
        for f in failures: print("  ✗ ", f)
        get_tree().quit(1)

func _play_one(index: int) -> void:
    var main: Node = load("res://scenes/main.tscn").instantiate()
    add_child(main)
    await get_tree().process_frame
    var engine: MatchEngine = main.engine
    # Freeze the screen's own AI loop; this harness drives both sides itself.
    main.ai_busy = true
    engine.setup(engine.db, "starter_life", "starter_fire", 9000 + index)
    main.call("_clear_selection")

    var steps := 0
    var human_actions := 0
    while not engine.match_over and steps < 1500:
        if main.overlay_open:
            main.call("_dismiss_overlay")
            continue
        var player: int = engine.current_player
        var action: Dictionary = engine.ai.choose_action(engine, player)
        if player == 0:
            _drive_human(main, engine, action)
            human_actions += 1
        else:
            engine.perform(player, action)
        steps += 1
        if steps % 40 == 0: await get_tree().process_frame

    if not engine.match_over:
        failures.append("match %d never finished (%d steps)" % [index, steps])
    if human_actions < 5:
        failures.append("match %d drove only %d actions through the UI" % [index, human_actions])
    # The selection state machine must not be left holding a stale selection.
    if main.mode != "" and not engine.match_over:
        failures.append("match %d ended with mode still '%s'" % [index, main.mode])
    main.queue_free()
    await get_tree().process_frame

## Replay one action the way a player would: click, then click again.
func _drive_human(main: Node, engine: MatchEngine, action: Dictionary) -> void:
    match String(action.get("kind", "pass")):
        "play_card":
            main.call("_select_card", String(action["card_id"]))
            main.call("_on_tile_clicked", action["pos"])
            if action.has("secondary"):
                main.call("_on_tile_clicked", action["secondary"])
        "shape":
            main.call("_choose_shape", String(action["element"]))
            main.call("_on_tile_clicked", action["pos"])
        "move":
            main.call("_on_tile_clicked", action["from"])
            main.call("_on_tile_clicked", action["to"])
        "attack_heart":
            main.call("_on_tile_clicked", action["from"])
            main.call("_on_tile_clicked", engine.sanctuary_pos(1))
        "command":
            main.call("_choose_command")
            main.call("_on_tile_clicked", action["pos"])
        _:
            main.call("_do_pass")
