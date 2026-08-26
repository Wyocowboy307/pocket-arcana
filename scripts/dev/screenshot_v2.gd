extends Node
## Review harness for the V2 prototype.
##
##   Godot --path . --scene res://scenes/dev/screenshot_v2.tscn -- \
##       --out=/abs/shot.png --scenario=v2_attack --delay=0.5
##
## Scenarios drive the real V2 screen, so a capture also exercises its click paths.

var out_path := "/tmp/v2.png"
var frames := 60
var scenario := "v2_opening"
var delay := 0.0
var main: Node

func _ready() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--out="): out_path = arg.trim_prefix("--out=")
        elif arg.begins_with("--frames="): frames = int(arg.trim_prefix("--frames="))
        elif arg.begins_with("--scenario="): scenario = arg.trim_prefix("--scenario=")
        elif arg.begins_with("--delay="): delay = float(arg.trim_prefix("--delay="))
    main = load("res://scenes/v2/main_v2.tscn").instantiate()
    add_child(main)
    await _settle(28)
    await _run()
    if delay > 0.0: await get_tree().create_timer(delay).timeout
    await _settle(frames)
    await RenderingServer.frame_post_draw
    var image := get_viewport().get_texture().get_image()
    if image.save_png(out_path) != OK:
        push_error("v2 screenshot: save failed")
        get_tree().quit(1)
        return
    print("SCREENSHOT SAVED: ", out_path)
    get_tree().quit(0)

func _settle(n: int) -> void:
    for _i in range(n): await get_tree().process_frame

func _engine() -> MatchV2:
    return main.engine

## Stop the rival acting so a scenario can hold a deliberate state.
func _freeze() -> void:
    main.ai_busy = true

func _place(player: int, index: int, card_id: String, ready := true) -> Dictionary:
    var e := _engine()
    if String(e.lane(player, index)["land"]) == "":
        e.lane(player, index)["land"] = String(e.players[player]["terrain"])
    var unit: Dictionary = e._make_unit(e.db.get_card(card_id), player, index)
    unit["ready"] = ready
    e.lane(player, index)["creature"] = unit
    return unit

func _run() -> void:
    var e := _engine()
    _freeze()
    match scenario:
        "v2_opening":
            pass
        "v2_card_selected":
            e.players[0]["aether"] = 9
            e.play_realm(0, 2)
            e.players[0]["played_card"] = false
            e.players[0]["hand"].append("life_petal_deer")
            main.call("_select_card", "life_petal_deer")
            main.stage.hover_side = 0
            main.stage.hover_lane = 1
        "v2_board":
            # A believable mid-match position on both sides.
            _place(0, 0, "life_sproutling")
            _place(0, 1, "life_great_stag")
            _place(0, 2, "life_bloom_bear")
            _place(1, 0, "fire_ashcat")
            _place(1, 1, "fire_blazewing_drake")
            e.lane(0, 1)["place"] = {"card_id": "life_herbalist_hut", "name": "Herbalist Hut",
                "owner": 0, "presence": 1}
            e.lane(1, 0)["place"] = {"card_id": "fire_blacksmith_nook", "name": "Blacksmith Nook",
                "owner": 1, "presence": 1}
            e.players[0]["max_aether"] = 4; e.players[0]["aether"] = 3
            e.players[1]["heart"] = 12
            main.call("_clear")
        "v2_land_build":
            e.players[0]["aether"] = 9
            e.play_realm(0, 3)
        "v2_summon":
            e.players[0]["hand"].append("life_great_stag")
            e.players[0]["aether"] = 9
            e.play_card(0, "life_great_stag", 0, 1)
        "v2_attack":
            _place(0, 1, "life_great_stag")
            _place(1, 1, "fire_ashcat")
            main.call("_clear")
            e.attack(0, 1)
        "v2_dragon":
            _place(0, 2, "life_garden_dragon")
            _place(1, 2, "fire_magma_turtle")
            main.call("_clear")
            e.attack(0, 2)
        "v2_heart":
            _place(0, 3, "life_great_stag")
            main.call("_clear")
            e.attack(0, 3)
        "v2_fusion":
            _place(0, 0, "life_sproutling")
            _place(0, 1, "life_petal_deer")
            e.players[0]["aether"] = 9
            main.call("_clear")
            e.fuse(0, "fuse_great_stag", 0, 1)
        "v2_attack_targeting":
            _place(0, 1, "life_great_stag")
            _place(0, 3, "life_bloom_bear")
            _place(1, 1, "fire_ashcat")
            main.call("_clear")
            main.call("_begin_attack", 3)
        _:
            push_error("unknown v2 scenario: " + scenario)
