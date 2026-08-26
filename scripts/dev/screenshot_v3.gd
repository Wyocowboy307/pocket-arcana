extends Node
## Review harness for the V3 lane battler.
##
##   Godot --path . --scene res://scenes/dev/screenshot_v3.tscn --resolution 1280x720 \
##       -- --out=/abs/shot.png --scenario=v3_midgame [--beat=0.5 --hold=attack]
##
## --beat freezes a named act at an exact fraction. Timing an animation capture
## by wall-clock delay is guesswork: acts are queued behind other acts and their
## durations differ by kind.

var out_path := "/tmp/v3.png"
var frames := 40
var scenario := "v3_opening"
var delay := 0.0
var beat := -1.0
var hold_kind := ""
var main: Node

func _ready() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--out="): out_path = arg.trim_prefix("--out=")
        elif arg.begins_with("--frames="): frames = int(arg.trim_prefix("--frames="))
        elif arg.begins_with("--scenario="): scenario = arg.trim_prefix("--scenario=")
        elif arg.begins_with("--delay="): delay = float(arg.trim_prefix("--delay="))
        elif arg.begins_with("--beat="): beat = float(arg.trim_prefix("--beat="))
        elif arg.begins_with("--hold="): hold_kind = arg.trim_prefix("--hold=")
    main = load("res://scenes/v3/main_v3.tscn").instantiate()
    add_child(main)
    await _settle(24)
    _freeze()
    await _run()
    if beat >= 0.0:
        await _hold_beat()
    else:
        if delay > 0.0: await get_tree().create_timer(delay).timeout
        await _settle(frames)
    await RenderingServer.frame_post_draw
    var image := get_viewport().get_texture().get_image()
    if image.save_png(out_path) != OK:
        push_error("v3 screenshot: save failed")
        get_tree().quit(1)
        return
    print("SCREENSHOT SAVED: ", out_path)
    get_tree().quit(0)

func _settle(n: int) -> void:
    for _i in range(n): await get_tree().process_frame

## Stop the rival acting so a scenario can hold a deliberate position.
func _freeze() -> void:
    main.ai_busy = true

func _engine() -> MatchV3:
    return main.engine

func _land(player: int, index: int, terrain: String) -> void:
    var e := _engine()
    e.lane(player, index)["terrain"] = terrain
    e.lane(player, index)["landscape_card"] = "land_grove" if terrain == "grove" else "land_cinder"

func _put(player: int, index: int, card_id: String, ready := true) -> Dictionary:
    var e := _engine()
    var unit := e._make_unit(e.db.card(card_id), player, index)
    unit["ready"] = ready
    e.lane(player, index)["creature"] = unit
    return unit

func _support(player: int, index: int, card_id: String) -> void:
    var e := _engine()
    e.lane(player, index)["support"] = {"card_id": card_id,
        "name": String(e.db.card(card_id).get("name", "")), "owner": player}

func _refresh() -> void:
    main.call("_clear")

func _run() -> void:
    var e := _engine()
    match scenario:
        "v3_opening":
            _refresh()
        "v3_land":
            # A Grove Landscape taking hold of a lane.
            e.players[0]["hand"].append("land_grove")
            e.players[0]["land_played"] = false
            e.play_card(0, "land_grove", 0, 1)
        "v3_three_each":
            for i in [0, 1, 2]:
                _land(0, i, "grove")
                _land(1, i, "cinder")
            _put(0, 0, "life_sproutling")
            _put(0, 1, "life_petal_deer")
            _put(0, 2, "life_bloom_bear")
            _put(1, 0, "fire_cinder_pup")
            _put(1, 1, "fire_ashcat")
            _put(1, 2, "fire_magma_turtle")
            e._begin_turn(0)
            _refresh()
        "v3_support":
            for i in range(MatchV3.LANES):
                _land(0, i, "grove")
            _put(0, 1, "life_petal_deer")
            _support(0, 1, "life_herbalist_hut")
            _put(0, 2, "life_bloom_bear")
            _support(0, 2, "life_bee_garden")
            _land(1, 1, "cinder"); _put(1, 1, "fire_ashcat")
            e._begin_turn(0)
            _refresh()
        "v3_attack":
            _land(0, 1, "grove"); _land(1, 1, "cinder")
            _land(0, 0, "grove"); _land(1, 0, "cinder")
            _put(0, 0, "life_moss_frog"); _put(1, 0, "fire_cinder_pup")
            _put(0, 1, "life_bloom_bear")            # 4/6 into a 3/3: it survives
            _put(1, 1, "fire_cinder_hound")
            e._begin_turn(0)
            _refresh()
            e.attack(0, 1)
        "v3_dragon":
            _land(0, 2, "grove"); _land(1, 2, "cinder")
            _put(0, 2, "life_garden_dragon")
            _put(1, 2, "fire_ashcat")
            e._begin_turn(0)
            _refresh()
            e.attack(0, 2)
        "v3_fusion":
            _land(0, 0, "grove"); _land(0, 1, "grove")
            _put(0, 0, "life_sproutling")
            _put(0, 1, "life_petal_deer")
            e._begin_turn(0)
            e.players[0]["pool"]["life"] = 4
            _refresh()
            e.fuse(0, "fuse_great_stag", 0, 1)
        "v3_select":
            # Selecting a Grove creature lights every legal Grove lane.
            _land(0, 0, "grove"); _land(0, 2, "grove"); _land(0, 3, "cinder")
            e._begin_turn(0)
            e.players[0]["pool"]["life"] = 4
            e.players[0]["hand"].append("life_sproutling")
            main.call("_select_card", "life_sproutling")
        "v3_late":
            for i in range(MatchV3.LANES):
                _land(0, i, "grove")
                _land(1, i, "cinder")
            _put(0, 0, "life_moss_frog")
            _put(0, 1, "life_great_stag")
            _put(0, 2, "life_bloom_bear")
            _put(0, 3, "life_garden_dragon")
            _put(1, 0, "fire_cinder_pup")
            _put(1, 1, "fire_blazewing_drake")
            _put(1, 2, "fire_magma_turtle")
            _put(1, 3, "fire_forge_ram")
            _support(0, 1, "life_herbalist_hut")
            _support(1, 2, "fire_blacksmith_nook")
            e.players[0]["heart"] = 19
            e.players[1]["heart"] = 12
            e._begin_turn(0)
            _refresh()
        _:
            push_error("unknown v3 scenario: " + scenario)

func _hold_beat() -> void:
    var b = main.board
    var wanted: Array = [hold_kind] if hold_kind != "" \
        else ["attack", "fusion", "summon", "landscape", "support"]
    var act: Dictionary = {}
    for _i in range(900):
        await get_tree().process_frame
        for a in b._acts:
            if String(a["kind"]) in wanted:
                act = a
                break
        if not act.is_empty(): break
    if act.is_empty():
        push_warning("no act to hold")
        return
    var target: float = float(act["dur"]) * clampf(beat, 0.0, 1.0)
    while float(act["t"]) < target:
        act["t"] = minf(target, float(act["t"]) + 0.0166)
    print("HELD: kind=%s t=%.2f/%.2f" % [String(act["kind"]), float(act["t"]), float(act["dur"])])
    b.set_process(false)
    b.queue_redraw()
    await _settle(3)
