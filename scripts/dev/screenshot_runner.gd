extends Node
## Dev tool: boot the match screen, drive it into a named state, capture a PNG.
##
##   Godot --path . --scene res://scenes/dev/screenshot.tscn -- \
##         --out=/abs/path.png --scenario=card_selected [--frames=90]
##
## Runs windowed — viewport capture needs a real renderer, so not --headless.
## Scenarios drive the real UI entry points, so this playtests the click paths
## as well as the look.

var out_path := "/tmp/pocket_arcana_shot.png"
var frames := 90
var scenario := "opening"
var main: Node

func _ready() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--out="): out_path = arg.trim_prefix("--out=")
        elif arg.begins_with("--frames="): frames = int(arg.trim_prefix("--frames="))
        elif arg.begins_with("--scenario="): scenario = arg.trim_prefix("--scenario=")
    var packed: PackedScene = load("res://scenes/main.tscn")
    main = packed.instantiate()
    add_child(main)
    await _settle(30)
    await _run_scenario()
    await _settle(frames)
    await RenderingServer.frame_post_draw
    var image := get_viewport().get_texture().get_image()
    if image.save_png(out_path) != OK:
        push_error("screenshot_runner: save_png failed for " + out_path)
        get_tree().quit(1)
        return
    print("SCREENSHOT SAVED: ", out_path)
    get_tree().quit(0)

func _settle(count: int) -> void:
    for _i in range(count):
        await get_tree().process_frame

func _engine() -> MatchEngine:
    return main.engine

## Stop the rival acting so a scenario can hold a deliberate board state.
func _freeze_rival() -> void:
    main.ai_busy = true

func _run_scenario() -> void:
    var engine := _engine()
    match scenario:
        "opening":
            pass
        "card_selected":
            _freeze_rival()
            # Pick a card that is genuinely in hand and affordable.
            for card_id in engine.players[0]["hand"]:
                if engine.card_block_reason(0, String(card_id)) == "":
                    main.call("_select_card", String(card_id))
                    break
        "shape_selected":
            _freeze_rival()
            main.call("_choose_shape", "life")
        "midgame":
            # Let both sides actually play, then stop on the human's turn.
            for _i in range(26):
                engine.perform(engine.current_player, engine.ai.choose_action(engine, engine.current_player))
                if engine.match_over: break
            _freeze_rival()
        "unit_selected":
            _freeze_rival()
            var pos := engine.sanctuary_pos(0)
            engine.board.get_tile(pos)["creature"] = engine.make_unit_from_card(engine.db.get_card("life_great_stag"), 0)
            main.call("_on_tile_clicked", pos)
        "heart_strike":
            _freeze_rival()
            var sanc := engine.sanctuary_pos(1)
            var beside := Vector2i(sanc.x, sanc.y + 1)
            engine.board.shape(0, beside, "grove")
            engine.board.get_tile(beside)["creature"] = engine.make_unit_from_card(engine.db.get_card("life_garden_dragon"), 0)
            main.call("_on_tile_clicked", beside)
        "ashbloom":
            # The marquee Life vs Fire discovery.
            _freeze_rival()
            var pos := Vector2i(3, 3)
            engine.board.shape(0, pos, "grove")
            engine.board.add_state(pos, "burning")
            main.call("_select_card", "life_grow")
            engine.players[0]["hand"].append("life_grow")
            engine.play_card(0, "life_grow", pos)
        "chapter_overlay":
            for _i in range(18):
                engine.perform(engine.current_player, engine.ai.choose_action(engine, engine.current_player))
                if engine.match_over: break
            _freeze_rival()
            engine.pass_chapter(engine.current_player)
            engine.pass_chapter(engine.current_player)
        "art_review":
            # The Phase-A capture from docs/ART_PRODUCTION_PIPELINE.md: a Life
            # creature on Grove, a Fire creature on Cinder, and a dragon a side.
            _freeze_rival()
            var place := func(pos: Vector2i, terrain: String, owner: int, card_id: String) -> void:
                engine.board.shape(owner, pos, terrain)
                if card_id != "":
                    engine.board.get_tile(pos)["creature"] = engine.make_unit_from_card(
                        engine.db.get_card(card_id), owner)
            place.call(Vector2i(2, 3), "grove", 0, "life_sproutling")
            place.call(Vector2i(3, 3), "grove", 0, "life_garden_dragon")
            place.call(Vector2i(4, 3), "grove", 0, "life_petal_deer")
            place.call(Vector2i(2, 1), "cinder", 1, "fire_cinder_pup")
            place.call(Vector2i(3, 1), "cinder", 1, "fire_blazewing_drake")
            place.call(Vector2i(4, 1), "cinder", 1, "fire_ashcat")
            place.call(Vector2i(1, 2), "grove", 0, "")
            place.call(Vector2i(5, 2), "cinder", 1, "")
            # A landmark sharing a tile with a creature, and an Ashbloom reaction.
            engine.board.get_tile(Vector2i(2, 3))["landmark"] = {
                "card_id": "life_herbalist_hut", "name": "Herbalist Hut", "owner": 0, "presence": 1}
            engine.board.get_tile(Vector2i(4, 1))["landmark"] = {
                "card_id": "fire_blacksmith_nook", "name": "Blacksmith Nook", "owner": 1, "presence": 1}
            engine.board.shape(0, Vector2i(3, 2), "grove")
            engine.board.add_state(Vector2i(3, 2), "overgrown")
            engine.board.add_state(Vector2i(3, 2), "burning")
            engine.combo.resolve_tile(engine.board, Vector2i(3, 2))
            main.call("_clear_selection")
        "match_end":
            _freeze_rival()
            var guard := 0
            while not engine.match_over and guard < 900:
                engine.perform(engine.current_player, engine.ai.choose_action(engine, engine.current_player))
                guard += 1
        "hand_hover":
            # Prove the hand behaves like a card game: the pointed-at card rises
            # out of the row and enlarges enough to read.
            _freeze_rival()
            await _settle(4)
            if main.hand_view.cards.size() > 3:
                main.hand_view.hovered = 3
                main.hand_view.call("_layout")
                main.call("_on_card_hovered", main.hand_view.cards[3].card_id)
        "help":
            _freeze_rival()
            main.help_panel.get_meta("dimmer").visible = true
        _:
            push_error("unknown scenario: " + scenario)
