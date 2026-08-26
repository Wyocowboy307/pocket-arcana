extends Node
## Regression suite for the V2 lane prototype. V1's suite is untouched and still
## runs; this proves the new rules independently.
##
##   Godot --headless --path . --scene res://scenes/dev/tests_v2.tscn

var _db := ContentDatabase.new()
var _failures: Array[String] = []
var _checks := 0
var _current := ""

func _ready() -> void:
    if not _db.load_all():
        push_error("V2 TEST: content failed to load")
        get_tree().quit(1)
        return
    for method in get_method_list():
        var name: String = method["name"]
        if name.begins_with("test_"):
            _current = name
            call(name)
    print("")
    if _failures.is_empty():
        print("V2 TESTS PASS — %d checks." % _checks)
        get_tree().quit(0)
    else:
        print("V2 TESTS FAILED — %d of %d checks failed:" % [_failures.size(), _checks])
        for f in _failures: print("  ✗ ", f)
        get_tree().quit(1)

func _ok(condition: bool, what: String) -> bool:
    _checks += 1
    if not condition: _failures.append("%s: %s" % [_current, what])
    return condition

func _eq(actual, expected, what: String) -> bool:
    return _ok(actual == expected, "%s (got %s, expected %s)" % [what, str(actual), str(expected)])

func _new(seed_value := 7) -> MatchV2:
    var e := MatchV2.new()
    add_child(e)
    e.setup(_db, "starter_life", "starter_fire", seed_value)
    return e

## Put a specific creature into a lane, ready to act.
func _place(e: MatchV2, player: int, index: int, card_id: String, ready := true) -> Dictionary:
    if String(e.lane(player, index)["land"]) == "":
        e.lane(player, index)["land"] = String(e.players[player]["terrain"])
    var unit: Dictionary = e._make_unit(_db.get_card(card_id), player, index)
    unit["ready"] = ready
    e.lane(player, index)["creature"] = unit
    return unit

# --- board and setup --------------------------------------------------------

func test_setup_gives_a_readable_board() -> void:
    var e := _new()
    _eq(e.players.size(), 2, "two players")
    _eq(e.players[0]["lanes"].size(), MatchV2.LANES, "four lanes a side")
    _eq(int(e.players[0]["heart"]), MatchV2.HEART_START, "starting Heart")
    _eq(e.players[0]["hand"].size(), MatchV2.OPENING_HAND, "opening hand")
    # The signature land is already grown, so turn one has something to do.
    _eq(e.built_lands(0), 1, "player 1 starts with a home land")
    _eq(e.built_lands(1), 1, "player 2 starts with a home land")
    _eq(String(e.lane(0, 1)["land"]), "grove", "Life home land is a Grove")
    _eq(String(e.lane(1, 1)["land"]), "cinder", "Fire home land is Cinder")
    _eq(int(e.players[0]["realm_stack"]), MatchV2.REALM_CARDS - 1, "one Realm card was spent on it")
    e.free()

func test_no_v1_systems_are_active() -> void:
    var e := _new()
    # V2 deliberately has no Chapters, Seals, Wonder or Pass.
    _ok(not e.players[0].has("seals"), "no Seals in V2")
    _ok(not e.players[0].has("wonder"), "no Wonder in V2")
    _ok(not e.players[0].has("passed"), "no passing in V2")
    _ok(not e.has_method("shape"), "no free Shape action in V2")
    e.free()

func test_aether_comes_from_land() -> void:
    var e := _new()
    _eq(int(e.players[0]["max_aether"]), MatchV2.SANCTUARY_AETHER + 1, "Sanctuary plus one land")
    _ok(bool(e.play_realm(0, 0).get("ok", false)), "second land builds")
    _eq(e.built_lands(0), 2, "two lands now")
    _eq(int(e.players[0]["max_aether"]), MatchV2.SANCTUARY_AETHER + 2, "capacity rose with the land")
    # Land costs the Card Play, not Aether.
    _ok(not bool(e.play_realm(0, 2).get("ok", false)), "only one card play per turn")
    e.free()

func test_one_card_and_one_attack_per_turn() -> void:
    var e := _new()
    _place(e, 0, 1, "life_sproutling")
    e.players[0]["aether"] = 9
    var hand_card := ""
    for cid in e.players[0]["hand"]:
        if e.card_role(String(cid)) == "Creature" and e.lane_block_reason(0, String(cid), 0, 0) != "":
            continue
    _ok(bool(e.attack(0, 1).get("ok", false)), "the ready creature attacks")
    _ok(not bool(e.attack(0, 1).get("ok", false)), "but only once a turn")
    _eq(e.attack_block_reason(0, 1), "You have already attacked this turn.", "and says why")
    e.free()

# --- placement clarity ------------------------------------------------------

func test_creatures_need_their_own_land() -> void:
    var e := _new()
    e.players[0]["hand"].append("life_sproutling")
    e.players[0]["aether"] = 9
    # Lane 1 is the Grove; lane 0 has no land at all.
    _eq(e.lane_block_reason(0, "life_sproutling", 0, 0), "Build land here first", "empty lane explains itself")
    _eq(e.lane_block_reason(0, "life_sproutling", 0, 1), "", "the Grove accepts it")
    _ok(bool(e.play_card(0, "life_sproutling", 0, 1).get("ok", false)), "summon lands")
    _eq(e.lane_block_reason(0, "life_sproutling", 0, 1), "Creature slot occupied", "occupied lane explains itself")
    e.free()

func test_a_creature_cannot_be_played_onto_rival_land() -> void:
    var e := _new()
    e.players[0]["hand"].append("life_sproutling")
    e.players[0]["aether"] = 9
    _eq(e.lane_block_reason(0, "life_sproutling", 1, 1), "That is the rival's land.", "rival land is refused")
    for t in e.legal_targets(0, "life_sproutling"):
        _eq(int(t["side"]), 0, "every legal target is on my own side")
    e.free()

func test_placement_lines_are_printed_not_inferred() -> void:
    var e := _new()
    _eq(e.placement_line("life_sproutling"), "PLAY ON: GROVE", "creature says where it lives")
    _eq(e.placement_line("fire_cinder_pup"), "PLAY ON: CINDER", "fire creature says Cinder")
    _eq(e.placement_line("life_herbalist_hut"), "PLAY ON: GROVE", "place says where it builds")
    _eq(e.placement_line("fire_scorch_mark"), "TARGET: ENEMY CREATURE", "damage spell targets a creature")
    _eq(e.placement_line("fire_dragon_breath"), "TARGET: RIVAL HEART", "burn spell targets the Heart")
    _eq(e.card_role("life_soft_meadow"), "Realm", "land card is a Realm card")
    e.free()

func test_aether_shortfall_is_stated_in_cards_not_jargon() -> void:
    var e := _new()
    e.players[0]["hand"].append("life_garden_dragon")     # costs 6
    e.players[0]["aether"] = 4
    _eq(e.card_block_reason(0, "life_garden_dragon"), "Need 2 more Aether", "shortfall is counted for the player")
    e.free()

# --- combat -----------------------------------------------------------------

func test_summoned_creatures_wait_a_turn() -> void:
    var e := _new()
    e.players[0]["hand"].append("life_sproutling")
    e.players[0]["aether"] = 9
    e.play_card(0, "life_sproutling", 0, 1)
    _eq(e.attack_block_reason(0, 1), "Summoned this turn — it can attack next turn", "summoning sickness explained")
    e.free()

func test_same_lane_combat_and_retaliation() -> void:
    var e := _new()
    var mine := _place(e, 0, 2, "life_great_stag")        # 5/7
    var theirs := _place(e, 1, 2, "fire_ashcat")          # 4/2
    _ok(bool(e.attack(0, 2).get("ok", false)), "attack resolves in its own lane")
    _ok(e.lane(1, 2)["creature"] == null, "the defender died to 5 damage")
    _eq(int(e.lane(0, 2)["creature"]["health"]), 7 - 4, "the attacker took retaliation")
    e.free()

func test_open_lane_reaches_the_heart() -> void:
    var e := _new()
    var mine := _place(e, 0, 3, "life_great_stag")        # 5 power
    _ok(e.lane_is_open(0, 3), "lane 3 has no defender")
    var before := int(e.players[1]["heart"])
    _ok(bool(e.attack(0, 3).get("ok", false)), "the attack goes through")
    _eq(int(e.players[1]["heart"]), before - 5, "the Heart took the creature's Attack")
    e.free()

func test_blocked_lane_does_not_reach_the_heart() -> void:
    var e := _new()
    _place(e, 0, 0, "life_great_stag")
    _place(e, 1, 0, "fire_magma_turtle")
    var before := int(e.players[1]["heart"])
    e.attack(0, 0)
    _eq(int(e.players[1]["heart"]), before, "a defender protects the Heart")
    e.free()

func test_breaking_the_heart_wins() -> void:
    var e := _new()
    e.players[1]["heart"] = 3
    _place(e, 0, 0, "life_great_stag")
    e.attack(0, 0)
    _ok(e.match_over, "the match ends")
    _eq(e.winner, 0, "the attacker wins")
    _eq(e.win_reason, "Heart broken", "for the only V2 reason")
    e.free()

# --- fusion -----------------------------------------------------------------

func test_fusion_recipes_load_and_resolve() -> void:
    var e := _new()
    _ok(e.fusion_recipes.size() >= 5, "five recipes for the prototype")
    _place(e, 0, 0, "life_sproutling")
    _place(e, 0, 1, "life_petal_deer")
    e.players[0]["aether"] = 9
    var options: Array = e.available_fusions(0)
    _ok(options.size() > 0, "the pair is offered, not hidden")
    var option: Dictionary = options[0]
    _eq(String(option["recipe"]["result"]), "life_great_stag", "it makes a Great Stag")
    _ok(bool(e.fuse(0, String(option["recipe"]["id"]), int(option["a"]), int(option["b"])).get("ok", false)),
        "fusion resolves")
    _eq(String(e.lane(0, 0)["creature"]["card_id"]), "life_great_stag", "the result stands in the first lane")
    _ok(e.lane(0, 1)["creature"] == null, "the second lane is freed")
    e.free()

func test_cross_element_fusion_exists() -> void:
    var e := _new()
    _place(e, 0, 0, "life_sproutling")
    _place(e, 0, 2, "fire_cinder_pup")
    e.players[0]["aether"] = 9
    var found := false
    for option in e.available_fusions(0):
        if String(option["recipe"]["id"]) == "fuse_ashbloom_fox": found = true
    _ok(found, "Life plus Fire offers the Ashbloom fusion")
    e.free()

func test_fusion_costs_the_card_play() -> void:
    var e := _new()
    _place(e, 0, 0, "life_sproutling")
    _place(e, 0, 1, "life_petal_deer")
    e.players[0]["aether"] = 9
    e.players[0]["played_card"] = true
    _eq(e.available_fusions(0).size(), 0, "no fusion after the card play is spent")
    e.free()

# --- full match -------------------------------------------------------------

func test_ai_match_completes() -> void:
    var ai := SimpleAIV2.new()
    var e := _new(11)
    var guard := 0
    while not e.match_over and guard < 300:
        ai.take_turn(e, e.current_player)
        guard += 1
    _ok(e.match_over, "an AI-vs-AI V2 match finishes (%d turns)" % guard)
    _ok(e.winner in [0, 1], "it has a winner")
    e.free()

func test_v2_is_deterministic() -> void:
    var ai := SimpleAIV2.new()
    var a := _new(99)
    var b := _new(99)
    for e in [a, b]:
        var guard := 0
        while not e.match_over and guard < 300:
            ai.take_turn(e, e.current_player)
            guard += 1
    _eq(a.winner, b.winner, "same seed, same winner")
    _eq(a.event_log, b.event_log, "same seed, identical log")
    a.free(); b.free()

func test_matchup_stays_playable() -> void:
    var ai := SimpleAIV2.new()
    var wins := [0, 0]
    var unfinished := 0
    for i in range(30):
        var e := _new(400 + i)
        var guard := 0
        while not e.match_over and guard < 300:
            ai.take_turn(e, e.current_player)
            guard += 1
        if e.match_over: wins[e.winner] += 1
        else: unfinished += 1
        e.free()
    _eq(unfinished, 0, "every V2 match finished")
    _ok(wins[0] > 0 and wins[1] > 0, "both decks win sometimes (%d/%d)" % [wins[0], wins[1]])
