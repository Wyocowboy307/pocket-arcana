class_name MatchV2
extends Node
## Pocket Arcana V2 — split-lane clarity prototype.
##
## Deliberately smaller than V1 (docs/V2_CLARITY_REDESIGN.md): four mirrored
## lanes a side, creatures never leave their own half, land is a real card that
## pays for magic, one Card Play and one Attack a turn, and the only way to win
## is to break the rival Heart.
##
## V1 (`MatchEngine`) is untouched and still runs, so the two can be compared.
##
## The simulation commits every result first and emits an event describing what
## happened. Animation reads those events; it never decides an outcome.

signal state_changed
signal event_emitted(event: Dictionary)
signal match_finished(winner: int)

const LANES := 4
const HEART_START := 20
const SANCTUARY_AETHER := 1
const OPENING_HAND := 5
const REALM_CARDS := 4

var db: ContentDatabase
var fusion_recipes: Array = []
var players: Array = []
var current_player := 0
var turn := 1
var match_over := false
var winner := -1
var win_reason := ""
var rng := RandomNumberGenerator.new()
var selected_seed := 20250826
var event_log: Array[String] = []
var _next_uid := 1

# --- setup ------------------------------------------------------------------

func setup(content: ContentDatabase, deck0 := "starter_life", deck1 := "starter_fire", match_seed := -1) -> void:
    db = content
    fusion_recipes = db.fusion_recipes
    if match_seed >= 0: selected_seed = match_seed
    rng.seed = selected_seed
    match_over = false
    winner = -1
    win_reason = ""
    event_log.clear()
    _next_uid = 1
    players = [_make_player(deck0), _make_player(deck1)]
    for p in range(2):
        _shuffle(players[p]["deck"])
        for _i in range(OPENING_HAND): _draw(p, false)
        # The signature home land is already there, so nobody stares at an empty
        # board wondering what to do first.
        _grow_land(p, 1, true)
    current_player = 0
    turn = 1
    _begin_turn(0)

func _make_player(deck_id: String) -> Dictionary:
    var deck_def := db.get_deck(deck_id)
    var commander := db.get_commander(String(deck_def.get("commander_id", "")))
    var element := String(commander.get("element", "life"))
    var terrain := String(db.elements.get(element, {}).get("terrain", "grove"))
    var deck: Array = []
    var realm_card := ""
    for entry in deck_def.get("cards", []):
        var cid := String(entry.get("card_id", ""))
        var card := db.get_card(cid)
        if String(card.get("type", "")) == "terrain":
            realm_card = cid          # land is pulled out into the Realm Stack
            continue
        for _i in range(int(entry.get("count", 0))): deck.append(cid)
    var lanes: Array = []
    for _i in range(LANES): lanes.append({"land": "", "creature": null, "place": null})
    return {
        "heart": HEART_START, "commander_id": String(deck_def.get("commander_id", "")),
        "element": element, "terrain": terrain, "realm_card": realm_card,
        "lanes": lanes, "deck": deck, "hand": [], "discard": [],
        "realm_stack": REALM_CARDS, "aether": 1, "max_aether": 1,
        "played_card": false, "attacked": false, "commander_used": false,
        "deck_name": String(deck_def.get("label", deck_id)),
    }

func _shuffle(deck: Array) -> void:
    for i in range(deck.size() - 1, 0, -1):
        var j := rng.randi_range(0, i)
        var tmp = deck[i]; deck[i] = deck[j]; deck[j] = tmp

func opponent(player: int) -> int:
    return 1 - player

func lane(player: int, index: int) -> Dictionary:
    return players[player]["lanes"][index]

func commander_element(player: int) -> String:
    return String(players[player]["element"])

# --- turn flow --------------------------------------------------------------

func _begin_turn(player: int) -> void:
    var p: Dictionary = players[player]
    p["played_card"] = false
    p["attacked"] = false
    if turn > 1 or player != 0:
        _draw(player, true)
    p["max_aether"] = SANCTUARY_AETHER + built_lands(player)
    p["aether"] = p["max_aether"]
    for l in p["lanes"]:
        if l["creature"] != null: l["creature"]["ready"] = true
    _emit({"type": "turn_started", "player": player, "turn": turn})
    _log("Turn %d — P%d." % [turn, player + 1])
    state_changed.emit()

func end_turn(player: int) -> Dictionary:
    if not _can_act(player): return _fail("It is not your turn.")
    _emit({"type": "turn_ended", "player": player})
    current_player = opponent(player)
    if current_player == 0: turn += 1
    _begin_turn(current_player)
    return {"ok": true}

func built_lands(player: int) -> int:
    var n := 0
    for l in players[player]["lanes"]:
        if String(l["land"]) != "": n += 1
    return n

func _draw(player: int, announce: bool) -> void:
    var p: Dictionary = players[player]
    if p["deck"].is_empty():
        # Running out of cards must never silently end the game in a prototype.
        if announce: _emit({"type": "deck_empty", "player": player})
        return
    var cid := String(p["deck"].pop_back())
    p["hand"].append(cid)
    if announce:
        _emit({"type": "card_drawn", "player": player, "card_id": cid,
               "hand_size": p["hand"].size()})

# --- land -------------------------------------------------------------------

func _grow_land(player: int, index: int, signature: bool) -> void:
    var p: Dictionary = players[player]
    var l: Dictionary = p["lanes"][index]
    l["land"] = String(p["terrain"])
    if p["realm_stack"] > 0: p["realm_stack"] -= 1
    p["max_aether"] = SANCTUARY_AETHER + built_lands(player)
    if signature: p["aether"] = p["max_aether"]
    _emit({"type": "land_built", "player": player, "lane": index,
           "terrain": l["land"], "element": p["element"], "signature": signature})

## Playing a Realm card costs no Aether — it costs your Card Play for the turn.
func play_realm(player: int, index: int) -> Dictionary:
    if not _can_act(player): return _fail("It is not your turn.")
    var p: Dictionary = players[player]
    if bool(p["played_card"]): return _fail("You have already played a card this turn.")
    if int(p["realm_stack"]) <= 0: return _fail("No Realm cards left.")
    if index < 0 or index >= LANES: return _fail("That lane is off the board.")
    if String(p["lanes"][index]["land"]) != "": return _fail("This lane already has land.")
    p["played_card"] = true
    _grow_land(player, index, false)
    _log("P%d built %s in lane %d." % [player + 1, String(p["terrain"]).capitalize(), index + 1])
    _after_action(player)
    return {"ok": true}

# --- cards ------------------------------------------------------------------

func card_role(card_id: String) -> String:
    match String(db.get_card(card_id).get("type", "")):
        "creature": return "Creature"
        "landmark": return "Place"
        "spell": return "Spell"
        "terrain": return "Realm"
    return "Spell"

## What a Spell is allowed to point at.
func spell_target_kind(card_id: String) -> String:
    var effects: Array = db.get_card(card_id).get("effects", [])
    for e in effects:
        if String(e.get("kind", "")) == "damage_unit": return "enemy_creature"
    for e in effects:
        if String(e.get("kind", "")) == "buff_unit": return "friendly_creature"
    for e in effects:
        if String(e.get("kind", "")) == "damage_heart": return "rival_heart"
    return "self"

## The single line printed on the card face.
func placement_line(card_id: String) -> String:
    var role := card_role(card_id)
    match role:
        "Creature", "Place":
            return "PLAY ON: %s" % _terrain_name_for_card(card_id).to_upper()
        "Realm":
            return "BUILD: EMPTY REALM SLOT"
    match spell_target_kind(card_id):
        "enemy_creature": return "TARGET: ENEMY CREATURE"
        "friendly_creature": return "TARGET: YOUR CREATURE"
        "rival_heart": return "TARGET: RIVAL HEART"
    return "TARGET: YOURSELF"

func _terrain_name_for_card(card_id: String) -> String:
    var els: Array = db.get_card(card_id).get("elements", [])
    if els.is_empty(): return "any land"
    var terrain := String(db.elements.get(String(els[0]), {}).get("terrain", ""))
    return terrain if terrain != "" else "any land"

func required_terrain(card_id: String) -> String:
    var els: Array = db.get_card(card_id).get("elements", [])
    if els.is_empty(): return ""
    return String(db.elements.get(String(els[0]), {}).get("terrain", ""))

## Every legal destination for a card, as {side, lane} pairs.
func legal_targets(player: int, card_id: String) -> Array:
    var out: Array = []
    if card_block_reason(player, card_id) != "": return out
    var role := card_role(card_id)
    if role == "Creature" or role == "Place":
        for i in range(LANES):
            if lane_block_reason(player, card_id, player, i) == "":
                out.append({"side": player, "lane": i})
        return out
    match spell_target_kind(card_id):
        "enemy_creature":
            var foe := opponent(player)
            for i in range(LANES):
                if lane(foe, i)["creature"] != null: out.append({"side": foe, "lane": i})
        "friendly_creature":
            for i in range(LANES):
                if lane(player, i)["creature"] != null: out.append({"side": player, "lane": i})
        "rival_heart":
            out.append({"side": opponent(player), "lane": -1})
        _:
            out.append({"side": player, "lane": -1})
    return out

## Why this card cannot be played at all right now.
func card_block_reason(player: int, card_id: String) -> String:
    var p: Dictionary = players[player]
    if match_over: return "The match is over."
    if current_player != player: return "Wait for your turn."
    if not p["hand"].has(card_id): return "That card is not in your hand."
    if bool(p["played_card"]): return "Card already played"
    var cost := int(db.get_card(card_id).get("cost", 0))
    var short := cost - int(p["aether"])
    if short > 0: return "Need %d more Aether" % short
    return ""

## Why this specific lane will not take the card.
func lane_block_reason(player: int, card_id: String, side: int, index: int) -> String:
    if index < 0 or index >= LANES: return "Not a lane."
    var role := card_role(card_id)
    var l := lane(side, index)
    if role == "Creature" or role == "Place":
        if side != player: return "That is the rival's land."
        var need := required_terrain(card_id)
        if String(l["land"]) == "": return "Build land here first"
        if need != "" and String(l["land"]) != need:
            return "Needs a %s" % need.capitalize()
        if role == "Creature" and l["creature"] != null: return "Creature slot occupied"
        if role == "Place" and l["place"] != null: return "Place slot occupied"
        return ""
    match spell_target_kind(card_id):
        "enemy_creature":
            if side == player: return "Target an enemy creature"
            if l["creature"] == null: return "No creature here"
        "friendly_creature":
            if side != player: return "Target your own creature"
            if l["creature"] == null: return "No creature here"
    return ""

func play_card(player: int, card_id: String, side: int, index: int) -> Dictionary:
    var blocked := card_block_reason(player, card_id)
    if blocked != "": return _fail(blocked)
    var role := card_role(card_id)
    if role == "Realm": return _fail("Realm cards come from your Realm Stack.")
    var needs_lane: bool = role in ["Creature", "Place"] or spell_target_kind(card_id) in ["enemy_creature", "friendly_creature"]
    if needs_lane:
        var why := lane_block_reason(player, card_id, side, index)
        if why != "": return _fail(why)

    var p: Dictionary = players[player]
    var card := db.get_card(card_id)
    p["aether"] = int(p["aether"]) - int(card.get("cost", 0))
    p["hand"].erase(card_id)
    p["played_card"] = true

    match role:
        "Creature":
            var unit := _make_unit(card, player, index)
            lane(player, index)["creature"] = unit
            _emit({"type": "creature_summoned", "player": player, "lane": index,
                   "card_id": card_id, "unit": unit})
            _log("P%d summoned %s." % [player + 1, String(card.get("name", card_id))])
        "Place":
            var place := {"card_id": card_id, "name": String(card.get("name", card_id)),
                          "owner": player, "presence": int(card.get("presence", 1))}
            lane(player, index)["place"] = place
            _emit({"type": "place_built", "player": player, "lane": index,
                   "card_id": card_id, "place": place})
            _log("P%d built %s." % [player + 1, String(card.get("name", card_id))])
        _:
            _emit({"type": "spell_cast", "player": player, "card_id": card_id,
                   "side": side, "lane": index, "target_kind": spell_target_kind(card_id)})
            _log("P%d cast %s." % [player + 1, String(card.get("name", card_id))])
            p["discard"].append(card_id)

    for effect in card.get("effects", []):
        _apply_effect(effect, player, side, index)
    _after_action(player)
    return {"ok": true}

func _make_unit(card: Dictionary, owner: int, index: int) -> Dictionary:
    var unit := {
        "uid": _next_uid, "card_id": String(card.get("id", "")),
        "name": String(card.get("name", "")), "owner": owner, "lane": index,
        "power": int(card.get("power", 0)), "health": int(card.get("health", 1)),
        "max_health": int(card.get("health", 1)),
        "ready": false,          # summoning sickness
    }
    _next_uid += 1
    return unit

# --- effects ----------------------------------------------------------------

func _apply_effect(effect: Dictionary, actor: int, side: int, index: int) -> void:
    var kind := String(effect.get("kind", ""))
    var amount := int(effect.get("amount", 0))
    var target := String(effect.get("target", ""))
    match kind:
        "damage_heart":
            var victim := opponent(actor) if target == "enemy" else actor
            players[victim]["heart"] = max(0, int(players[victim]["heart"]) - amount)
            _emit({"type": "heart_damaged", "player": victim, "amount": amount, "actor": actor})
        "heal_heart":
            var who := actor if target != "enemy" else opponent(actor)
            var before := int(players[who]["heart"])
            players[who]["heart"] = min(HEART_START + 10, before + amount)
            _emit({"type": "heart_healed", "player": who,
                   "amount": int(players[who]["heart"]) - before, "actor": actor})
        "damage_unit":
            if index < 0: return
            var unit = lane(side, index)["creature"]
            if unit == null: return
            unit["health"] = int(unit["health"]) - amount
            _emit({"type": "unit_damaged", "side": side, "lane": index,
                   "amount": amount, "unit": unit, "actor": actor})
            _clear_if_dead(side, index)
        "buff_unit":
            if index < 0: return
            var friend = lane(side, index)["creature"]
            if friend == null: return
            var dp := int(effect.get("power", 0)); var dh := int(effect.get("health", 0))
            friend["power"] = int(friend["power"]) + dp
            friend["health"] = int(friend["health"]) + dh
            friend["max_health"] = int(friend["max_health"]) + dh
            _emit({"type": "unit_buffed", "side": side, "lane": index,
                   "power": dp, "health": dh, "unit": friend, "actor": actor})
        "draw":
            for _i in range(amount): _draw(actor, true)
        "summon_token":
            if index < 0 or lane(actor, index)["creature"] != null: return
            var token := db.get_token(String(effect.get("token_id", "")))
            if token.is_empty(): return
            var unit2 := _make_unit({
                "id": "token:" + String(token.get("id", "")), "name": token.get("name", "Token"),
                "power": token.get("power", 1), "health": token.get("health", 1)}, actor, index)
            lane(actor, index)["creature"] = unit2
            _emit({"type": "creature_summoned", "player": actor, "lane": index,
                   "card_id": unit2["card_id"], "unit": unit2})
        # add_state / transform_terrain / gain_wonder have no meaning in V2 and
        # are intentionally ignored rather than faked.

func _clear_if_dead(side: int, index: int) -> void:
    var l := lane(side, index)
    var unit = l["creature"]
    if unit != null and int(unit["health"]) <= 0:
        l["creature"] = null
        players[side]["discard"].append(String(unit["card_id"]))
        _emit({"type": "unit_died", "side": side, "lane": index, "unit": unit})

# --- combat -----------------------------------------------------------------

func attack_block_reason(player: int, index: int) -> String:
    if match_over: return "The match is over."
    if current_player != player: return "Wait for your turn."
    if bool(players[player]["attacked"]): return "You have already attacked this turn."
    if index < 0 or index >= LANES: return "Not a lane."
    var unit = lane(player, index)["creature"]
    if unit == null: return "No creature in this lane"
    if not bool(unit["ready"]): return "Summoned this turn — it can attack next turn"
    if int(unit["power"]) <= 0: return "This creature has no Attack"
    return ""

func legal_attacks(player: int) -> Array:
    var out: Array = []
    for i in range(LANES):
        if attack_block_reason(player, i) == "": out.append(i)
    return out

## True when the lane opposite is empty, so the attack reaches the Heart.
func lane_is_open(player: int, index: int) -> bool:
    return lane(opponent(player), index)["creature"] == null

func attack(player: int, index: int) -> Dictionary:
    var blocked := attack_block_reason(player, index)
    if blocked != "": return _fail(blocked)
    var foe := opponent(player)
    var attacker: Dictionary = lane(player, index)["creature"]
    var defender = lane(foe, index)["creature"]
    players[player]["attacked"] = true
    attacker["ready"] = false

    if defender == null:
        var amount := int(attacker["power"])
        players[foe]["heart"] = max(0, int(players[foe]["heart"]) - amount)
        _emit({"type": "heart_attack", "player": player, "lane": index,
               "amount": amount, "unit": attacker})
        _log("P%d struck the rival Heart for %d." % [player + 1, amount])
    else:
        var dealt := int(attacker["power"])
        var back := int(defender["power"])
        defender["health"] = int(defender["health"]) - dealt
        attacker["health"] = int(attacker["health"]) - back
        _emit({"type": "creature_clash", "player": player, "lane": index,
               "attacker": attacker, "defender": defender,
               "damage_to_defender": dealt, "damage_to_attacker": back})
        _log("P%d attacked in lane %d." % [player + 1, index + 1])
        _clear_if_dead(foe, index)
        _clear_if_dead(player, index)
    _after_action(player)
    return {"ok": true}

# --- fusion -----------------------------------------------------------------

## Recipes that could be performed right now, each with its two source lanes.
func available_fusions(player: int) -> Array:
    var out: Array = []
    if bool(players[player]["played_card"]) or current_player != player or match_over: return out
    for recipe in fusion_recipes:
        var sources: Array = recipe.get("sources", [])
        if sources.size() != 2: continue
        for a in range(LANES):
            for b in range(LANES):
                if a == b: continue
                var ua = lane(player, a)["creature"]
                var ub = lane(player, b)["creature"]
                if ua == null or ub == null: continue
                if String(ua["card_id"]) != String(sources[0]): continue
                if String(ub["card_id"]) != String(sources[1]): continue
                out.append({"recipe": recipe, "a": a, "b": b,
                            "affordable": int(players[player]["aether"]) >= int(recipe.get("cost", 0))})
    return out

func fuse(player: int, recipe_id: String, lane_a: int, lane_b: int) -> Dictionary:
    if current_player != player or match_over: return _fail("Wait for your turn.")
    if bool(players[player]["played_card"]): return _fail("You have already played a card this turn.")
    var chosen: Dictionary = {}
    for option in available_fusions(player):
        if String(option["recipe"].get("id", "")) == recipe_id and int(option["a"]) == lane_a and int(option["b"]) == lane_b:
            chosen = option
            break
    if chosen.is_empty(): return _fail("Those two creatures cannot combine.")
    var recipe: Dictionary = chosen["recipe"]
    var cost := int(recipe.get("cost", 0))
    if int(players[player]["aether"]) < cost:
        return _fail("Need %d more Aether" % (cost - int(players[player]["aether"])))

    var source_a: Dictionary = lane(player, lane_a)["creature"]
    var source_b: Dictionary = lane(player, lane_b)["creature"]
    players[player]["aether"] = int(players[player]["aether"]) - cost
    players[player]["played_card"] = true
    lane(player, lane_a)["creature"] = null
    lane(player, lane_b)["creature"] = null

    var result_card := db.get_card(String(recipe.get("result", "")))
    var fused := _make_unit(result_card, player, lane_a)
    fused["ready"] = false
    lane(player, lane_a)["creature"] = fused
    _emit({"type": "fusion", "player": player, "recipe_id": recipe_id,
           "name": String(recipe.get("name", "")), "lane": lane_a, "freed_lane": lane_b,
           "sources": [source_a, source_b], "unit": fused})
    _log("P%d fused %s." % [player + 1, String(recipe.get("name", ""))])
    _after_action(player)
    return {"ok": true}

# --- commander --------------------------------------------------------------

func commander_block_reason(player: int) -> String:
    if match_over: return "The match is over."
    if current_player != player: return "Wait for your turn."
    if bool(players[player]["commander_used"]): return "Already used this match."
    if bool(players[player]["played_card"]): return "You have already played a card this turn."
    return ""

func use_commander(player: int, side: int, index: int) -> Dictionary:
    var blocked := commander_block_reason(player)
    if blocked != "": return _fail(blocked)
    var cmd := db.get_commander(String(players[player]["commander_id"]))
    players[player]["commander_used"] = true
    players[player]["played_card"] = true
    _emit({"type": "commander", "player": player, "name": String(cmd.get("name", "")),
           "side": side, "lane": index})
    for effect in cmd.get("command", {}).get("effects", []):
        _apply_effect(effect, player, side, index)
    # V2 Commands that only shaped terrain would do nothing, so they chip instead.
    if cmd.get("command", {}).get("effects", []).is_empty():
        _apply_effect({"kind": "damage_heart", "amount": 2, "target": "enemy"}, player, side, index)
    _log("P%d used %s." % [player + 1, String(cmd.get("name", "Commander"))])
    _after_action(player)
    return {"ok": true}

# --- helpers ----------------------------------------------------------------

func _can_act(player: int) -> bool:
    return not match_over and current_player == player

func _after_action(player: int) -> void:
    if _check_victory(): return
    state_changed.emit()

func _check_victory() -> bool:
    for p in range(2):
        if int(players[p]["heart"]) <= 0:
            _finish(opponent(p), "Heart broken")
            return true
    return false

func _finish(who: int, reason: String) -> void:
    if match_over: return
    match_over = true
    winner = who
    win_reason = reason
    _log("P%d wins: %s." % [who + 1, reason])
    _emit({"type": "match_finished", "winner": who, "reason": reason})
    match_finished.emit(who)
    state_changed.emit()

func _emit(event: Dictionary) -> void:
    event_emitted.emit(event)

func _log(text: String) -> void:
    event_log.append(text)
    if event_log.size() > 40: event_log.pop_front()

func _fail(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}
