class_name MatchV3
extends RefCounted
## The V3 elemental lane battler — see docs/V3_LANE_BATTLER.md.
##
## Deterministic simulation. Nothing here knows about drawing: the view asks for
## legal actions and exact refusal reasons, and animation only ever reports state
## this has already committed.
##
## The shape of the game, in one place:
##   four lanes a side, each holding a Landscape, a Creature and a Support;
##   your pool of an element equals the Landscapes of that element you control;
##   creatures fight straight across, and an empty lane lets the blow through
##   to the Heart behind it.

signal state_changed
signal event_emitted(event: Dictionary)
signal match_finished(winner: int)

const LANES := 4
const HEART_START := 30
const OPENING_HAND := 5
const MAX_HAND := 9
const ELEMENTS := ["life", "fire"]
const TERRAIN_ELEMENT := {"grove": "life", "cinder": "fire"}

var db: ContentV3
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

func setup(content: ContentV3, deck0 := "v3_life", deck1 := "v3_fire", match_seed := -1) -> void:
    db = content
    selected_seed = match_seed if match_seed >= 0 else selected_seed
    rng.seed = selected_seed
    players = [_make_player(deck0), _make_player(deck1)]
    current_player = 0
    turn = 1
    match_over = false
    winner = -1
    win_reason = ""
    event_log.clear()
    for player in range(2):
        for _i in range(OPENING_HAND):
            _draw(player, false)
    _begin_turn(current_player)
    state_changed.emit()

func _make_player(deck_id: String) -> Dictionary:
    var deck_data := db.deck(deck_id)
    var element := String(deck_data.get("element", "life"))
    var deck: Array = []
    for entry in deck_data.get("cards", []):
        for _i in range(int(entry.get("count", 1))):
            deck.append(String(entry.get("card_id", "")))
    _shuffle(deck)
    return {
        "deck_id": deck_id,
        "element": element,
        "commander_id": String(deck_data.get("commander_id", "")),
        "heart": HEART_START,
        "deck": deck,
        "hand": [],
        "discard": [],
        "lanes": _empty_lanes(),
        # Pool is rebuilt from Landscapes every turn; it never carries over.
        "pool": {"life": 0, "fire": 0},
        "land_played": false,
        "power_used": false,
        "fatigue": 0,
    }

func _empty_lanes() -> Array:
    var out: Array = []
    for _i in range(LANES):
        out.append({"terrain": "", "landscape_card": "", "creature": null, "support": null})
    return out

func _shuffle(deck: Array) -> void:
    for i in range(deck.size() - 1, 0, -1):
        var j := rng.randi_range(0, i)
        var tmp = deck[i]; deck[i] = deck[j]; deck[j] = tmp

# --- reading the board ------------------------------------------------------

func opponent(player: int) -> int:
    return 1 - player

func lane(player: int, index: int) -> Dictionary:
    return players[player]["lanes"][index]

func commander(player: int) -> Dictionary:
    return db.commander(String(players[player]["commander_id"]))

## How many Landscapes of an element a player controls. This *is* their income.
func landscape_count(player: int, element: String) -> int:
    var total := 0
    for i in range(LANES):
        var terrain := String(lane(player, i)["terrain"])
        if terrain != "" and String(TERRAIN_ELEMENT.get(terrain, "")) == element:
            total += 1
    return total

func pool(player: int, element: String) -> int:
    return int(players[player]["pool"].get(element, 0))

## Power after the Support in its lane and the Commander's passive. Presentation
## reads this rather than the raw card, so a buffed creature shows its real number.
func effective_power(player: int, index: int) -> int:
    var unit = lane(player, index)["creature"]
    if unit == null: return 0
    var total := int(unit["power"])
    var support = lane(player, index)["support"]
    if support != null:
        var effect: Dictionary = db.card(String(support["card_id"])).get("effect", {})
        if String(effect.get("kind", "")) == "power_here":
            total += int(effect.get("amount", 0))
    var passive: Dictionary = commander(player).get("passive", {})
    if String(passive.get("kind", "")) == "power_on_terrain" \
            and String(lane(player, index)["terrain"]) == String(passive.get("terrain", "")):
        total += int(passive.get("amount", 0))
    return maxi(0, total)

# --- turn structure ---------------------------------------------------------

func _begin_turn(player: int) -> void:
    var p: Dictionary = players[player]
    # Your pool is your land. Recalculated, never accumulated.
    for element in ELEMENTS:
        p["pool"][element] = landscape_count(player, element)
    p["land_played"] = false
    for i in range(LANES):
        var unit = lane(player, i)["creature"]
        if unit != null: unit["ready"] = true
    _draw(player, true)
    _emit({"type": "turn_started", "player": player, "turn": turn})

func end_turn(player: int) -> Dictionary:
    if match_over: return {"ok": false, "reason": "The match is over."}
    if player != current_player: return {"ok": false, "reason": "It is not your turn."}
    _end_of_turn_effects(player)
    if match_over: return {"ok": true}
    current_player = opponent(player)
    if current_player == 0: turn += 1
    _begin_turn(current_player)
    state_changed.emit()
    return {"ok": true}

## Supports and the Commander's passive both tick here, so a player can see the
## result of their board before handing over.
func _end_of_turn_effects(player: int) -> void:
    var passive: Dictionary = commander(player).get("passive", {})
    var heal_terrain := ""
    var heal_amount := 0
    if String(passive.get("kind", "")) == "heal_on_terrain":
        heal_terrain = String(passive.get("terrain", ""))
        heal_amount = int(passive.get("amount", 0))
    for i in range(LANES):
        var l: Dictionary = lane(player, i)
        var unit = l["creature"]
        if unit == null: continue
        var healed := 0
        var support = l["support"]
        if support != null:
            var effect: Dictionary = db.card(String(support["card_id"])).get("effect", {})
            if String(effect.get("kind", "")) == "heal_here":
                healed += int(effect.get("amount", 0))
        if heal_terrain != "" and String(l["terrain"]) == heal_terrain:
            healed += heal_amount
        if healed > 0 and int(unit["health"]) < int(unit["max_health"]):
            var before := int(unit["health"])
            unit["health"] = mini(int(unit["max_health"]), before + healed)
            _emit({"type": "creature_healed", "player": player, "lane": i,
                   "amount": int(unit["health"]) - before, "unit": unit})

func _draw(player: int, announce: bool) -> void:
    var p: Dictionary = players[player]
    if p["deck"].is_empty():
        # Fatigue. Without it two empty boards with two empty decks can sit
        # opposite each other forever — one self-test match ran 201 turns and
        # never finished. Drawing on nothing costs you, and rising, so a match
        # always terminates.
        p["fatigue"] = int(p["fatigue"]) + 1
        if announce:
            _emit({"type": "fatigue", "player": player, "amount": int(p["fatigue"])})
            _damage_heart(player, int(p["fatigue"]))
        return
    var card_id: String = p["deck"].pop_back()
    if p["hand"].size() >= MAX_HAND:
        p["discard"].append(card_id)
        if announce: _emit({"type": "hand_full", "player": player, "card_id": card_id})
        return
    p["hand"].append(card_id)
    if announce: _emit({"type": "card_drawn", "player": player, "card_id": card_id})

func _emit(event: Dictionary) -> void:
    event_log.append(String(event.get("type", "")))
    event_emitted.emit(event)

func _make_unit(card: Dictionary, owner: int, index: int) -> Dictionary:
    var unit := {
        "uid": _next_uid, "card_id": String(card.get("id", "")),
        "name": String(card.get("name", "")), "element": String(card.get("element", "")),
        "power": int(card.get("power", 0)), "health": int(card.get("health", 1)),
        "max_health": int(card.get("health", 1)), "owner": owner, "lane": index,
        "ready": false,
    }
    _next_uid += 1
    return unit

# --- legality ---------------------------------------------------------------

func card_role(card_id: String) -> String:
    return db.card_type(card_id)

## The `PLAY ON` line, printed on the card rather than inferred by the player.
func placement_line(card_id: String) -> String:
    var card := db.card(card_id)
    match String(card.get("type", "")):
        "landscape": return "PLAY ON: ANY EMPTY LANE"
        "creature": return "PLAY ON: %s" % String(card.get("play_on", "")).to_upper()
        "support": return "ATTACH TO: %s" % String(card.get("play_on", "")).to_upper()
        "spell":
            return "TARGET: A CREATURE" if String(card.get("target", "none")) == "creature" \
                else "CAST ANY TIME"
    return ""

## Why this card cannot be played at all right now, or "" if it can.
func card_block_reason(player: int, card_id: String) -> String:
    if match_over: return "The match is over."
    if player != current_player: return "It is not your turn."
    var card := db.card(card_id)
    if card.is_empty(): return "Unknown card."
    var kind := String(card.get("type", ""))
    if kind == "landscape":
        if bool(players[player]["land_played"]): return "One Landscape per turn."
        if _first_empty_landscape(player) < 0: return "Every lane already has a Landscape."
        return ""
    var element := String(card.get("element", ""))
    var cost := int(card.get("cost", 0))
    if pool(player, element) < cost:
        return "Needs %d %s — you have %d." % [cost, element.capitalize(), pool(player, element)]
    if kind in ["creature", "support"]:
        if legal_targets(player, card_id).is_empty():
            return "No lane has a %s Landscape with room." % String(card.get("play_on", "")).capitalize()
    return ""

func _first_empty_landscape(player: int) -> int:
    for i in range(LANES):
        if String(lane(player, i)["terrain"]) == "": return i
    return -1

## Every lane this card may legally enter, as {"side": s, "lane": i}.
func legal_targets(player: int, card_id: String) -> Array:
    var out: Array = []
    var card := db.card(card_id)
    var kind := String(card.get("type", ""))
    match kind:
        "landscape":
            for i in range(LANES):
                if String(lane(player, i)["terrain"]) == "":
                    out.append({"side": player, "lane": i})
        "creature":
            for i in range(LANES):
                var l: Dictionary = lane(player, i)
                if String(l["terrain"]) == String(card.get("play_on", "")) and l["creature"] == null:
                    out.append({"side": player, "lane": i})
        "support":
            for i in range(LANES):
                var l2: Dictionary = lane(player, i)
                if String(l2["terrain"]) == String(card.get("play_on", "")) and l2["support"] == null:
                    out.append({"side": player, "lane": i})
        "spell":
            if String(card.get("target", "none")) == "creature":
                for side in range(2):
                    for i in range(LANES):
                        if lane(side, i)["creature"] != null:
                            out.append({"side": side, "lane": i})
    return out

## Why this card cannot go in this specific lane.
##
## The most specific reason wins. Checking affordability and "is there anywhere
## at all" first meant that pointing at a lane already holding a creature
## answered "No lane has a Grove Landscape with room" — true, but not an answer
## to what the player asked.
func lane_block_reason(player: int, card_id: String, side: int, index: int) -> String:
    if match_over: return "The match is over."
    if player != current_player: return "It is not your turn."
    var card := db.card(card_id)
    if card.is_empty(): return "Unknown card."
    var kind := String(card.get("type", ""))
    var l: Dictionary = lane(side, index)

    match kind:
        "landscape":
            if side != player: return "Landscapes go in your own lanes."
            if String(l["terrain"]) != "": return "This lane already has a Landscape."
            if bool(players[player]["land_played"]): return "One Landscape per turn."
            return ""
        "creature":
            if side != player: return "Creatures go in your own lanes."
            if String(l["terrain"]) == "": return "This lane has no Landscape yet."
            if String(l["terrain"]) != String(card.get("play_on", "")):
                return "%s must be played on %s." % [String(card.get("name", "")),
                    String(card.get("play_on", "")).capitalize()]
            if l["creature"] != null: return "This lane already has a creature."
        "support":
            if side != player: return "Supports attach to your own lanes."
            if String(l["terrain"]) == "": return "This lane has no Landscape yet."
            if String(l["terrain"]) != String(card.get("play_on", "")):
                return "%s attaches to %s." % [String(card.get("name", "")),
                    String(card.get("play_on", "")).capitalize()]
            if l["support"] != null: return "This lane already has a Support."
        "spell":
            if String(card.get("target", "none")) == "creature" and l["creature"] == null:
                return "That spell needs a creature to target."

    # Only once the lane itself is fine does the price matter.
    var element := String(card.get("element", ""))
    var cost := int(card.get("cost", 0))
    if pool(player, element) < cost:
        return "Needs %d %s — you have %d." % [cost, element.capitalize(), pool(player, element)]
    return ""

# --- playing ----------------------------------------------------------------

func play_card(player: int, card_id: String, side: int, index: int) -> Dictionary:
    var blocked := lane_block_reason(player, card_id, side, index)
    if blocked != "": return {"ok": false, "reason": blocked}
    var p: Dictionary = players[player]
    if not p["hand"].has(card_id): return {"ok": false, "reason": "That card is not in your hand."}
    var card := db.card(card_id)
    var kind := String(card.get("type", ""))
    var element := String(card.get("element", ""))
    var cost := int(card.get("cost", 0))

    p["hand"].erase(card_id)
    if kind == "landscape":
        p["land_played"] = true
        var terrain := String(card.get("terrain", ""))
        lane(player, index)["terrain"] = terrain
        lane(player, index)["landscape_card"] = card_id
        # A Landscape enters awake, so playing land always does something now.
        p["pool"][element] = pool(player, element) + 1
        _emit({"type": "landscape_played", "player": player, "lane": index,
               "card_id": card_id, "terrain": terrain, "element": element})
    else:
        p["pool"][element] = pool(player, element) - cost
        match kind:
            "creature":
                var unit := _make_unit(card, player, index)
                lane(player, index)["creature"] = unit
                _emit({"type": "creature_played", "player": player, "lane": index,
                       "card_id": card_id, "unit": unit})
                _apply_effect(card.get("effect", null), player, side, index)
            "support":
                lane(player, index)["support"] = {"card_id": card_id,
                    "name": String(card.get("name", "")), "owner": player}
                _emit({"type": "support_played", "player": player, "lane": index,
                       "card_id": card_id})
            "spell":
                _emit({"type": "spell_cast", "player": player, "card_id": card_id,
                       "side": side, "lane": index})
                _apply_effect(card.get("effect", null), player, side, index)
                p["discard"].append(card_id)
    _check_finished()
    state_changed.emit()
    return {"ok": true}

func _apply_effect(effect, actor: int, side: int, index: int) -> void:
    if effect is not Dictionary or effect.is_empty(): return
    var kind := String(effect.get("kind", ""))
    var amount := int(effect.get("amount", 0))
    match kind:
        "draw":
            for _i in range(amount): _draw(actor, true)
        "heal_heart":
            var before := int(players[actor]["heart"])
            players[actor]["heart"] = mini(HEART_START, before + amount)
            _emit({"type": "heart_changed", "player": actor,
                   "amount": int(players[actor]["heart"]) - before, "heal": true})
        "damage_heart":
            _damage_heart(opponent(actor), amount)
        "heal_creature":
            var unit = lane(side, index)["creature"]
            if unit != null:
                var before2 := int(unit["health"])
                unit["health"] = mini(int(unit["max_health"]), before2 + amount)
                _emit({"type": "creature_healed", "player": side, "lane": index,
                       "amount": int(unit["health"]) - before2, "unit": unit})
        "damage_creature":
            _damage_creature(side, index, amount, "spell")

func _damage_heart(target: int, amount: int) -> void:
    if amount <= 0: return
    players[target]["heart"] = maxi(0, int(players[target]["heart"]) - amount)
    _emit({"type": "heart_changed", "player": target, "amount": -amount, "heal": false})
    _check_finished()

func _damage_creature(side: int, index: int, amount: int, source: String) -> void:
    var unit = lane(side, index)["creature"]
    if unit == null or amount <= 0: return
    unit["health"] = int(unit["health"]) - amount
    _emit({"type": "creature_damaged", "player": side, "lane": index,
           "amount": amount, "unit": unit, "source": source})
    if int(unit["health"]) <= 0:
        lane(side, index)["creature"] = null
        players[side]["discard"].append(String(unit["card_id"]))
        _emit({"type": "creature_died", "player": side, "lane": index, "unit": unit})

# --- combat -----------------------------------------------------------------

func attack_block_reason(player: int, index: int) -> String:
    if match_over: return "The match is over."
    if player != current_player: return "It is not your turn."
    var unit = lane(player, index)["creature"]
    if unit == null: return "No creature in that lane."
    if not bool(unit["ready"]): return "%s is resting this turn." % String(unit["name"])
    return ""

func legal_attacks(player: int) -> Array:
    var out: Array = []
    for i in range(LANES):
        if attack_block_reason(player, i) == "": out.append(i)
    return out

## True when the lane opposite is empty, so an attack there reaches the Heart.
func lane_is_open(player: int, index: int) -> bool:
    return lane(opponent(player), index)["creature"] == null

## Straight across, and both creatures land their blow.
##
## This was one-way at first — attacker hits, defender answers on its own turn.
## That reads fine but it makes Health nearly worthless, because a defender never
## uses it, and Life's whole identity is Health. Fire took 63% of matches on raw
## Power. Trading both ways is no harder to explain ("they both hit each other"),
## it restores the point of a tough creature, and it turns attacking into a
## decision rather than a formality.
func attack(player: int, index: int) -> Dictionary:
    var blocked := attack_block_reason(player, index)
    if blocked != "": return {"ok": false, "reason": blocked}
    var attacker: Dictionary = lane(player, index)["creature"]
    var foe := opponent(player)
    var defender = lane(foe, index)["creature"]
    var damage := effective_power(player, index)
    attacker["ready"] = false

    var support = lane(player, index)["support"]
    var sear := 0
    if support != null:
        var effect: Dictionary = db.card(String(support["card_id"])).get("effect", {})
        if String(effect.get("kind", "")) == "sear_on_attack":
            sear = int(effect.get("amount", 0))

    if defender == null:
        _emit({"type": "heart_attack", "player": player, "lane": index,
               "attacker": attacker, "damage": damage})
        _damage_heart(foe, damage)
    else:
        var back := effective_power(foe, index)
        _emit({"type": "creature_clash", "player": player, "lane": index,
               "attacker": attacker, "defender": defender,
               "damage": damage, "damage_back": back})
        _damage_creature(foe, index, damage, "attack")
        _damage_creature(player, index, back, "clash")
    if sear > 0: _damage_heart(foe, sear)
    _check_finished()
    state_changed.emit()
    return {"ok": true, "damage": damage, "to_heart": defender == null}

# --- fusion -----------------------------------------------------------------

## Every fusion the player could pay for right now, with the lanes involved.
func available_fusions(player: int) -> Array:
    var out: Array = []
    for recipe in db.fusions:
        var sources: Array = recipe.get("sources", [])
        if sources.size() < 2: continue
        for a in range(LANES):
            for b in range(LANES):
                if a == b: continue
                var ua = lane(player, a)["creature"]
                var ub = lane(player, b)["creature"]
                if ua == null or ub == null: continue
                if String(ua["card_id"]) != String(sources[0]): continue
                if String(ub["card_id"]) != String(sources[1]): continue
                if fusion_block_reason(player, String(recipe.get("id", "")), a, b) != "": continue
                out.append({"recipe": recipe, "a": a, "b": b})
    return out

func fusion_block_reason(player: int, recipe_id: String, lane_a: int, lane_b: int) -> String:
    if match_over: return "The match is over."
    if player != current_player: return "It is not your turn."
    var recipe := db.fusion(recipe_id)
    if recipe.is_empty(): return "Unknown fusion."
    var sources: Array = recipe.get("sources", [])
    var ua = lane(player, lane_a)["creature"]
    var ub = lane(player, lane_b)["creature"]
    if ua == null or ub == null: return "Both creatures must be on the board."
    if String(ua["card_id"]) != String(sources[0]) or String(ub["card_id"]) != String(sources[1]):
        return "Those creatures do not combine."
    var element := String(recipe.get("element", ""))
    var cost := int(recipe.get("cost", 0))
    if pool(player, element) < cost:
        return "Needs %d %s — you have %d." % [cost, element.capitalize(), pool(player, element)]
    var result := db.card(String(recipe.get("result", "")))
    if String(lane(player, lane_a)["terrain"]) != String(result.get("play_on", "")):
        return "%s must stand on %s." % [String(result.get("name", "")),
            String(result.get("play_on", "")).capitalize()]
    return ""

func fuse(player: int, recipe_id: String, lane_a: int, lane_b: int) -> Dictionary:
    var blocked := fusion_block_reason(player, recipe_id, lane_a, lane_b)
    if blocked != "": return {"ok": false, "reason": blocked}
    var recipe := db.fusion(recipe_id)
    var element := String(recipe.get("element", ""))
    var source_a: Dictionary = lane(player, lane_a)["creature"]
    var source_b: Dictionary = lane(player, lane_b)["creature"]
    players[player]["pool"][element] = pool(player, element) - int(recipe.get("cost", 0))

    lane(player, lane_a)["creature"] = null
    lane(player, lane_b)["creature"] = null
    var result_card := db.card(String(recipe.get("result", "")))
    var fused := _make_unit(result_card, player, lane_a)
    # Two bodies is already the price; the fused creature arrives ready to act.
    fused["ready"] = true
    lane(player, lane_a)["creature"] = fused
    _emit({"type": "fusion", "player": player, "recipe_id": recipe_id,
           "name": String(recipe.get("name", "")), "lane": lane_a, "freed_lane": lane_b,
           "sources": [source_a, source_b], "unit": fused})
    _apply_effect(result_card.get("effect", null), player, player, lane_a)
    _check_finished()
    state_changed.emit()
    return {"ok": true}

# --- commander --------------------------------------------------------------

func power_block_reason(player: int) -> String:
    if match_over: return "The match is over."
    if player != current_player: return "It is not your turn."
    if bool(players[player]["power_used"]): return "Already used this match."
    return ""

func use_power(player: int, side := -1, index := -1) -> Dictionary:
    var blocked := power_block_reason(player)
    if blocked != "": return {"ok": false, "reason": blocked}
    var cmd := commander(player)
    var power: Dictionary = cmd.get("power", {})
    var kind := String(power.get("kind", ""))
    var amount := int(power.get("amount", 0))
    players[player]["power_used"] = true
    _emit({"type": "commander_power", "player": player,
           "name": String(cmd.get("power_name", "")), "side": side, "lane": index})
    match kind:
        "draw":
            for _i in range(amount): _draw(player, true)
        "burst":
            # Ember Rush: a named enemy creature, or the Heart behind an empty lane.
            if side >= 0 and index >= 0 and lane(side, index)["creature"] != null:
                _damage_creature(side, index, amount, "power")
            else:
                _damage_heart(opponent(player), amount)
    _check_finished()
    state_changed.emit()
    return {"ok": true}

func power_target_kind(player: int) -> String:
    return String(commander(player).get("power_target", "none"))

# --- finishing --------------------------------------------------------------

func _check_finished() -> void:
    if match_over: return
    for player in range(2):
        if int(players[player]["heart"]) <= 0:
            match_over = true
            winner = opponent(player)
            win_reason = "%s's Heart broke." % String(commander(player).get("name", "The rival"))
            _emit({"type": "match_finished", "winner": winner, "reason": win_reason})
            match_finished.emit(winner)
            return

func summary() -> String:
    var out := "Turn %d — %s to act\n" % [turn, String(commander(current_player).get("name", ""))]
    for player in range(2):
        var p: Dictionary = players[player]
        out += "  P%d %s heart %d  pool L%d/F%d  hand %d\n" % [player,
            String(p["element"]), int(p["heart"]),
            pool(player, "life"), pool(player, "fire"), p["hand"].size()]
    return out
