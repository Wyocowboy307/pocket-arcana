extends Node
## The Living Board Lab: every board state the visual system must survive,
## in one scene. The visual regression bench for current and future elements.
##
##   Godot --path . --scene res://scenes/dev/board_lab.tscn
##     LEFT/RIGHT or 1-9,0,-,=   jump between states
##     D  toggle environment dressing      M  toggle micro-animation
##     C  capture the current state to /tmp/board_lab/
##
##   Godot --path . --scene res://scenes/dev/board_lab.tscn --resolution 1280x720 \
##       -- --capture-all=/abs/dir [--no-dressing] [--no-micro]
##
## Batch mode walks every state in one boot and saves <idx>_<name>.png.

var main: Node
var label: Label
var state_index := 0
var capture_dir := ""
var states: Array = []

func _ready() -> void:
    main = load("res://scenes/v2/main_v2.tscn").instantiate()
    main.ai_busy = true                  # the rival never acts in the lab
    add_child(main)

    label = Label.new()
    label.position = Vector2(10, 6)
    label.add_theme_font_size_override("font_size", 13)
    label.add_theme_color_override("font_color", Color("f2c86b"))
    label.add_theme_color_override("font_outline_color", Color(0.06, 0.05, 0.08))
    label.add_theme_constant_override("outline_size", 6)
    label.z_index = 90
    add_child(label)

    states = _build_states()
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--capture-all="): capture_dir = arg.trim_prefix("--capture-all=")
        elif arg == "--no-dressing": main.stage.realm.dressing_enabled = false
        elif arg == "--no-micro": main.stage.realm.micro_enabled = false

    await _settle(24)
    await _flush_opening()
    if capture_dir != "":
        await _capture_all()
        return
    _apply(0)

func _settle(n: int) -> void:
    for _i in range(n): await get_tree().process_frame

## Wait out the opening ceremony's fire-and-forget beats.
func _flush_opening() -> void:
    for _i in range(900):
        await get_tree().process_frame
        if main._stage_free_at <= main._now() and main.stage._acts.is_empty() \
                and main.stage._effects.is_empty():
            break

func _e() -> MatchV2:
    return main.engine

## Reset to a fresh match, then let a state builder sculpt it. setup() emits
## the opening ceremony through fire-and-forget beat timers, so the lab waits
## them out and sweeps their leftovers before the state counts as applied.
func _apply(index: int) -> void:
    state_index = posmod(index, states.size())
    var st: Dictionary = states[state_index]
    main.engine.setup(main.db, "starter_life", "starter_fire", 7)
    main.call("_clear")
    main.tutorial_active = false
    if main.coach_panel != null: main.coach_panel.visible = false
    await _flush_opening()
    main.stage._acts = []
    main.stage._effects = []
    main.stage._particles = []
    main.stage._decals = []
    main.stage.realm.reset()
    (st["build"] as Callable).call()
    main.call("_refresh")
    _refresh_label()

func _refresh_label() -> void:
    var realm = main.stage.realm
    label.text = "LAB %d/%d  %s   [D]ressing:%s  [M]icro:%s  [C]apture" % [
        state_index + 1, states.size(), String(states[state_index]["name"]),
        "on" if realm.dressing_enabled else "OFF",
        "on" if realm.micro_enabled else "OFF"]

func _unhandled_input(event: InputEvent) -> void:
    if event is not InputEventKey or not event.pressed: return
    match event.keycode:
        KEY_RIGHT: _apply(state_index + 1)
        KEY_LEFT: _apply(state_index - 1)
        KEY_D:
            main.stage.realm.dressing_enabled = not main.stage.realm.dressing_enabled
            _refresh_label()
        KEY_M:
            main.stage.realm.micro_enabled = not main.stage.realm.micro_enabled
            _refresh_label()
        KEY_C:
            _capture_one("/tmp/board_lab", state_index)
        _:
            var digits := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8,
                KEY_9, KEY_0, KEY_MINUS, KEY_EQUAL]
            var at := digits.find(event.keycode)
            if at >= 0 and at < states.size(): _apply(at)

func _capture_one(dir: String, index: int) -> void:
    DirAccess.make_dir_recursive_absolute(dir)
    await _settle(4)
    await RenderingServer.frame_post_draw
    var path := "%s/%02d_%s.png" % [dir, index + 1, String(states[index]["name"])]
    get_viewport().get_texture().get_image().save_png(path)
    print("LAB CAPTURE: ", path)

func _capture_all() -> void:
    label.visible = false
    for i in range(states.size()):
        await _apply(i)
        await _settle(30)
        await _capture_one(capture_dir, i)
    print("LAB DONE: %d states" % states.size())
    get_tree().quit(0)

# --- state builders ----------------------------------------------------------

func _land(side: int, lane: int, terrain := "") -> void:
    var e := _e()
    e.lane(side, lane)["land"] = terrain if terrain != "" \
        else String(e.players[side]["terrain"])

func _unit(side: int, lane: int, card_id: String, ready := true) -> void:
    var e := _e()
    _land(side, lane)
    var u: Dictionary = e._make_unit(e.db.get_card(card_id), side, lane)
    u["ready"] = ready
    e.lane(side, lane)["creature"] = u

func _place_at(side: int, lane: int, card_id: String, pname: String) -> void:
    _land(side, lane)
    _e().lane(side, lane)["place"] = {"card_id": card_id, "name": pname,
        "owner": side, "presence": 1}

## Lands that have stood for `age` turns grow more; the lab fakes the clock.
func _aged(side: int, lane: int, age: int) -> void:
    main.stage.realm.built_turn["%d,%d" % [side, lane]] = maxi(1, _e().turn - age)

func _build_states() -> Array:
    return [
        {"name": "opening", "build": func() -> void:
            pass},
        {"name": "one_life_land", "build": func() -> void:
            _land(0, 1)},
        {"name": "four_life_lands", "build": func() -> void:
            for i in range(4): _land(0, i)},
        {"name": "mixed_life_fire", "build": func() -> void:
            _land(0, 0); _land(0, 1); _land(1, 2); _land(1, 3)},
        {"name": "creatures", "build": func() -> void:
            _unit(0, 0, "life_sproutling"); _unit(0, 1, "life_great_stag")
            _unit(0, 2, "life_bloom_bear", false)
            _unit(1, 1, "fire_blazewing_drake"); _unit(1, 2, "fire_ashcat", false)},
        {"name": "places", "build": func() -> void:
            _unit(0, 1, "life_petal_deer"); _unit(1, 2, "fire_magma_turtle")
            _place_at(0, 1, "life_herbalist_hut", "Herbalist Hut")
            _place_at(1, 2, "fire_blacksmith_nook", "Blacksmith Nook")},
        {"name": "damaged_terrain", "build": func() -> void:
            for i in range(4): _land(0, i); _land(1, i)
            _unit(0, 1, "life_rootback_boar"); _unit(1, 2, "fire_cinder_hound")
            var stage = main.stage
            stage.scar(stage.clash_centre(0) + Vector2(-20, 8), "scorch")
            stage.scar(stage.creature_stand(0, 2) + Vector2(10, -30), "scorch")
            stage.scar(stage.creature_stand(1, 0) + Vector2(-16, -20), "growth")
            stage.scar(stage.clash_centre(2) + Vector2(30, -6), "growth")},
        {"name": "damaged_hearts", "build": func() -> void:
            _e().players[0]["heart"] = 6
            _e().players[1]["heart"] = 4
            _unit(0, 1, "life_great_stag"); _unit(1, 2, "fire_forge_ram")},
        {"name": "fusion_available", "build": func() -> void:
            _unit(0, 1, "life_sproutling"); _unit(0, 2, "life_petal_deer")
            _e().players[0]["aether"] = 9
            main.call("_refresh")},
        {"name": "fusion_done", "build": func() -> void:
            _unit(0, 1, "life_great_stag")
            main.stage.realm.fusion_sites.append({"side": 0, "lane": 1})},
        {"name": "max_complexity", "build": func() -> void:
            var e := _e()
            e.turn = 14
            for i in range(4):
                _land(0, i); _land(1, i)
                _aged(0, i, i + 1); _aged(1, i, 4 - i)
            _unit(0, 0, "life_sproutling"); _unit(0, 1, "life_great_stag")
            _unit(0, 2, "life_bloom_bear", false); _unit(0, 3, "life_garden_dragon")
            _unit(1, 0, "fire_ashcat", false); _unit(1, 1, "fire_blazewing_drake")
            _unit(1, 2, "fire_magma_turtle"); _unit(1, 3, "fire_rax_the_laughing_inferno")
            _place_at(0, 1, "life_herbalist_hut", "Herbalist Hut")
            _place_at(1, 2, "fire_blacksmith_nook", "Blacksmith Nook")
            e.players[0]["heart"] = 8; e.players[1]["heart"] = 5
            e.players[0]["max_aether"] = 7; e.players[0]["aether"] = 3
            var stage = main.stage
            stage.realm.fusion_sites.append({"side": 0, "lane": 1})
            stage.scar(stage.clash_centre(1) + Vector2(-14, 4), "scorch")
            stage.scar(stage.clash_centre(3) + Vector2(12, -8), "growth")
            stage.scar(stage.creature_stand(1, 3) + Vector2(-30, -26), "scorch")},
    ]
