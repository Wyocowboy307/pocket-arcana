class_name SimpleAI
extends RefCounted
## Heuristic opponent for Pocket Arcana.
##
## Design rule (DESIGN_DECISIONS): a harder opponent makes *better decisions*.
## It never gets extra Aether, cards, stats or hidden information — every option
## it considers comes from the same public legality API the UI uses.

enum Difficulty { GENTLE, STEADY, SHARP }

var difficulty: int = Difficulty.STEADY

## How much each element wants to race the Heart versus build a realm.
const AGGRESSION := {
    "fire": 1.0, "lightning": 0.8, "death": 0.7, "wind": 0.6,
    "water": 0.5, "frost": 0.45, "life": 0.4, "earth": 0.35,
}
const TURN_SAFETY_VALVE := 80

func choose_action(engine, player: int) -> Dictionary:
    var p: Dictionary = engine.players[player]
    if int(p.get("turns_taken", 0)) > TURN_SAFETY_VALVE:
        return {"kind": "pass"}

    var aggression: float = float(AGGRESSION.get(engine.commander_element(player), 0.5))
    var best: Dictionary = {"kind": "pass"}
    var best_score := _pass_value(engine, player)

    for option in _enumerate(engine, player, aggression):
        # Strict > keeps the first of any tie, so the same seed always replays.
        if float(option["score"]) > best_score:
            best_score = float(option["score"])
            best = option["action"]
    if difficulty == Difficulty.GENTLE and best.get("kind", "") == "attack_heart" and int(p.get("turns_taken", 0)) < 3:
        return {"kind": "pass"} if best_score < 6.0 else best
    return best

# --- option enumeration -----------------------------------------------------

func _enumerate(engine, player: int, aggression: float) -> Array:
    var options: Array = []
    var p: Dictionary = engine.players[player]
    var enemy_sanctuary: Vector2i = engine.sanctuary_pos(1 - player)

    # 1. Strike the Heart with anything already standing beside the Sanctuary.
    for entry in engine.units_of(player):
        var pos: Vector2i = entry["pos"]
        if engine.can_attack_heart(player, pos):
            var unit: Dictionary = entry["unit"]
            var power := int(unit.get("power", 0))
            if power > 0:
                var lethal: bool = power >= int(engine.players[1 - player]["heart"])
                var score := power * (1.6 + aggression * 1.4)
                if lethal:
                    score += 1000.0
                elif int(unit.get("health", 0)) <= MatchEngine.SANCTUARY_WARD:
                    # The Ward will kill it — only worth it if the damage beats the body.
                    score -= power * 1.5 + int(unit.get("health", 0)) * 0.7
                options.append({"score": score, "action": {"kind": "attack_heart", "from": pos}})

    # 2. Play a card.
    var seen_cards: Array[String] = []
    for card_id in p["hand"]:
        var cid := String(card_id)
        if seen_cards.has(cid): continue
        seen_cards.append(cid)
        if engine.card_block_reason(player, cid) != "": continue
        var card: Dictionary = engine.db.get_card(cid)
        var two_step: bool = engine.card_needs_second_target(cid)
        for pos in engine.legal_targets_for_card(player, cid):
            if two_step:
                var enemy_sanc: Vector2i = engine.sanctuary_pos(1 - player)
                for dest in engine.legal_push_targets(pos):
                    var subject = engine.board.get_tile(pos).get("creature")
                    if subject == null or int(subject.get("owner", -1)) == player: continue
                    # Shoving a threat away from our Sanctuary is the point of the card.
                    var gain: float = float(_distance(dest, engine.sanctuary_pos(player)) - _distance(pos, engine.sanctuary_pos(player)))
                    options.append({
                        "score": 1.0 + gain * 1.6 + (2.5 if engine.can_attack_heart(1 - player, pos) else 0.0),
                        "action": {"kind": "play_card", "card_id": cid, "pos": pos, "secondary": dest},
                    })
                continue
            options.append({
                "score": _card_value(engine, player, card, pos, aggression),
                "action": {"kind": "play_card", "card_id": cid, "pos": pos},
            })

    # 3. Shape terrain.
    for element in _shape_elements(engine, player):
        for pos in engine.legal_shape_tiles(player, element):
            options.append({
                "score": _shape_value(engine, player, element, pos, aggression),
                "action": {"kind": "shape", "element": element, "pos": pos},
            })

    # 4. Move or fight with a creature.
    for entry in engine.units_of(player):
        var from: Vector2i = entry["pos"]
        var unit: Dictionary = entry["unit"]
        var legal: Dictionary = engine.legal_moves_for_unit(player, from)
        var here: int = _distance(from, enemy_sanctuary)
        for to in legal["moves"]:
            var closer: int = here - _distance(to, enemy_sanctuary)
            var score := closer * (0.9 + aggression * 1.8)
            if closer <= 0: score -= 1.2  # never drift aimlessly
            if engine.can_attack_heart(player, to): score += 2.0 + aggression * 2.0
            options.append({"score": score, "action": {"kind": "move", "from": from, "to": to}})
        for to in legal["attacks"]:
            var target = engine.board.get_tile(to).get("creature")
            if target == null: continue
            var value := _trade_value(unit, target)
            # Anything standing beside our own Sanctuary is bleeding us every turn.
            if engine.can_attack_heart(1 - player, to):
                value += int(target.get("power", 0)) * (2.2 + (1.0 - aggression))
                if int(unit.get("power", 0)) >= int(target.get("health", 0)):
                    value += 3.0  # and we can actually remove it
            options.append({
                "score": value,
                "action": {"kind": "move", "from": from, "to": to},
            })

    # 5. Use the Command.
    if not bool(p["commander_used"]):
        var command: Dictionary = engine.db.get_commander(String(p["commander_id"])).get("command", {})
        var effects: Array = command.get("effects", [])
        if not effects.is_empty():
            for y in range(BoardModel.HEIGHT):
                for x in range(BoardModel.WIDTH):
                    var pos := Vector2i(x, y)
                    options.append({
                        "score": _effects_value(engine, player, effects, pos, aggression) * 0.9,
                        "action": {"kind": "command", "pos": pos},
                    })
    return options

## Shape the Commander's element, plus anything a card in hand is waiting on.
func _shape_elements(engine, player: int) -> Array[String]:
    var out: Array[String] = [engine.commander_element(player)]
    for card_id in engine.players[player]["hand"]:
        var card: Dictionary = engine.db.get_card(String(card_id))
        for el in engine.missing_attunement(player, card.get("attunement", [])):
            if not out.has(el): out.append(el)
    return out

# --- valuation --------------------------------------------------------------

func _card_value(engine, player: int, card: Dictionary, pos: Vector2i, aggression: float) -> float:
    var typ := String(card.get("type", ""))
    var score := 0.0
    var enemy_sanctuary: Vector2i = engine.sanctuary_pos(1 - player)
    if typ == "creature":
        # Power counts twice: it is Realm Score and it is Heart pressure.
        score += int(card.get("power", 0)) * 1.5 + int(card.get("health", 0)) * 0.7
        var dist: int = _distance(pos, enemy_sanctuary)
        score += max(0, 8 - dist) * aggression * 0.55
        # A body next to our own Sanctuary can trade with whatever is chipping us.
        if _distance(pos, engine.sanctuary_pos(player)) <= 1 and _heart_threat(engine, player) > 0:
            score += _heart_threat(engine, player) * 1.1
    elif typ == "landmark":
        score += int(card.get("presence", 1)) * 2.2
    score += _effects_value(engine, player, card.get("effects", []), pos, aggression)
    # Spend big cards when the Aether is there, but do not hoard cheap ones.
    score -= int(card.get("cost", 0)) * 0.25
    return score

func _effects_value(engine, player: int, effects: Array, pos: Vector2i, aggression: float) -> float:
    var total := 0.0
    var tile: Dictionary = engine.board.get_tile(pos)
    for effect in effects:
        var kind := String(effect.get("kind", ""))
        var amount := float(effect.get("amount", 0))
        match kind:
            "damage_heart":
                var enemy_heart: int = int(engine.players[1 - player]["heart"])
                total += amount * (1.6 + aggression * 1.6)
                if amount >= enemy_heart: total += 1000.0
            "heal_heart":
                var missing: int = MatchEngine.HEART_CAP - int(engine.players[player]["heart"])
                total += min(amount, float(missing)) * 0.9
            "gain_wonder":
                var wonder: int = int(engine.players[player]["wonder"])
                total += amount * 2.4
                if wonder + amount >= MatchEngine.WONDER_TO_WIN: total += 1000.0
            "draw": total += amount * 1.7
            "gain_aether": total += amount * 0.8
            "damage_unit":
                var target = tile.get("creature")
                if target != null and int(target.get("owner", -1)) != player:
                    total += min(amount, float(target.get("health", 0))) * 1.3
                    if amount >= int(target.get("health", 0)):
                        total += int(target.get("power", 0)) * 1.1
                        if engine.can_attack_heart(1 - player, pos):
                            total += int(target.get("power", 0)) * 2.2  # kills a Heart threat
                else:
                    total -= 0.6  # aimed at nothing
            "add_state":
                total += 0.7
                if _completes_recipe(engine, tile, String(effect.get("state", ""))): total += 3.2
            "buff_unit":
                var friend = tile.get("creature")
                if friend != null and int(friend.get("owner", -1)) == player:
                    total += float(effect.get("power", 0)) * 1.4 + float(effect.get("health", 0)) * 0.7
            "summon_token":
                var token: Dictionary = engine.db.get_token(String(effect.get("token_id", "")))
                if tile.get("creature") == null:
                    total += int(token.get("power", 1)) * 1.4 + int(token.get("health", 1)) * 0.7
            "transform_terrain": total += 1.0
            "resurrect_last":
                if not engine.players[player]["graveyard"].is_empty(): total += 1.6
    return total

func _completes_recipe(engine, tile: Dictionary, new_state: String) -> bool:
    if new_state == "": return false
    var states: Array = tile.get("states", [])
    if states.has(new_state): return false
    for recipe in engine.db.recipes:
        var need: Array = recipe.get("states", [])
        if need.size() != 2: continue
        if need.has(new_state) and (states.has(need[0]) or states.has(need[1])):
            return true
    return false

func _shape_value(engine, player: int, element: String, pos: Vector2i, aggression: float) -> float:
    # Every shaped tile is +1 Realm Score, so shaping is never worthless.
    var score := 1.15
    var tile: Dictionary = engine.board.get_tile(pos)
    if int(tile.get("owner", -1)) == -1: score += 0.5  # claiming new ground
    if element != engine.commander_element(player): score += 2.5  # unlocks a stuck card
    # Push the realm toward the rival so creatures have somewhere to land.
    var dist: int = _distance(pos, engine.sanctuary_pos(1 - player))
    score += max(0, 8 - dist) * aggression * 0.22
    return score

func _trade_value(mine: Dictionary, theirs: Dictionary) -> float:
    var my_power := int(mine.get("power", 0)); var my_hp := int(mine.get("health", 0))
    var their_power := int(theirs.get("power", 0)); var their_hp := int(theirs.get("health", 0))
    var gain := (their_power * 1.5 + their_hp * 0.7) if my_power >= their_hp else my_power * 0.4
    var loss := (my_power * 1.5 + my_hp * 0.7) if their_power >= my_hp else their_power * 0.4
    return gain - loss

## Passing keeps cards for the next Chapter, so it has to beat weak actions.
func _pass_value(engine, player: int) -> float:
    var preview: Dictionary = engine.pass_preview(player)
    var margin: int = int(preview["my_score"]) - int(preview["rival_score"])
    var value := 0.5
    if difficulty == Difficulty.GENTLE: return 0.35
    var last_chapter: bool = engine.chapter >= MatchEngine.MAX_CHAPTERS
    var rival_passed: bool = bool(preview["rival_passed"])
    # Hand size is public information — the scoreboard shows it to the player too.
    var rival_cards: int = engine.players[1 - player]["hand"].size()
    # Roughly what the rival could still add, including their one last turn.
    var rival_threat: float = 0.0 if rival_passed else float(rival_cards) * 1.6 + 4.0

    if margin > 0 and rival_passed:
        # The rival is out and we are ahead: anything more is spent for nothing.
        value += 60.0
    elif not last_chapter and float(margin) > rival_threat:
        # The Chapter is already safe. Winning by one with cards in hand beats
        # winning by fifteen with none (DESIGN_DECISIONS #4) — those cards are
        # next Chapter's draws.
        value += 60.0
    elif margin > 0 and not last_chapter:
        value += 1.4 + min(margin, 8) * 0.5
    if difficulty == Difficulty.SHARP:
        value += 0.4
    return value

## Total Power the rival currently has parked beside our Sanctuary.
func _heart_threat(engine, player: int) -> int:
    var threat := 0
    for entry in engine.units_of(1 - player):
        if engine.can_attack_heart(1 - player, entry["pos"]):
            threat += int(entry["unit"].get("power", 0))
    return threat

func _distance(a: Vector2i, b: Vector2i) -> int:
    return abs(a.x - b.x) + abs(a.y - b.y)
