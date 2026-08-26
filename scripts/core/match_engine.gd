class_name MatchEngine
extends Node
## Deterministic Pocket Arcana match simulation.
##
## The simulation owns every rule. UI and AI ask it what is legal and why
## something was refused; they never decide outcomes themselves.

signal state_changed
signal event_emitted(event: Dictionary)
signal chapter_resolved(summary: Dictionary)
signal match_finished(winner: int)

const HEART_START := 25
const HEART_CAP := 30
const WONDER_TO_WIN := 10
const SEALS_TO_WIN := 2
const MAX_CHAPTERS := 3
const OPENING_HAND := 8
const AETHER_CAP := 10
## The Sanctuary defends itself. Without this, one creature parked beside the
## rival Sanctuary farms the Heart every turn for free and Heart-rush dominates
## every other plan. Playtest knob — see docs/IMPLEMENTATION_NOTES.md.
const SANCTUARY_WARD := 2
## When your rival passes, you get this many final turns and then the Chapter
## scores. Without a bound, whoever passed first handed the other player free
## turns forever — and because Shaping costs no cards, those turns were pure
## permanent Realm Score. That made passing first strictly bad, so nobody ever
## passed holding cards and DESIGN_DECISIONS #4 could not happen.
## Playtest knob — see docs/IMPLEMENTATION_NOTES.md.
const FINAL_TURNS_AFTER_PASS := 1

var db: ContentDatabase
var board := BoardModel.new()
var combo := ComboResolver.new()
var effects := EffectResolver.new()
var ai := SimpleAI.new()
var players: Array = []
var current_player := 0
var chapter := 1
var starting_player := 0
var match_over := false
var winner := -1
var win_reason := ""
var rng := RandomNumberGenerator.new()
var selected_seed := 424242
var event_log: Array[String] = []
var last_chapter_summary: Dictionary = {}

# --- setup ------------------------------------------------------------------

func setup(content: ContentDatabase, deck0_id: String = "starter_life", deck1_id: String = "starter_fire", match_seed: int = -1) -> void:
    db = content
    combo.setup(db.recipes, db.terrain_attunement)
    if match_seed >= 0: selected_seed = match_seed
    rng.seed = selected_seed
    board.reset()
    match_over = false
    winner = -1
    win_reason = ""
    event_log.clear()
    last_chapter_summary = {}
    players = [_make_player(db.get_deck(deck0_id)), _make_player(db.get_deck(deck1_id))]
    _seed_sanctuary_terrain(0)
    _seed_sanctuary_terrain(1)
    for p in range(2):
        _shuffle_deck(players[p]["deck"])
        for _i in range(OPENING_HAND): draw_card(p)
    chapter = 1
    starting_player = 0
    _start_chapter(false)

func _make_player(deck_def: Dictionary) -> Dictionary:
    var deck: Array = []
    for entry in deck_def.get("cards", []):
        for _i in range(int(entry.get("count", 0))): deck.append(String(entry.get("card_id", "")))
    return {
        "heart": HEART_START, "seals": 0, "wonder": 0,
        "deck": deck, "hand": [], "discard": [], "graveyard": [],
        "commander_id": String(deck_def.get("commander_id", "")),
        "deck_name": String(deck_def.get("label", deck_def.get("name", "Deck"))),
        "passed": false, "commander_used": false, "turns_taken": 0,
        "max_aether": 3, "aether": 3, "bonus_aether": 0, "chapter_flags": {}, "solo_turns": 0,
    }

func _shuffle_deck(deck: Array) -> void:
    for i in range(deck.size() - 1, 0, -1):
        var j := rng.randi_range(0, i)
        var tmp = deck[i]; deck[i] = deck[j]; deck[j] = tmp

func sanctuary_pos(player: int) -> Vector2i:
    return Vector2i(3, 4) if player == 0 else Vector2i(3, 0)

func _seed_sanctuary_terrain(player: int) -> void:
    var cmd := db.get_commander(String(players[player]["commander_id"]))
    var el := String(cmd.get("element", "life"))
    var info: Dictionary = db.elements.get(el, {})
    board.shape(player, sanctuary_pos(player), String(info.get("terrain", "grove")))

func commander_element(player: int) -> String:
    return String(db.get_commander(String(players[player]["commander_id"])).get("element", "life"))

# --- chapter / turn flow ----------------------------------------------------

func _start_chapter(draw_between: bool = true) -> void:
    for p in range(2):
        var pl: Dictionary = players[p]
        pl["passed"] = false
        pl["commander_used"] = false
        pl["chapter_flags"] = {}
        pl["turns_taken"] = 0
        pl["solo_turns"] = 0
        pl["bonus_aether"] = 0
        pl["max_aether"] = min(AETHER_CAP, 3 + chapter)
        pl["aether"] = pl["max_aether"]
        if draw_between:
            for _i in range(3 if chapter == 2 else 2): draw_card(p)
    current_player = starting_player
    _begin_turn(current_player)
    _log("Chapter %d begins." % chapter)
    _emit({"type": "chapter_started", "chapter": chapter})
    state_changed.emit()

func _begin_turn(player: int) -> void:
    var p: Dictionary = players[player]
    p["max_aether"] = min(AETHER_CAP, 3 + chapter + int(p["turns_taken"]))
    p["aether"] = int(p["max_aether"]) + int(p["bonus_aether"])
    p["bonus_aether"] = 0
    # A Commander's Chapter opener belongs to the player's own first turn, so the
    # bonus is still there when they act rather than being refilled away.
    if not bool(p["chapter_flags"].get("turn_started", false)):
        p["chapter_flags"]["turn_started"] = true
        _dispatch_commander_trigger(player, "on_chapter_start", {})

func draw_card(player: int) -> void:
    var deck: Array = players[player]["deck"]
    if deck.is_empty(): return
    players[player]["hand"].append(deck.pop_back())

func grant_aether(player: int, amount: int) -> void:
    if current_player == player and not bool(players[player]["passed"]):
        players[player]["aether"] = int(players[player]["aether"]) + amount
    else:
        players[player]["bonus_aether"] = int(players[player]["bonus_aether"]) + amount

# --- legality queries (the UI and AI both go through these) -----------------

func has_attunement(player: int, required) -> bool:
    if required is not Array or required.is_empty(): return true
    var owned: Array[String] = []
    for row in board.tiles:
        for tile in row:
            if int(tile.get("owner", -1)) != player: continue
            var terrain := String(tile.get("terrain", "neutral"))
            for el in db.terrain_attunement.get(terrain, []):
                if not owned.has(String(el)): owned.append(String(el))
    for el in required:
        if not owned.has(String(el)): return false
    return true

func missing_attunement(player: int, required) -> Array[String]:
    var missing: Array[String] = []
    if required is not Array: return missing
    for el in required:
        if not has_attunement(player, [el]): missing.append(String(el))
    return missing

func terrain_for_element(element: String) -> String:
    return String(db.elements.get(element, {}).get("terrain", ""))

func can_shape_with_element(player: int, element: String, pos: Vector2i) -> bool:
    var terrain := terrain_for_element(element)
    if terrain == "": return false
    return board.can_shape(player, pos, terrain)

func legal_shape_tiles(player: int, element: String) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    for y in range(BoardModel.HEIGHT):
        for x in range(BoardModel.WIDTH):
            var pos := Vector2i(x, y)
            if can_shape_with_element(player, element, pos): out.append(pos)
    return out

func legal_targets_for_card(player: int, card_id: String) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    var card := db.get_card(card_id)
    if card.is_empty(): return out
    var typ := String(card.get("type", ""))
    for y in range(BoardModel.HEIGHT):
        for x in range(BoardModel.WIDTH):
            var pos := Vector2i(x, y); var tile := board.get_tile(pos)
            if typ == "creature" and int(tile.get("owner", -1)) == player and tile.get("creature") == null:
                out.append(pos)
            elif typ == "landmark" and int(tile.get("owner", -1)) == player and tile.get("landmark") == null:
                out.append(pos)
            elif typ in ["spell", "terrain", "relic"]:
                out.append(pos)
    return out

func can_afford(player: int, card_id: String) -> bool:
    return int(db.get_card(card_id).get("cost", 99)) <= int(players[player]["aether"])

## Why this card cannot be played right now, in plain English. "" means it can.
func card_block_reason(player: int, card_id: String) -> String:
    var card := db.get_card(card_id)
    if card.is_empty(): return "Card data is missing."
    if not players[player]["hand"].has(card_id): return "That card is not in your hand."
    if not _can_act(player): return "It is not your turn."
    if int(card.get("cost", 0)) > int(players[player]["aether"]): return "Not enough Aether."
    var missing := missing_attunement(player, card.get("attunement", []))
    if not missing.is_empty():
        var names: Array[String] = []
        for el in missing: names.append(String(db.elements.get(el, {}).get("name", el)))
        return "Shape %s first." % " and ".join(names)
    if legal_targets_for_card(player, card_id).is_empty(): return "No legal tile for that card."
    return ""

func units_of(player: int) -> Array:
    var out: Array = []
    for y in range(BoardModel.HEIGHT):
        for x in range(BoardModel.WIDTH):
            var tile := board.get_tile(Vector2i(x, y))
            var unit = tile.get("creature")
            if unit != null and int(unit.get("owner", -1)) == player:
                out.append({"pos": Vector2i(x, y), "unit": unit})
    return out

func legal_moves_for_unit(player: int, from: Vector2i) -> Dictionary:
    var moves: Array[Vector2i] = []
    var attacks: Array[Vector2i] = []
    var src := board.get_tile(from)
    var unit = src.get("creature")
    if unit == null or int(unit.get("owner", -1)) != player:
        return {"moves": moves, "attacks": attacks, "heart": false}
    for n in board.neighbors(from):
        var tile := board.get_tile(n)
        var other = tile.get("creature")
        if int(tile.get("sanctuary_owner", -1)) >= 0 and int(tile.get("sanctuary_owner", -1)) != player:
            continue  # the rival Sanctuary is struck from outside, never occupied
        if other == null: moves.append(n)
        elif int(other.get("owner", -1)) != player: attacks.append(n)
    return {"moves": moves, "attacks": attacks, "heart": can_attack_heart(player, from)}

## Cards whose effect needs a second click (currently push/movement magic).
func card_needs_second_target(card_id: String) -> bool:
    for effect in db.get_card(card_id).get("effects", []):
        if String(effect.get("kind", "")) == "move_unit": return true
    return false

## Where a creature standing on `from` can legally be pushed.
func legal_push_targets(from: Vector2i) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    if board.get_tile(from).get("creature") == null: return out
    for n in board.neighbors(from):
        var tile := board.get_tile(n)
        if tile.get("creature") != null: continue
        if int(tile.get("sanctuary_owner", -1)) >= 0: continue
        out.append(n)
    return out

func can_attack_heart(player: int, from: Vector2i) -> bool:
    var unit = board.get_tile(from).get("creature")
    if unit == null or int(unit.get("owner", -1)) != player: return false
    return board.neighbors(from).has(sanctuary_pos(1 - player))

# --- pass preview -----------------------------------------------------------

func pass_preview(player: int) -> Dictionary:
    var mine := board.realm_score_breakdown(player)
    var theirs := board.realm_score_breakdown(1 - player)
    var my_total := int(mine["total"]); var their_total := int(theirs["total"])
    var rival_passed := bool(players[1 - player]["passed"])
    var outcome := ""
    if my_total > their_total:
        outcome = "You win this Chapter."
    elif their_total > my_total:
        outcome = "You lose this Chapter."
    else:
        outcome = "Tied — no Seal for anyone."
    var turns_word := "turn" if FINAL_TURNS_AFTER_PASS == 1 else "turns"
    if not rival_passed:
        outcome += " Rival gets %d last %s." % [FINAL_TURNS_AFTER_PASS, turns_word]
    return {
        "my_score": my_total, "rival_score": their_total,
        "my_breakdown": mine, "rival_breakdown": theirs,
        "rival_passed": rival_passed, "outcome": outcome,
        "cards_kept": players[player]["hand"].size(),
    }

# --- actions ----------------------------------------------------------------

## Single entry point for an action dictionary, as produced by SimpleAI or the UI.
func perform(player: int, action: Dictionary) -> Dictionary:
    match String(action.get("kind", "pass")):
        "play_card": return play_card(player, String(action.get("card_id", "")), action.get("pos", Vector2i.ZERO), action.get("secondary", Vector2i(-1, -1)))
        "shape": return shape(player, String(action.get("element", "")), action.get("pos", Vector2i.ZERO))
        "move": return move_or_attack(player, action.get("from", Vector2i.ZERO), action.get("to", Vector2i.ZERO))
        "attack_heart": return attack_heart(player, action.get("from", Vector2i.ZERO))
        "command": return use_commander(player, action.get("pos", Vector2i.ZERO))
        "pass": return pass_chapter(player)
    return _fail("Unknown action.")

func play_card(player: int, card_id: String, pos: Vector2i, secondary: Vector2i = Vector2i(-1, -1)) -> Dictionary:
    if not _can_act(player): return _fail("It is not your turn.")
    var p: Dictionary = players[player]
    if not p["hand"].has(card_id): return _fail("That card is not in your hand.")
    var card := db.get_card(card_id)
    if card.is_empty(): return _fail("Card data is missing.")
    if int(card.get("cost", 0)) > int(p["aether"]): return _fail("Not enough Aether.")
    var missing := missing_attunement(player, card.get("attunement", []))
    if not missing.is_empty():
        var names: Array[String] = []
        for el in missing: names.append(String(db.elements.get(el, {}).get("name", el)))
        return _fail("Shape %s first." % " and ".join(names))
    if not legal_targets_for_card(player, card_id).has(pos): return _fail("That card cannot go there.")
    if card_needs_second_target(card_id):
        if legal_push_targets(pos).is_empty():
            return _fail("There is nothing there to move.")
        if not legal_push_targets(pos).has(secondary):
            return {"ok": false, "needs_second_target": true, "reason": "Now choose where to move it."}
    p["aether"] = int(p["aether"]) - int(card.get("cost", 0))
    p["hand"].erase(card_id)
    var tile := board.get_tile(pos)
    var typ := String(card.get("type", ""))
    if typ == "creature":
        tile["creature"] = make_unit_from_card(card, player)
        tile["owner"] = player
        _emit({"type": "creature_summoned", "player": player, "card_id": card_id, "pos": pos, "unit": tile["creature"]})
    elif typ == "landmark":
        tile["landmark"] = {"card_id": card_id, "name": card.get("name", card_id), "owner": player, "presence": int(card.get("presence", 1))}
        tile["owner"] = player
        _emit({"type": "landmark_built", "player": player, "card_id": card_id, "pos": pos})
    else:
        _emit({"type": "spell_cast", "player": player, "card_id": card_id, "pos": pos})
    for effect in card.get("effects", []): _apply_and_followups(effect, player, pos, secondary)
    if typ in ["spell", "terrain", "relic"]: p["discard"].append(card_id)
    _dispatch_commander_trigger(player, "on_first_card_played", {"card": card})
    _log("P%d played %s." % [player + 1, String(card.get("name", card_id))])
    _check_victory_or_finish_action(player)
    return {"ok": true}

func shape(player: int, element: String, pos: Vector2i) -> Dictionary:
    if not _can_act(player): return _fail("It is not your turn.")
    var info: Dictionary = db.elements.get(element, {})
    if info.is_empty(): return _fail("Unknown element.")
    var terrain := String(info.get("terrain", ""))
    if not board.in_bounds(pos): return _fail("That tile is off the board.")
    var tile := board.get_tile(pos)
    if int(tile.get("owner", -1)) not in [-1, player]: return _fail("That tile belongs to the rival realm.")
    if int(tile.get("owner", -1)) == player and String(tile.get("terrain", "")) == terrain:
        return _fail("That tile is already %s." % String(info.get("name", element)))
    if not board.shape(player, pos, terrain): return _fail("Shape next to your own realm.")
    _emit({"type": "shape", "player": player, "element": element, "terrain": terrain, "pos": pos})
    _log("P%d shaped %s." % [player + 1, String(info.get("name", element))])
    _finish_action(player)
    return {"ok": true}

func use_commander(player: int, pos: Vector2i) -> Dictionary:
    if not _can_act(player): return _fail("It is not your turn.")
    if bool(players[player]["commander_used"]): return _fail("Command already used this Chapter.")
    var cmd := db.get_commander(String(players[player]["commander_id"]))
    if cmd.is_empty(): return _fail("Commander data is missing.")
    players[player]["commander_used"] = true
    _emit({"type": "commander", "player": player, "commander_id": cmd.get("id", ""), "name": cmd.get("name", ""), "pos": pos})
    for effect in cmd.get("command", {}).get("effects", []): _apply_and_followups(effect, player, pos)
    _log("P%d used %s's Command." % [player + 1, String(cmd.get("name", "Commander"))])
    _check_victory_or_finish_action(player)
    return {"ok": true}

func move_or_attack(player: int, from: Vector2i, to: Vector2i) -> Dictionary:
    if not _can_act(player): return _fail("It is not your turn.")
    if not board.neighbors(from).has(to): return _fail("Move only one tile at a time.")
    var src := board.get_tile(from); var dst := board.get_tile(to)
    var unit = src.get("creature")
    if unit == null or int(unit.get("owner", -1)) != player: return _fail("Pick one of your creatures.")
    var sanc := int(dst.get("sanctuary_owner", -1))
    if sanc >= 0 and sanc != player:
        return _fail("Creatures cannot enter the rival Sanctuary — strike the Heart from beside it.")
    var enemy = dst.get("creature")
    if enemy == null:
        src["creature"] = null
        dst["creature"] = unit
        _emit({"type": "unit_moved", "player": player, "from": from, "to": to, "unit": unit})
        _dispatch_commander_trigger(player, "on_unit_move", {"unit": unit})
    elif int(enemy.get("owner", -1)) != player:
        var my_power := int(unit.get("power", 0)); var their_power := int(enemy.get("power", 0))
        unit["health"] = int(unit.get("health", 0)) - their_power
        enemy["health"] = int(enemy.get("health", 0)) - my_power
        _emit({"type": "combat", "player": player, "from": from, "to": to, "my_damage": their_power, "enemy_damage": my_power})
        _clean_dead_on_tile(from); _clean_dead_on_tile(to)
    else:
        return _fail("That tile already has your creature.")
    _check_victory_or_finish_action(player)
    return {"ok": true}

## A creature standing beside the rival Sanctuary spends its turn striking the Heart.
func attack_heart(player: int, from: Vector2i) -> Dictionary:
    if not _can_act(player): return _fail("It is not your turn.")
    var unit = board.get_tile(from).get("creature")
    if unit == null or int(unit.get("owner", -1)) != player: return _fail("Pick one of your creatures.")
    if not can_attack_heart(player, from):
        return _fail("That creature is not beside the rival Sanctuary.")
    var amount := int(unit.get("power", 0))
    if amount <= 0: return _fail("That creature has no Power to strike with.")
    var victim := 1 - player
    players[victim]["heart"] = max(0, int(players[victim]["heart"]) - amount)
    _emit({"type": "heart_attack", "player": player, "amount": amount, "from": from, "unit": unit, "ward": SANCTUARY_WARD})
    _log("P%d struck the rival Heart for %d." % [player + 1, amount])
    # The Sanctuary strikes back at whatever is hitting it.
    if SANCTUARY_WARD > 0 and int(players[victim]["heart"]) > 0:
        unit["health"] = int(unit.get("health", 0)) - SANCTUARY_WARD
        _emit({"type": "ward_retaliation", "player": victim, "amount": SANCTUARY_WARD, "pos": from, "unit": unit})
        _clean_dead_on_tile(from)
    _check_victory_or_finish_action(player)
    return {"ok": true}

func pass_chapter(player: int) -> Dictionary:
    if not _can_act(player): return _fail("It is not your turn.")
    players[player]["passed"] = true
    _emit({"type": "passed", "player": player})
    _log("P%d passed." % (player + 1))
    if bool(players[1 - player]["passed"]):
        _resolve_chapter()
    else:
        current_player = 1 - player
        _begin_turn(current_player)
        state_changed.emit()
    return {"ok": true}

# --- units ------------------------------------------------------------------

func make_unit_from_card(card: Dictionary, owner: int) -> Dictionary:
    var unit := {
        "uid": board.next_unit_id, "card_id": card.get("id", ""), "name": card.get("name", ""),
        "owner": owner, "power": int(card.get("power", 0)),
        "health": int(card.get("health", 1)), "max_health": int(card.get("health", 1)),
    }
    board.next_unit_id += 1
    return unit

func make_unit_from_token(token: Dictionary, owner: int) -> Dictionary:
    var out := {
        "uid": board.next_unit_id, "card_id": "token:" + String(token.get("id", "")),
        "name": token.get("name", "Token"), "owner": owner, "power": int(token.get("power", 1)),
        "health": int(token.get("health", 1)), "max_health": int(token.get("health", 1)),
    }
    board.next_unit_id += 1
    return out

func _clean_dead_on_tile(pos: Vector2i) -> void:
    var tile := board.get_tile(pos)
    var unit = tile.get("creature")
    if unit != null and int(unit.get("health", 0)) <= 0:
        var owner := int(unit.get("owner", -1))
        players[owner]["graveyard"].append(String(unit.get("card_id", "")))
        tile["creature"] = null
        _emit({"type": "unit_died", "unit": unit, "pos": pos})
        _dispatch_commander_trigger(owner, "on_unit_death", {"unit": unit})

# --- effects and triggers ---------------------------------------------------

func _apply_and_followups(effect: Dictionary, actor: int, pos: Vector2i, secondary: Vector2i = Vector2i(-1, -1)) -> void:
    for event in effects.apply(effect, self, actor, pos, secondary):
        _emit(event)
        if String(event.get("type", "")) == "state_added":
            _dispatch_commander_trigger(actor, "on_first_state_added", event)
        if String(event.get("type", "")) == "unit_died":
            _dispatch_commander_trigger(int(event.get("unit", {}).get("owner", actor)), "on_unit_death", event)
    for event in combo.resolve_tile(board, pos):
        event["player"] = actor
        if int(event.get("wonder", 0)) > 0: players[actor]["wonder"] += int(event["wonder"])
        _log("Discovery: %s." % String(event.get("name", "new terrain")))
        _emit(event)

func _dispatch_commander_trigger(player: int, trigger: String, context: Dictionary) -> void:
    var cmd := db.get_commander(String(players[player]["commander_id"]))
    var passive: Dictionary = cmd.get("passive", {})
    if String(passive.get("trigger", "")) != trigger: return
    var flag := "passive:" + trigger
    if bool(passive.get("once_per_chapter", false)) and bool(players[player]["chapter_flags"].get(flag, false)): return
    for cond in passive.get("conditions", []):
        if String(cond.get("kind", "")) == "card_element":
            var card: Dictionary = context.get("card", {})
            if not card.get("elements", []).has(cond.get("element")):
                return
        elif String(cond.get("kind", "")) == "state_is" and String(context.get("state", "")) != String(cond.get("state", "")):
            return
    players[player]["chapter_flags"][flag] = true
    for effect in passive.get("effects", []):
        _apply_and_followups(effect, player, sanctuary_pos(player))
    _emit({"type": "commander_passive", "player": player, "commander_id": cmd.get("id", ""), "name": cmd.get("name", "")})

# --- flow helpers -----------------------------------------------------------

func _can_act(player: int) -> bool:
    return not match_over and current_player == player and not bool(players[player]["passed"])

func _finish_action(player: int) -> void:
    players[player]["turns_taken"] = int(players[player]["turns_taken"]) + 1
    var other := 1 - player
    if bool(players[other]["passed"]):
        # The rival is out of this Chapter, so this is a bounded last word.
        players[player]["solo_turns"] = int(players[player]["solo_turns"]) + 1
        if int(players[player]["solo_turns"]) >= FINAL_TURNS_AFTER_PASS:
            players[player]["passed"] = true
            _log("P%d takes the last turn of the Chapter." % (player + 1))
            state_changed.emit()
            _resolve_chapter()
            return
        current_player = player
    else:
        current_player = other
    _begin_turn(current_player)
    state_changed.emit()

func _check_victory_or_finish_action(player: int) -> void:
    if _check_victory(player): return
    _finish_action(player)

func _check_victory(actor: int) -> bool:
    for p in range(2):
        if int(players[p]["heart"]) <= 0:
            _finish_match(1 - p, "Heart broken")
            return true
    for p in range(2):
        if int(players[p]["wonder"]) >= WONDER_TO_WIN:
            _finish_match(p, "Wonder completed")
            return true
    return false

func _resolve_chapter() -> void:
    var a := board.realm_score(0); var b := board.realm_score(1)
    var chapter_winner := -1
    if a > b: chapter_winner = 0
    elif b > a: chapter_winner = 1
    _log("Chapter %d score: %d–%d." % [chapter, a, b])
    if chapter_winner >= 0:
        players[chapter_winner]["seals"] += 1
        _log("P%d wins the Chapter." % (chapter_winner + 1))
    else:
        _log("The Chapter is a tie. No Seal awarded.")
    last_chapter_summary = {
        "chapter": chapter, "scores": [a, b], "winner": chapter_winner,
        "seals": [int(players[0]["seals"]), int(players[1]["seals"])],
        "hearts": [int(players[0]["heart"]), int(players[1]["heart"])],
        "breakdown": [board.realm_score_breakdown(0), board.realm_score_breakdown(1)],
        "hand_sizes": [players[0]["hand"].size(), players[1]["hand"].size()],
    }
    chapter_resolved.emit(last_chapter_summary)
    _emit({"type": "chapter_resolved", "summary": last_chapter_summary})
    for p in range(2):
        if int(players[p]["seals"]) >= SEALS_TO_WIN:
            _finish_match(p, "Two Chapter Seals")
            return
    chapter += 1
    if chapter > MAX_CHAPTERS:
        var final_winner := 0 if int(players[0]["heart"]) + a >= int(players[1]["heart"]) + b else 1
        _finish_match(final_winner, "Final tiebreak")
        return
    board.clear_creatures_for_new_chapter()
    starting_player = 1 - starting_player
    _start_chapter(true)

func _finish_match(who: int, reason: String) -> void:
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
