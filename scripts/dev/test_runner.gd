extends Node
## Headless regression suite for the Pocket Arcana simulation.
##
##   Godot --headless --path . --scene res://scenes/dev/tests.tscn
##
## Exits 0 when every check passes, 1 otherwise, so it works in a commit gate.

var _db := ContentDatabase.new()
var _failures: Array[String] = []
var _checks := 0
var _current := ""

func _ready() -> void:
    if not _db.load_all():
        push_error("TEST: content failed to load")
        get_tree().quit(1)
        return
    for method in get_method_list():
        var name: String = method["name"]
        if name.begins_with("test_"):
            _current = name
            call(name)
    print("")
    if _failures.is_empty():
        print("TESTS PASS — %d checks." % _checks)
        get_tree().quit(0)
    else:
        print("TESTS FAILED — %d of %d checks failed:" % [_failures.size(), _checks])
        for f in _failures:
            print("  ✗ ", f)
        get_tree().quit(1)

# --- tiny assertion helpers -------------------------------------------------

func _ok(condition: bool, what: String) -> bool:
    _checks += 1
    if not condition:
        _failures.append("%s: %s" % [_current, what])
    return condition

func _eq(actual, expected, what: String) -> bool:
    return _ok(actual == expected, "%s (got %s, expected %s)" % [what, str(actual), str(expected)])

func _new_match(deck0 := "starter_life", deck1 := "starter_fire", match_seed := 424242) -> MatchEngine:
    var engine := MatchEngine.new()
    add_child(engine)
    engine.setup(_db, deck0, deck1, match_seed)
    return engine

## Give a player a specific card in hand and enough Aether to cast it.
func _force_hand(engine: MatchEngine, player: int, card_id: String) -> void:
    engine.players[player]["hand"].append(card_id)
    engine.players[player]["aether"] = 99

func _play_out(engine: MatchEngine, max_steps := 800) -> int:
    var steps := 0
    while not engine.match_over and steps < max_steps:
        var player: int = engine.current_player
        engine.perform(player, engine.ai.choose_action(engine, player))
        steps += 1
    return steps

# --- tests ------------------------------------------------------------------

func test_content_loads() -> void:
    _eq(_db.cards.size(), 240, "core set card count")
    _eq(_db.commanders.size(), 24, "commander count")
    _eq(_db.recipes.size(), 28, "recipe count")
    _ok(_db.get_deck("starter_life").has("cards"), "life starter deck exists")
    _ok(_db.get_deck("starter_fire").has("cards"), "fire starter deck exists")

func test_match_setup() -> void:
    var e := _new_match()
    _eq(e.players[0]["hand"].size(), 8, "player 1 opening hand")
    _eq(e.players[1]["hand"].size(), 8, "player 2 opening hand")
    # Mossy Mae opens every Chapter by healing 2, so Life starts above the base 25.
    _eq(int(e.players[0]["heart"]), MatchEngine.HEART_START + 2, "Life starts with its Commander's heal")
    _eq(int(e.players[1]["heart"]), MatchEngine.HEART_START, "Fire is untouched until it acts")
    _eq(e.chapter, 1, "starts in chapter 1")
    _ok(not e.match_over, "match is live at setup")
    # Mono starters must be castable turn one without shaping first.
    _ok(e.has_attunement(0, ["life"]), "life sanctuary grants life attunement")
    _ok(e.has_attunement(1, ["fire"]), "fire sanctuary grants fire attunement")
    _ok(not e.has_attunement(0, ["fire"]), "life player lacks fire attunement")
    e.free()

func test_ai_match_completes() -> void:
    var e := _new_match()
    var steps := _play_out(e)
    _ok(e.match_over, "AI vs AI match finishes (took %d steps)" % steps)
    _ok(e.winner in [0, 1], "match has a winner")
    e.free()

func test_determinism() -> void:
    var a := _new_match("starter_life", "starter_fire", 777)
    var b := _new_match("starter_life", "starter_fire", 777)
    _play_out(a)
    _play_out(b)
    _eq(a.winner, b.winner, "same seed gives same winner")
    _eq(a.event_log, b.event_log, "same seed gives identical event log")
    var c := _new_match("starter_life", "starter_fire", 778)
    _play_out(c)
    _ok(true, "alternate seed also completes: %s" % str(c.match_over))
    a.free(); b.free(); c.free()

func test_shape_must_change_the_tile() -> void:
    var e := _new_match()
    # The Life sanctuary is already a grove; re-shaping it to grove is a wasted turn.
    _ok(not e.can_shape_with_element(0, "life", e.sanctuary_pos(0)), "cannot re-shape an identical tile")
    _ok(e.can_shape_with_element(0, "fire", e.sanctuary_pos(0)), "can re-shape to a different terrain")
    var r: Dictionary = e.shape(0, "life", e.sanctuary_pos(0))
    _ok(not bool(r.get("ok", false)), "no-op shape is rejected")
    e.free()

func test_aether_is_spent_and_refills() -> void:
    var e := _new_match()
    var before: int = int(e.players[0]["aether"])
    _force_hand(e, 0, "life_sproutling")
    e.players[0]["aether"] = before
    var r: Dictionary = e.play_card(0, "life_sproutling", e.sanctuary_pos(0))
    _ok(bool(r.get("ok", false)), "sproutling is playable on the sanctuary: %s" % str(r.get("reason", "")))
    _eq(int(e.players[0]["aether"]), before - 1, "aether was spent")
    e.free()

func test_cannot_act_out_of_turn() -> void:
    var e := _new_match()
    var r: Dictionary = e.pass_chapter(1)
    _ok(not bool(r.get("ok", false)), "player 2 cannot act on player 1's turn")
    _ok(String(r.get("reason", "")) != "", "refusal carries a plain-English reason")
    e.free()

func test_commander_chapter_aether_is_not_wiped() -> void:
    # Pip Snowshoe and the Water starter grant +1 Aether at the start of each
    # Chapter. That bonus must survive until the player actually acts.
    var e := _new_match("starter_frost", "starter_water")
    var base: int = min(10, 3 + e.chapter)
    _eq(int(e.players[0]["aether"]), base + 1, "starting player keeps chapter-start Aether")
    e.pass_chapter(0)
    _eq(e.current_player, 1, "turn passes to player 2")
    _eq(int(e.players[1]["aether"]), base + 1, "second player also keeps chapter-start Aether")
    e.free()

func test_heart_attack_requires_adjacency() -> void:
    var e := _new_match()
    var enemy_sanc: Vector2i = e.sanctuary_pos(1)
    var adjacent := Vector2i(enemy_sanc.x, enemy_sanc.y + 1)
    # Drop a unit next to the rival Sanctuary by hand.
    var card: Dictionary = _db.get_card("life_great_stag")
    e.board.get_tile(adjacent)["creature"] = e.make_unit_from_card(card, 0)
    var far := e.sanctuary_pos(0)
    e.board.get_tile(far)["creature"] = e.make_unit_from_card(card, 0)
    _ok(e.can_attack_heart(0, adjacent), "adjacent creature may strike the Heart")
    _ok(not e.can_attack_heart(0, far), "distant creature may not strike the Heart")
    var before: int = int(e.players[1]["heart"])
    var r: Dictionary = e.attack_heart(0, adjacent)
    _ok(bool(r.get("ok", false)), "heart attack resolves: %s" % str(r.get("reason", "")))
    _eq(int(e.players[1]["heart"]), before - int(card.get("power", 0)), "heart took the creature's Power")
    e.free()

func test_creature_cannot_enter_enemy_sanctuary() -> void:
    var e := _new_match()
    var enemy_sanc: Vector2i = e.sanctuary_pos(1)
    var adjacent := Vector2i(enemy_sanc.x, enemy_sanc.y + 1)
    e.board.get_tile(adjacent)["creature"] = e.make_unit_from_card(_db.get_card("life_great_stag"), 0)
    var r: Dictionary = e.move_or_attack(0, adjacent, enemy_sanc)
    _ok(not bool(r.get("ok", false)), "the rival Sanctuary is not a walkable tile")
    _ok(e.board.get_tile(enemy_sanc).get("creature") == null, "no creature standing in the Sanctuary")
    e.free()

func test_ashbloom_recipe_fires() -> void:
    # The marquee Life vs Fire interaction: Overgrown + Burning -> Ashbloom.
    var e := _new_match()
    var pos := Vector2i(3, 3)
    e.board.add_state(pos, "overgrown")
    e.board.add_state(pos, "burning")
    var events: Array = e.combo.resolve_tile(e.board, pos)
    _eq(events.size(), 1, "one recipe fired")
    if events.size() == 1:
        _eq(String(events[0].get("name", "")), "Ashbloom", "recipe is Ashbloom")
        _eq(String(e.board.get_tile(pos)["terrain"]), "ashbloom", "tile became ashbloom terrain")
    e.free()

func test_recipe_terrain_grants_both_attunements() -> void:
    var e := _new_match()
    var pos := Vector2i(3, 3)
    e.board.shape(0, pos, "grove")
    e.board.add_state(pos, "overgrown")
    e.board.add_state(pos, "burning")
    e.combo.resolve_tile(e.board, pos)
    _ok(e.has_attunement(0, ["life", "fire"]), "ashbloom tile grants both Life and Fire attunement")
    e.free()

func test_heart_break_wins_immediately() -> void:
    var e := _new_match()
    e.players[1]["heart"] = 1
    var enemy_sanc: Vector2i = e.sanctuary_pos(1)
    var adjacent := Vector2i(enemy_sanc.x, enemy_sanc.y + 1)
    e.board.get_tile(adjacent)["creature"] = e.make_unit_from_card(_db.get_card("life_great_stag"), 0)
    e.attack_heart(0, adjacent)
    _ok(e.match_over, "breaking the Heart ends the match")
    _eq(e.winner, 0, "the attacker wins")
    e.free()

func test_wonder_ten_wins() -> void:
    var e := _new_match()
    e.players[0]["wonder"] = 9
    _force_hand(e, 0, "life_rebloom")  # heal 2, gain 1 Wonder
    e.play_card(0, "life_rebloom", e.sanctuary_pos(0))
    _ok(e.match_over, "10 Wonder ends the match")
    _eq(e.winner, 0, "the Wonder player wins")
    e.free()

func test_heal_caps_at_thirty() -> void:
    # Water's starter Commander has no Chapter opener, so nothing else moves the Heart.
    var e := _new_match("starter_life", "starter_water")
    e.players[0]["heart"] = 29
    _force_hand(e, 0, "life_warm_sun")  # heal 3
    e.play_card(0, "life_warm_sun", e.sanctuary_pos(0))
    _eq(int(e.players[0]["heart"]), 30, "healing is capped at 30")
    e.free()

func test_hand_carries_across_chapters() -> void:
    var e := _new_match()
    var kept: int = e.players[0]["hand"].size()
    e.pass_chapter(0)
    e.pass_chapter(1)
    _eq(e.chapter, 2, "chapter advanced")
    # Chapter 2 draws 3; nothing should have been discarded.
    _eq(e.players[0]["hand"].size(), kept + 3, "unspent cards carry into Chapter 2 plus 3 draws")
    e.free()

func test_creatures_clear_between_chapters() -> void:
    var e := _new_match()
    var pos: Vector2i = e.sanctuary_pos(0)
    e.board.get_tile(pos)["creature"] = e.make_unit_from_card(_db.get_card("life_great_stag"), 0)
    e.board.shape(0, Vector2i(3, 3), "grove")
    e.pass_chapter(0)
    e.pass_chapter(1)
    _ok(e.board.get_tile(pos).get("creature") == null, "creatures clear between Chapters")
    _eq(String(e.board.get_tile(Vector2i(3, 3))["terrain"]), "grove", "terrain persists between Chapters")

func test_pass_preview_reports_score() -> void:
    var e := _new_match()
    var preview: Dictionary = e.pass_preview(0)
    _ok(preview.has("my_score") and preview.has("rival_score"), "preview reports both Realm Scores")
    _ok(preview.has("outcome"), "preview reports the likely Chapter result")
    e.board.shape(0, Vector2i(3, 3), "grove")
    e.board.shape(0, Vector2i(3, 2), "grove")
    var after: Dictionary = e.pass_preview(0)
    _ok(int(after["my_score"]) > int(preview["my_score"]), "shaping raised the Realm Score")
    e.free()

func test_attunement_gates_dual_cards() -> void:
    var e := _new_match()
    # Meltheart Salamander is frost+fire; a Life realm cannot cast it.
    _ok(not e.has_attunement(0, ["frost", "fire"]), "life realm lacks frost+fire")
    _force_hand(e, 0, "dual_meltheart_salamander")
    var r: Dictionary = e.play_card(0, "dual_meltheart_salamander", e.sanctuary_pos(0))
    _ok(not bool(r.get("ok", false)), "dual card is refused without both attunements")
    e.free()

func test_slice_commanders_have_distinct_identities() -> void:
    # COMMANDERS.md: a Commander is the player's identity, not a shared sentence.
    var mae: Dictionary = _db.get_commander("cmd_mossy_mae")
    var poppy: Dictionary = _db.get_commander("cmd_poppy_cinder")
    _ok(String(mae.get("passive_text", "")) != String(poppy.get("passive_text", "")),
        "the two slice Commanders do not share a passive")
    _ok(String(mae.get("command_text", "")) != String(poppy.get("command_text", "")),
        "the two slice Commanders do not share a Command")

func test_commander_passive_actually_fires() -> void:
    var e := _new_match()
    # Mossy Mae already healed 2 for the starting player; Poppy Cinder's opener
    # fires on her own first turn, which only arrives once player 1 has acted.
    var before: int = int(e.players[0]["heart"])
    _eq(before, MatchEngine.HEART_START + 2, "Mossy Mae's opener landed")
    # Read the amount from the data rather than hardcoding a tuning knob.
    var chip := 0
    for effect in _db.get_commander("cmd_poppy_cinder").get("passive", {}).get("effects", []):
        if String(effect.get("kind", "")) == "damage_heart": chip = int(effect.get("amount", 0))
    _ok(chip > 0, "Poppy Cinder's passive damages the Heart")
    e.pass_chapter(0)
    _eq(int(e.players[0]["heart"]), before - chip, "Poppy Cinder's opener hit the rival Heart")
    e.free()

func test_push_needs_a_second_target() -> void:
    var e := _new_match()
    _ok(e.card_needs_second_target("wind_tailwind"), "Tailwind asks for a push destination")
    _ok(not e.card_needs_second_target("life_grow"), "Grow does not")
    # Put an enemy creature in the middle of the board and shape a realm to cast from.
    var subject := Vector2i(3, 2)
    e.board.get_tile(subject)["creature"] = e.make_unit_from_card(_db.get_card("fire_ashcat"), 1)
    var destinations: Array[Vector2i] = e.legal_push_targets(subject)
    _ok(destinations.size() > 0, "the creature has somewhere to be pushed")
    _ok(not destinations.has(e.sanctuary_pos(0)), "nothing is ever pushed into a Sanctuary")
    # Tailwind is a Wind card, so the realm needs Wind Attunement first.
    e.board.shape(0, Vector2i(3, 3), "skygrass")
    _force_hand(e, 0, "wind_tailwind")
    # First click alone is refused, and asks for the second.
    var first: Dictionary = e.play_card(0, "wind_tailwind", subject)
    _ok(bool(first.get("needs_second_target", false)), "first click asks for a destination")
    _ok(e.players[0]["hand"].has("wind_tailwind"), "the refused card stayed in hand")
    var dest: Vector2i = destinations[0]
    var second: Dictionary = e.play_card(0, "wind_tailwind", subject, dest)
    _ok(bool(second.get("ok", false)), "the push resolves: %s" % str(second.get("reason", "")))
    _ok(e.board.get_tile(subject).get("creature") == null, "the creature left its tile")
    _ok(e.board.get_tile(dest).get("creature") != null, "the creature arrived on the destination")
    e.free()

## Guards the whole simulation: every match must finish, both decks must stay
## viable, and each must keep winning in its own way (PLAYTEST_MATRIX).
func test_slice_matchup_stays_healthy() -> void:
    var wins := [0, 0]
    var seals_for_life := 0
    var hearts_for_fire := 0
    var unfinished := 0
    var rounds := 40
    for i in range(rounds):
        var e := _new_match("starter_life", "starter_fire", 500 + i)
        var steps := _play_out(e, 1200)
        if not e.match_over:
            unfinished += 1
        else:
            wins[e.winner] += 1
            if e.winner == 0 and e.win_reason == "Two Chapter Seals": seals_for_life += 1
            if e.winner == 1 and e.win_reason == "Heart broken": hearts_for_fire += 1
        e.free()
    _eq(unfinished, 0, "every simulated match finished")
    _ok(wins[0] >= rounds / 5, "Life stays viable (%d/%d)" % [wins[0], rounds])
    _ok(wins[1] >= rounds / 5, "Fire stays viable (%d/%d)" % [wins[1], rounds])
    _ok(seals_for_life > 0, "Life still wins Chapters on Realm Score")
    _ok(hearts_for_fire > 0, "Fire still wins by breaking the Heart")

func test_every_starter_deck_is_legal() -> void:
    var validator := DeckValidator.new()
    for deck_id in _db.decks.keys():
        var errors: Array[String] = validator.validate(_db.get_deck(deck_id), _db)
        _ok(errors.is_empty(), "%s is legal (%s)" % [deck_id, ", ".join(errors)])
