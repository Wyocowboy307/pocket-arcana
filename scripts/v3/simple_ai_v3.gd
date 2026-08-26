class_name SimpleAIV3
extends RefCounted
## A rival that plays V3 competently enough to test the rules.
##
## Difficulty raises the quality of decisions, never the resources: the AI reads
## the same legal-action API the human UI does and never touches private state.

var engine: MatchV3
var rng := RandomNumberGenerator.new()

func setup(match_engine: MatchV3, seed_value := 991) -> void:
    engine = match_engine
    rng.seed = seed_value

## One complete turn, returned as a list of actions the view can replay in order.
func take_turn(player: int) -> Array:
    var taken: Array = []
    if engine.match_over or engine.current_player != player: return taken

    _play_landscape(player, taken)
    _fuse(player, taken)
    _play_bodies(player, taken)
    # Again: playing a creature is usually what *creates* the pair, and checking
    # only before the bodies go down meant every opportunity made this turn was
    # missed — 120 test matches resolved zero fusions.
    _fuse(player, taken)
    _use_power(player, taken)
    _cast_spells(player, taken)
    _attack(player, taken)
    engine.end_turn(player)
    taken.append({"kind": "end_turn"})
    return taken

## Land first, always: it is both the curve and the permission to play anything.
func _play_landscape(player: int, taken: Array) -> void:
    var own := String(engine.players[player]["element"])
    var best := ""
    for card_id in engine.players[player]["hand"]:
        if engine.db.card_type(String(card_id)) != "landscape": continue
        if engine.db.element_of(String(card_id)) == own:
            best = String(card_id)
            break
        if best == "": best = String(card_id)
    if best == "": return
    var targets := engine.legal_targets(player, best)
    if targets.is_empty(): return
    var spot: Dictionary = targets[0]
    if engine.play_card(player, best, int(spot["side"]), int(spot["lane"]))["ok"]:
        taken.append({"kind": "landscape", "card_id": best, "lane": int(spot["lane"])})

func _fuse(player: int, taken: Array) -> void:
    # Fusion is the strongest thing on the board; take every one that is legal.
    var guard := 0
    while guard < MatchV3.LANES:
        guard += 1
        var options := engine.available_fusions(player)
        if options.is_empty(): return
        var pick: Dictionary = options[0]
        var recipe: Dictionary = pick["recipe"]
        if not engine.fuse(player, String(recipe.get("id", "")), int(pick["a"]), int(pick["b"]))["ok"]:
            return
        taken.append({"kind": "fusion", "recipe": String(recipe.get("id", "")),
                      "a": int(pick["a"]), "b": int(pick["b"])})

## A creature that completes a fusion is worth more than a bigger body, because
## the fused result is worth more than both. Without this the AI always played
## its largest card and never assembled a recipe — 120 test matches resolved
## zero fusions, which is the signature mechanic never firing.
func _fusion_wanted(player: int) -> Dictionary:
    var wanted := {}
    for recipe in engine.db.fusions:
        var sources: Array = recipe.get("sources", [])
        if sources.size() < 2: continue
        if String(recipe.get("element", "")) != String(engine.players[player]["element"]): continue
        var on_board := {}
        for i in range(MatchV3.LANES):
            var unit = engine.lane(player, i)["creature"]
            if unit != null: on_board[String(unit["card_id"])] = true
        for source in sources:
            var sid := String(source)
            var partner_out := false
            for other in sources:
                if String(other) != sid and on_board.has(String(other)): partner_out = true
            if not on_board.has(sid) and partner_out:
                wanted[sid] = true
    return wanted

## Creatures before Supports, and the biggest body that still fits.
func _play_bodies(player: int, taken: Array) -> void:
    for wanted in ["creature", "support"]:
        var guard := 0
        while guard < MatchV3.LANES * 2:
            guard += 1
            var best := ""
            var best_score := -1
            for card_id in engine.players[player]["hand"]:
                var cid := String(card_id)
                if engine.db.card_type(cid) != wanted: continue
                if engine.card_block_reason(player, cid) != "": continue
                var card := engine.db.card(cid)
                var score := int(card.get("power", 0)) + int(card.get("health", 0)) \
                    + int(card.get("cost", 0)) * 2
                if wanted == "creature" and _fusion_wanted(player).has(cid):
                    score += 14
                if score > best_score:
                    best_score = score
                    best = cid
            if best == "": break
            var targets := engine.legal_targets(player, best)
            if targets.is_empty(): break
            var spot := _best_lane(player, best, targets)
            if not engine.play_card(player, best, int(spot["side"]), int(spot["lane"]))["ok"]: break
            taken.append({"kind": wanted, "card_id": best, "lane": int(spot["lane"])})

## Prefer a lane the rival has left open, so a new body threatens the Heart.
func _best_lane(player: int, card_id: String, targets: Array) -> Dictionary:
    var best: Dictionary = targets[0]
    var best_score := -99
    for spot in targets:
        var index := int(spot["lane"])
        var score := 0
        if engine.lane_is_open(player, index): score += 3
        if engine.lane(player, index)["support"] != null: score += 1
        if score > best_score:
            best_score = score
            best = spot
    return best

func _use_power(player: int, taken: Array) -> void:
    if engine.power_block_reason(player) != "": return
    if String(engine.power_target_kind(player)) == "enemy_lane":
        # Ember Rush: finish a creature if it can, otherwise go face.
        var foe := engine.opponent(player)
        for i in range(MatchV3.LANES):
            var unit = engine.lane(foe, i)["creature"]
            if unit != null and int(unit["health"]) <= 3:
                if engine.use_power(player, foe, i)["ok"]:
                    taken.append({"kind": "power", "side": foe, "lane": i})
                return
        if engine.turn >= 4 and engine.use_power(player)["ok"]:
            taken.append({"kind": "power", "side": -1, "lane": -1})
        return
    if engine.players[player]["hand"].size() <= 3 and engine.use_power(player)["ok"]:
        taken.append({"kind": "power", "side": -1, "lane": -1})

func _cast_spells(player: int, taken: Array) -> void:
    var guard := 0
    while guard < 6:
        guard += 1
        var chosen := ""
        for card_id in engine.players[player]["hand"]:
            var cid := String(card_id)
            if engine.db.card_type(cid) != "spell": continue
            if engine.card_block_reason(player, cid) != "": continue
            chosen = cid
            break
        if chosen == "": return
        var targets := engine.legal_targets(player, chosen)
        var side := player
        var index := 0
        if String(engine.db.card(chosen).get("target", "none")) == "creature":
            if targets.is_empty(): return
            var pick := _best_spell_target(player, chosen, targets)
            side = int(pick["side"]); index = int(pick["lane"])
        if not engine.play_card(player, chosen, side, index)["ok"]: return
        taken.append({"kind": "spell", "card_id": chosen, "side": side, "lane": index})

## Burn the enemy, heal your own — never the other way round.
func _best_spell_target(player: int, card_id: String, targets: Array) -> Dictionary:
    var effect: Dictionary = engine.db.card(card_id).get("effect", {})
    var harmful := String(effect.get("kind", "")) == "damage_creature"
    var want_side := engine.opponent(player) if harmful else player
    for spot in targets:
        if int(spot["side"]) == want_side: return spot
    return targets[0]

## Both creatures trade, so charging a bigger body just loses yours. Attack when
## the lane is open, when the blow kills, or when the answer will not kill us.
func _worth_attacking(player: int, index: int) -> bool:
    if engine.lane_is_open(player, index): return true
    # Two cautious boards can stare at each other forever once every trade looks
    # bad. Past a point, take the trade: a stalled match is worse than a bad one.
    if engine.turn >= 12: return true
    var foe := engine.opponent(player)
    var defender = engine.lane(foe, index)["creature"]
    var attacker = engine.lane(player, index)["creature"]
    if defender == null or attacker == null: return true
    var mine := engine.effective_power(player, index)
    var theirs := engine.effective_power(foe, index)
    if mine >= int(defender["health"]): return true          # it dies
    return theirs < int(attacker["health"])                  # we survive the answer

func _attack(player: int, taken: Array) -> void:
    # Open lanes first: damage that reaches the Heart is the only damage that wins.
    var order: Array = []
    for index in engine.legal_attacks(player):
        order.append({"lane": index, "open": engine.lane_is_open(player, index)})
    order.sort_custom(func(a, b): return bool(a["open"]) and not bool(b["open"]))
    for entry in order:
        var index2 := int(entry["lane"])
        if engine.attack_block_reason(player, index2) != "": continue
        if not _worth_attacking(player, index2): continue
        var result := engine.attack(player, index2)
        if bool(result.get("ok", false)):
            taken.append({"kind": "attack", "lane": index2,
                          "to_heart": bool(result.get("to_heart", false))})
        if engine.match_over: return
