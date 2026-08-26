extends Node
## Regression suite for the V3 elemental lane battler.
##
##   Godot --headless --path . --scene res://scenes/dev/tests_v3.tscn
##
## V1 and V2 suites are untouched and still run; this proves the V3 rules
## independently, because V3 changed the economy rather than only the look.

var _db := ContentV3.new()
var _failures: Array[String] = []
var _checks := 0
var _current := ""

func _ready() -> void:
    if not _db.load_all():
        push_error("V3 TEST: content failed to load")
        get_tree().quit(1)
        return
    for method in get_method_list():
        var name: String = method["name"]
        if name.begins_with("test_"):
            _current = name
            call(name)
    print("")
    if _failures.is_empty():
        print("V3 TESTS PASS — %d checks." % _checks)
        get_tree().quit(0)
    else:
        print("V3 TESTS FAILED — %d of %d checks failed:" % [_failures.size(), _checks])
        for f in _failures: print("  ✗ ", f)
        get_tree().quit(1)

func _check(condition: bool, what: String) -> void:
    _checks += 1
    if not condition: _failures.append("%s: %s" % [_current, what])

func _equal(got, want, what: String) -> void:
    _checks += 1
    if got != want: _failures.append("%s: %s (got %s, want %s)" % [_current, what, str(got), str(want)])

func _fresh() -> MatchV3:
    var m := MatchV3.new()
    m.setup(_db, "v3_life", "v3_fire", 4242)
    return m

## Put a card in hand regardless of the shuffle, so a test states its own setup.
func _give(m: MatchV3, player: int, card_id: String) -> void:
    m.players[player]["hand"].append(card_id)

func _land(m: MatchV3, player: int, index: int, terrain: String) -> void:
    m.lane(player, index)["terrain"] = terrain
    m.lane(player, index)["landscape_card"] = "land_grove" if terrain == "grove" else "land_cinder"

func _put(m: MatchV3, player: int, index: int, card_id: String, ready := true) -> Dictionary:
    var unit := m._make_unit(_db.card(card_id), player, index)
    unit["ready"] = ready
    m.lane(player, index)["creature"] = unit
    return unit

# --- content ---------------------------------------------------------------

func test_content_loads() -> void:
    _check(_db.cards.size() >= 20, "V3 set has cards")
    _check(_db.fusions.size() >= 4, "fusion recipes present")
    _check(_db.commanders.size() == 2, "two commanders")
    _check(not _db.deck("v3_life").is_empty(), "life deck exists")

func test_no_card_costs_more_than_four() -> void:
    # You hold at most four Landscapes, so a 5-cost card is unplayable by design.
    for card_id in _db.cards:
        var card: Dictionary = _db.cards[card_id]
        _check(int(card.get("cost", 0)) <= MatchV3.LANES,
            "%s costs %d, above the four-Landscape ceiling" % [card_id, int(card.get("cost", 0))])

func test_every_creature_and_support_prints_a_landscape() -> void:
    for card_id in _db.cards:
        var card: Dictionary = _db.cards[card_id]
        if String(card.get("type", "")) in ["creature", "support"]:
            _check(String(card.get("play_on", "")) != "", "%s prints PLAY ON" % card_id)

# --- economy ---------------------------------------------------------------

func test_pool_starts_empty() -> void:
    var m := _fresh()
    _equal(m.pool(0, "life"), 0, "no Landscapes means no resource")

func test_landscape_is_free_and_usable_immediately() -> void:
    var m := _fresh()
    _give(m, 0, "land_grove")
    var res := m.play_card(0, "land_grove", 0, 1)
    _check(bool(res["ok"]), "Landscape plays: %s" % str(res.get("reason", "")))
    _equal(m.pool(0, "life"), 1, "a Landscape played this turn is awake")
    _equal(String(m.lane(0, 1)["terrain"]), "grove", "lane took the terrain")

func test_one_landscape_per_turn() -> void:
    var m := _fresh()
    _give(m, 0, "land_grove"); _give(m, 0, "land_grove")
    m.play_card(0, "land_grove", 0, 0)
    _equal(m.card_block_reason(0, "land_grove"), "One Landscape per turn.", "second Landscape refused")

func test_pool_equals_landscapes_and_never_carries_over() -> void:
    var m := _fresh()
    _land(m, 0, 0, "grove"); _land(m, 0, 1, "grove"); _land(m, 0, 2, "cinder")
    m._begin_turn(0)
    _equal(m.pool(0, "life"), 2, "two Grove gives two Life")
    _equal(m.pool(0, "fire"), 1, "one Cinder gives one Fire")
    m.players[0]["pool"]["life"] = 0                     # spend it all
    m._begin_turn(0)
    _equal(m.pool(0, "life"), 2, "pool refreshes from land, it does not accumulate")

func test_costs_are_element_specific() -> void:
    var m := _fresh()
    _land(m, 0, 0, "cinder"); _land(m, 0, 1, "cinder")
    m._begin_turn(0)
    _give(m, 0, "life_petal_deer")
    var reason := m.card_block_reason(0, "life_petal_deer")
    _check(reason.contains("Life"), "Fire cannot pay a Life cost (got '%s')" % reason)

# --- placement -------------------------------------------------------------

func test_creature_needs_matching_landscape() -> void:
    var m := _fresh()
    _land(m, 0, 0, "cinder")
    m._begin_turn(0)
    m.players[0]["pool"]["life"] = 5
    _give(m, 0, "life_sproutling")
    var reason := m.lane_block_reason(0, "life_sproutling", 0, 0)
    _check(reason.contains("Grove"), "Sproutling refuses Cinder (got '%s')" % reason)
    _land(m, 0, 1, "grove")
    _equal(m.lane_block_reason(0, "life_sproutling", 0, 1), "", "Sproutling accepts Grove")

func test_bare_lane_refuses_creatures() -> void:
    var m := _fresh()
    m.players[0]["pool"]["life"] = 5
    _give(m, 0, "life_sproutling")
    _check(m.lane_block_reason(0, "life_sproutling", 0, 0).contains("no Landscape"),
        "an empty lane says so plainly")

func test_creature_enters_resting() -> void:
    var m := _fresh()
    _land(m, 0, 0, "grove")
    m._begin_turn(0)
    _give(m, 0, "life_sproutling")
    m.play_card(0, "life_sproutling", 0, 0)
    _check(not bool(m.lane(0, 0)["creature"]["ready"]), "a summoned creature rests")
    _check(m.attack_block_reason(0, 0).contains("resting"), "and cannot attack yet")

func test_one_creature_and_one_support_per_lane() -> void:
    var m := _fresh()
    _land(m, 0, 0, "grove")
    m._begin_turn(0); m.players[0]["pool"]["life"] = 9
    _put(m, 0, 0, "life_sproutling")
    _give(m, 0, "life_petal_deer")
    _check(m.lane_block_reason(0, "life_petal_deer", 0, 0).contains("already has a creature"),
        "lane holds one creature")
    _give(m, 0, "life_herbalist_hut")
    _equal(m.lane_block_reason(0, "life_herbalist_hut", 0, 0), "", "Support fits alongside")
    m.play_card(0, "life_herbalist_hut", 0, 0)
    _give(m, 0, "life_bee_garden")
    _check(m.lane_block_reason(0, "life_bee_garden", 0, 0).contains("already has a Support"),
        "lane holds one Support")

# --- combat ----------------------------------------------------------------

func test_attack_hits_the_creature_across() -> void:
    var m := _fresh()
    _land(m, 0, 1, "grove")
    m._begin_turn(0)
    _put(m, 0, 1, "life_petal_deer")                     # 3 power
    var defender := _put(m, 1, 1, "fire_magma_turtle")   # 4/6
    var res := m.attack(0, 1)
    _check(bool(res["ok"]), "attack resolves")
    _equal(int(defender["health"]), 3, "defender took the attacker's power")
    _equal(int(m.players[1]["heart"]), MatchV3.HEART_START, "the Heart was not touched")

## Both creatures land their blow. One-way damage made Health nearly worthless,
## and Life is built on Health — Fire took 63% of matches on raw Power alone.
func test_both_creatures_trade_damage() -> void:
    var m := _fresh()
    _land(m, 0, 1, "grove"); _land(m, 1, 1, "cinder")
    m._begin_turn(0)
    var attacker := _put(m, 0, 1, "life_bloom_bear")     # 4/6
    var defender := _put(m, 1, 1, "fire_cinder_hound")   # 3/3
    m.attack(0, 1)
    _check(m.lane(1, 1)["creature"] == null, "the defender took 4 and died")
    # 3 power, plus 1 from Poppy Cinder's Forge Heat for standing on Cinder.
    _equal(int(attacker["health"]), 2, "and the attacker took the buffed 4 back")
    _check(int(defender["health"]) <= 0, "the defender is spent")

func test_charging_a_bigger_body_costs_you() -> void:
    var m := _fresh()
    _land(m, 0, 1, "grove"); _land(m, 1, 1, "cinder")
    m._begin_turn(0)
    var attacker := _put(m, 0, 1, "life_sproutling")     # 1/3
    _put(m, 1, 1, "fire_blazewing_drake")                # 6/4
    m.attack(0, 1)
    _check(m.lane(0, 1)["creature"] == null, "attacking into a giant kills your own creature")
    _check(int(attacker["health"]) <= 0, "which is what makes attacking a decision")

func test_empty_lane_lets_the_blow_through_to_the_heart() -> void:
    var m := _fresh()
    _land(m, 0, 2, "grove")
    m._begin_turn(0)
    _put(m, 0, 2, "life_petal_deer")                     # 3 power
    _check(m.lane_is_open(0, 2), "the lane opposite is open")
    m.attack(0, 2)
    _equal(int(m.players[1]["heart"]), MatchV3.HEART_START - 3, "Heart took the damage")

func test_dead_creature_leaves_but_the_landscape_stays() -> void:
    var m := _fresh()
    _land(m, 0, 0, "grove"); _land(m, 1, 0, "cinder")
    m._begin_turn(0)
    _put(m, 0, 0, "life_bloom_bear")                     # 4 power
    _put(m, 1, 0, "fire_cinder_pup")                     # 2/1
    m.attack(0, 0)
    _check(m.lane(1, 0)["creature"] == null, "the defender died")
    _equal(String(m.lane(1, 0)["terrain"]), "cinder", "its Landscape remains")

func test_attacking_spends_the_creature() -> void:
    var m := _fresh()
    _land(m, 0, 0, "grove")
    m._begin_turn(0)
    _put(m, 0, 0, "life_petal_deer")
    m.attack(0, 0)
    _check(m.attack_block_reason(0, 0).contains("resting"), "one attack per turn")

# --- supports and commanders ----------------------------------------------

func test_support_buffs_power() -> void:
    var m := _fresh()
    _land(m, 0, 0, "grove")
    m._begin_turn(0)
    _put(m, 0, 0, "life_petal_deer")                     # 3 power
    _equal(m.effective_power(0, 0), 3, "unbuffed")
    m.lane(0, 0)["support"] = {"card_id": "life_bee_garden", "name": "Bee Garden", "owner": 0}
    _equal(m.effective_power(0, 0), 4, "Bee Garden adds a point of Power")

func test_commander_passive_forge_heat() -> void:
    var m := _fresh()
    _land(m, 1, 0, "cinder"); _land(m, 1, 1, "grove")
    _put(m, 1, 0, "fire_ashcat")                         # 3 power, standing on Cinder
    _put(m, 1, 1, "fire_ashcat")                         # same card, wrong land
    _equal(m.effective_power(1, 0), 4, "Forge Heat lifts a creature on Cinder")
    _equal(m.effective_power(1, 1), 3, "and only on Cinder")

func test_commander_passive_verdant_care() -> void:
    var m := _fresh()
    _land(m, 0, 0, "grove")
    m._begin_turn(0)
    var unit := _put(m, 0, 0, "life_bloom_bear")
    unit["health"] = 2
    m._end_of_turn_effects(0)
    _equal(int(unit["health"]), 4, "Verdant Care heals a creature standing on Grove")

func test_commander_power_is_once_per_match() -> void:
    var m := _fresh()
    _equal(m.power_block_reason(0), "", "power is available")
    var before: int = m.players[0]["hand"].size()
    m.use_power(0)
    _equal(m.players[0]["hand"].size(), before + 2, "Wild Spring drew two")
    _check(m.power_block_reason(0).contains("Already used"), "and only once")

func test_ember_rush_can_burn_a_creature_or_the_heart() -> void:
    var m := _fresh()
    m.current_player = 1
    var target := _put(m, 0, 2, "life_bloom_bear")       # 4/6
    m.use_power(1, 0, 2)
    _equal(int(target["health"]), 3, "Ember Rush hits the named creature")
    var m2 := _fresh()
    m2.current_player = 1
    m2.use_power(1)
    _equal(int(m2.players[0]["heart"]), MatchV3.HEART_START - 3, "or the Heart when none is named")

# --- fusion ----------------------------------------------------------------

func test_fusion_combines_two_creatures() -> void:
    var m := _fresh()
    _land(m, 0, 0, "grove"); _land(m, 0, 1, "grove")
    m._begin_turn(0)
    m.players[0]["pool"]["life"] = 4
    _put(m, 0, 0, "life_sproutling")
    _put(m, 0, 1, "life_petal_deer")
    var options := m.available_fusions(0)
    _check(options.size() >= 1, "Antler Communion is offered")
    var res := m.fuse(0, "fuse_great_stag", 0, 1)
    _check(bool(res["ok"]), "fusion resolves: %s" % str(res.get("reason", "")))
    _equal(String(m.lane(0, 0)["creature"]["card_id"]), "life_great_stag", "the result stands in the first lane")
    _check(m.lane(0, 1)["creature"] == null, "the second creature was consumed")
    _equal(String(m.lane(0, 1)["terrain"]), "grove", "but its Landscape remains")

func test_fused_creature_arrives_ready() -> void:
    var m := _fresh()
    _land(m, 0, 0, "grove"); _land(m, 0, 1, "grove")
    m._begin_turn(0); m.players[0]["pool"]["life"] = 4
    _put(m, 0, 0, "life_sproutling"); _put(m, 0, 1, "life_petal_deer")
    m.fuse(0, "fuse_great_stag", 0, 1)
    _equal(m.attack_block_reason(0, 0), "", "two bodies already paid for the tempo")

func test_fusion_needs_the_right_landscape_and_resource() -> void:
    var m := _fresh()
    _land(m, 0, 0, "cinder"); _land(m, 0, 1, "grove")
    m._begin_turn(0); m.players[0]["pool"]["life"] = 4
    _put(m, 0, 0, "life_sproutling"); _put(m, 0, 1, "life_petal_deer")
    _check(m.fusion_block_reason(0, "fuse_great_stag", 0, 1).contains("Grove"),
        "the result needs its own land")
    var m2 := _fresh()
    _land(m2, 0, 0, "grove"); _land(m2, 0, 1, "grove")
    m2._begin_turn(0); m2.players[0]["pool"]["life"] = 0
    _put(m2, 0, 0, "life_sproutling"); _put(m2, 0, 1, "life_petal_deer")
    _check(m2.fusion_block_reason(0, "fuse_great_stag", 0, 1).contains("Needs"),
        "and it still costs resource")

func test_fusion_only_creatures_are_not_in_the_deck() -> void:
    var deck: Dictionary = _db.deck("v3_life")
    for entry in deck.get("cards", []):
        _check(String(entry.get("card_id", "")) != "life_elaria_mother_of_groves",
            "Elaria is reachable only through Fusion")

# --- winning ---------------------------------------------------------------

func test_breaking_the_heart_wins() -> void:
    var m := _fresh()
    _land(m, 0, 0, "grove")
    m._begin_turn(0)
    m.players[1]["heart"] = 3
    _put(m, 0, 0, "life_bloom_bear")                     # 4 power, open lane
    m.attack(0, 0)
    _check(m.match_over, "the match ended")
    _equal(m.winner, 0, "the attacker won")

func test_turn_passes_and_the_rival_refreshes() -> void:
    var m := _fresh()
    _land(m, 1, 0, "cinder")
    m.end_turn(0)
    _equal(m.current_player, 1, "turn passed")
    _equal(m.pool(1, "fire"), 1, "the rival's land paid out")
