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
var beat := -1.0                      # freeze the running act at this fraction
var hold_kind := ""                   # which act kind to freeze (default: any combat beat)
var main: Node

func _ready() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--out="): out_path = arg.trim_prefix("--out=")
        elif arg.begins_with("--frames="): frames = int(arg.trim_prefix("--frames="))
        elif arg.begins_with("--scenario="): scenario = arg.trim_prefix("--scenario=")
        elif arg.begins_with("--delay="): delay = float(arg.trim_prefix("--delay="))
        elif arg.begins_with("--beat="): beat = float(arg.trim_prefix("--beat="))
        elif arg.begins_with("--hold="): hold_kind = arg.trim_prefix("--hold=")
    main = load("res://scenes/v2/main_v2.tscn").instantiate()
    main.ai_busy = true               # the rival never takes its opening turn
    add_child(main)
    await _settle(28)
    await _flush_opening()
    await _run()
    if beat >= 0.0:
        await _hold_beat()
    else:
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

## Freeze the choreography at an exact fraction of the running act.
##
## Timing a capture with --delay is guesswork: the act is scheduled some way
## into the future and its duration varies by kind. This waits for the act to
## exist, walks it forward in real frame-sized steps so every _at() beat fires
## in order, then stops the stage processing so the frame holds.
func _hold_beat() -> void:
    var stage = main.stage
    # Name the act, or the harness grabs whichever beat happens to be running —
    # the opening Realm build fires before any attack and was being frozen
    # instead of the attack the scenario is about.
    var wanted: Array = [hold_kind] if hold_kind != "" \
        else ["attack", "heart_attack", "fusion", "spell"]
    var act: Dictionary = {}
    for _i in range(900):
        await get_tree().process_frame
        for a in stage._acts:
            if String(a["kind"]) in wanted:
                act = a
                break
        if not act.is_empty(): break
    if act.is_empty():
        push_warning("no act to hold; kinds present: %s" % [_act_kinds(stage)])
        return
    var target: float = float(act["dur"]) * clampf(beat, 0.0, 1.0)
    while float(act["t"]) < target:
        act["t"] = minf(target, float(act["t"]) + 0.0166)
        stage._tick_act(act)
        stage._tick_effects(0.0166)
    print("HELD: kind=%s t=%.2f/%.2f effects=%d emergent-source-uid=%s"
        % [String(act["kind"]), float(act["t"]), float(act["dur"]),
           stage._effects.size(), str(act.get("uid", "-"))])
    stage.set_process(false)
    stage.queue_redraw()
    await _settle(3)

func _act_kinds(stage) -> Array:
    var out: Array = []
    for a in stage._acts: out.append(String(a["kind"]))
    return out

func _engine() -> MatchV2:
    return main.engine

## Let the opening ceremony (initial draws, the starting land grant) play out
## fully, so a scenario capture starts from a settled board instead of
## mid-flourish. Beats are fire-and-forget timers, so this waits them out.
func _flush_opening() -> void:
    for _i in range(900):
        await get_tree().process_frame
        if main._stage_free_at <= main._now() and main.stage._acts.is_empty() \
                and main.stage._effects.is_empty():
            break

## Stop the rival acting so a scenario can hold a deliberate state.
func _freeze() -> void:
    main.ai_busy = true
    main.stage._acts = []
    main.stage._effects = []

## Hide the tutorial coach. It sits over the top of the board, which means the
## rival's Sanctuary is never visible in a review capture while it is up.
func _hide_coach() -> void:
    main.tutorial_active = false
    if main.coach_panel != null:
        main.coach_panel.visible = false

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
        "v2_three_each":
            # Three cards deployed a side, with land under them.
            _hide_coach()
            e.players[0]["aether"] = 9
            for i in [0, 1, 2]:
                e.lane(0, i)["land"] = "grove"
                e.lane(1, i)["land"] = "cinder"
            _place(0, 0, "life_sproutling")
            _place(0, 1, "life_great_stag")
            _place(0, 2, "life_bloom_bear")
            _place(1, 0, "fire_ashcat")
            _place(1, 1, "fire_blazewing_drake")
            _place(1, 2, "fire_magma_turtle")
            e.players[0]["max_aether"] = 4; e.players[0]["aether"] = 3
            e.players[1]["heart"] = 16
            main.call("_clear")
        "v2_land_grow":
            # A Grove Realm card transforming its part of the battlefield.
            _hide_coach()
            e.players[0]["aether"] = 9
            e.lane(0, 0)["land"] = "grove"
            _place(0, 0, "life_sproutling")
            main.call("_clear")
            e.players[0]["played_card"] = false
            e.play_realm(0, 2)
        "v2_select_grove":
            # Selecting a Grove creature lights the land it can be played on.
            _hide_coach()
            e.players[0]["aether"] = 9
            for i in [0, 2]:
                e.players[0]["played_card"] = false
                e.play_realm(0, i)
            e.players[0]["played_card"] = false
            e.players[0]["hand"].append("life_sproutling")
            main.call("_select_card", "life_sproutling")
        "v2_sanctuaries":
            # Both homes, with the coach out of the way.
            _hide_coach()
            e.players[0]["aether"] = 9
            for i in range(MatchV2.LANES):
                e.lane(0, i)["land"] = "grove"
                e.lane(1, i)["land"] = "cinder"
            main.call("_clear")
        "v2_late_clear":
            _hide_coach()
            e.players[0]["aether"] = 9
            for i in range(MatchV2.LANES):
                e.lane(0, i)["land"] = "grove"
                e.lane(1, i)["land"] = "cinder"
            _place(0, 0, "life_sproutling")
            _place(0, 1, "life_great_stag")
            _place(0, 2, "life_bloom_bear")
            _place(0, 3, "life_garden_dragon")
            _place(1, 0, "fire_ashcat")
            _place(1, 1, "fire_blazewing_drake")
            _place(1, 2, "fire_magma_turtle")
            _place(1, 3, "fire_cinder_hound")
            e.lane(0, 1)["place"] = {"card_id": "life_herbalist_hut", "name": "Herbalist Hut",
                "owner": 0, "presence": 1}
            e.lane(1, 2)["place"] = {"card_id": "fire_blacksmith_nook", "name": "Blacksmith Nook",
                "owner": 1, "presence": 1}
            e.players[0]["max_aether"] = 5; e.players[0]["aether"] = 4
            e.players[1]["max_aether"] = 5; e.players[1]["aether"] = 2
            e.players[0]["heart"] = 14; e.players[1]["heart"] = 9
            main.call("_clear")
        "v2_card_selected":
            e.players[0]["aether"] = 9
            e.play_realm(0, 2)
            e.players[0]["played_card"] = false
            e.players[0]["hand"].append("life_petal_deer")
            main.call("_select_card", "life_petal_deer")
            main.stage.hover_side = 0
            main.stage.hover_lane = 1
        "v2_one_grove":
            pass                     # only the signature Grove exists yet
        "v2_three_lands":
            e.players[0]["aether"] = 9
            for i in [0, 2]:
                e.players[0]["played_card"] = false
                e.play_realm(0, i)
        "v2_facing":
            # Creatures from opposing realms staring at each other.
            _place(0, 1, "life_great_stag")
            _place(0, 2, "life_bloom_bear")
            _place(1, 1, "fire_blazewing_drake")
            _place(1, 2, "fire_forge_ram")
            main.call("_clear")
        "v2_place_built":
            _place(0, 1, "life_petal_deer")
            e.players[0]["hand"].append("life_herbalist_hut")
            e.players[0]["aether"] = 9
            e.play_card(0, "life_herbalist_hut", 0, 1)
        "v2_late":
            # Both realms fully developed, the way a match should end up looking.
            e.players[0]["aether"] = 9
            for i in range(MatchV2.LANES):
                e.lane(0, i)["land"] = "grove"
                e.lane(1, i)["land"] = "cinder"
            _place(0, 0, "life_sproutling")
            _place(0, 1, "life_great_stag")
            _place(0, 2, "life_bloom_bear")
            _place(0, 3, "life_garden_dragon")
            _place(1, 0, "fire_ashcat")
            _place(1, 1, "fire_blazewing_drake")
            _place(1, 2, "fire_magma_turtle")
            _place(1, 3, "fire_cinder_hound")
            e.lane(0, 1)["place"] = {"card_id": "life_herbalist_hut", "name": "Herbalist Hut",
                "owner": 0, "presence": 1}
            e.lane(1, 2)["place"] = {"card_id": "fire_blacksmith_nook", "name": "Blacksmith Nook",
                "owner": 1, "presence": 1}
            e.players[0]["max_aether"] = 5; e.players[0]["aether"] = 4
            e.players[1]["max_aether"] = 5; e.players[1]["aether"] = 2
            e.players[0]["heart"] = 14; e.players[1]["heart"] = 9
            e.players[0]["realm_stack"] = 0; e.players[1]["realm_stack"] = 0
            main.call("_clear")
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
        "v2_spell":
            # A Fire spell landing on a Life creature: cause, travel, impact.
            _place(0, 1, "life_bloom_bear")
            _place(0, 2, "life_petal_deer")
            _place(1, 1, "fire_cinder_hound")
            e.players[1]["aether"] = 9
            e.players[1]["hand"].append("fire_scorch_mark")
            main.call("_clear")
            e.play_card(1, "fire_scorch_mark", 0, 1)
            # Same payload shape main_v2 sends for a real cast.
            main.stage.play("spell", {
                "from": main.stage.sanctuary_rect(1).get_center(),
                "to": main.stage.creature_anchor(0, 1),
                "element": "fire",
                "colour": main.stage.element_colour("fire")}, 1.1)
        "v2_grove_pair":
            # Neighbouring Grove lands reading as one region.
            e.players[0]["aether"] = 9
            for i in [1, 2]:
                e.players[0]["played_card"] = false
                e.play_realm(0, i)
            _place(0, 1, "life_great_stag")
            _place(0, 2, "life_bloom_bear")
            main.call("_clear")
        "v2_cinder_pair":
            e.players[1]["aether"] = 9
            for i in [1, 2]:
                e.players[1]["played_card"] = false
                e.play_realm(1, i)
            _place(1, 1, "fire_blazewing_drake")
            _place(1, 2, "fire_magma_turtle")
            main.call("_clear")
        "v2_place_building":
            # Caught part-way through construction.
            _place(0, 1, "life_petal_deer")
            e.players[0]["hand"].append("life_herbalist_hut")
            e.players[0]["aether"] = 9
            e.play_card(0, "life_herbalist_hut", 0, 1)
            main.stage.play("place_build", {"side": 0, "lane": 1, "element": "life",
                "colour": main.stage.element_colour("life")}, 2.4)
        "v2_attack_targeting":
            _place(0, 1, "life_great_stag")
            _place(0, 3, "life_bloom_bear")
            _place(1, 1, "fire_ashcat")
            main.call("_clear")
            main.call("_begin_attack", 3)
        "v2_victory":
            # The winner's portrait takes the frame.
            _hide_coach()
            e.players[1]["heart"] = 0
            main.call("_on_match_finished", 0)
        "v2_defeat":
            _hide_coach()
            e.players[0]["heart"] = 0
            main.call("_on_match_finished", 1)
        _:
            push_error("unknown v2 scenario: " + scenario)
