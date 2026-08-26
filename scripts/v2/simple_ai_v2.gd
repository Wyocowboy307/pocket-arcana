class_name SimpleAIV2
extends RefCounted
## Opponent for the V2 lane prototype.
##
## Same rule as V1: a better opponent makes better decisions, never gets hidden
## resources. It sees only what the player could see.

func take_turn(engine: MatchV2, player: int) -> Array:
    ## Returns the actions it performed, so a test can assert it actually played.
    var done: Array = []
    var p: Dictionary = engine.players[player]

    # 1. Land first while lanes are empty — more land is more magic.
    if not bool(p["played_card"]) and int(p["realm_stack"]) > 0 and engine.built_lands(player) < 3:
        for i in range(MatchV2.LANES):
            if String(engine.lane(player, i)["land"]) == "":
                if bool(engine.play_realm(player, i).get("ok", false)):
                    done.append("realm")
                break

    # 2. Fuse when it is clearly an upgrade.
    if not bool(p["played_card"]):
        for option in engine.available_fusions(player):
            if not bool(option["affordable"]): continue
            var r: Dictionary = option["recipe"]
            if bool(engine.fuse(player, String(r.get("id", "")), int(option["a"]), int(option["b"])).get("ok", false)):
                done.append("fusion")
                break

    # 3. Play the strongest affordable card.
    if not bool(p["played_card"]):
        var best := ""
        var best_score := -1.0
        var best_target: Dictionary = {}
        for card_id in p["hand"]:
            var cid := String(card_id)
            var targets: Array = engine.legal_targets(player, cid)
            if targets.is_empty(): continue
            var score := _card_score(engine, player, cid)
            if score > best_score:
                best_score = score
                best = cid
                best_target = _pick_target(engine, player, cid, targets)
        if best != "":
            if bool(engine.play_card(player, best, int(best_target.get("side", player)),
                                     int(best_target.get("lane", -1))).get("ok", false)):
                done.append("card")

    # 4. Attack: clear a blocker we beat, otherwise hit the Heart.
    if not bool(p["attacked"]):
        var lanes: Array = engine.legal_attacks(player)
        var chosen := -1
        var chosen_score := -1.0
        for i in lanes:
            var mine: Dictionary = engine.lane(player, i)["creature"]
            var foe = engine.lane(engine.opponent(player), i)["creature"]
            var score := 0.0
            if foe == null:
                score = 4.0 + float(mine["power"])          # free Heart damage
            else:
                var kills: bool = int(mine["power"]) >= int(foe["health"])
                var dies: bool = int(foe["power"]) >= int(mine["health"])
                score = (3.0 if kills else 0.5) - (2.5 if dies else 0.0)
            if score > chosen_score:
                chosen_score = score
                chosen = i
        if chosen >= 0 and chosen_score > 0.0:
            if bool(engine.attack(player, chosen).get("ok", false)): done.append("attack")

    # 5. Commander, when it has nothing better to do with the card play.
    if not bool(p["played_card"]) and engine.commander_block_reason(player) == "":
        if bool(engine.use_commander(player, engine.opponent(player), -1).get("ok", false)):
            done.append("commander")

    engine.end_turn(player)
    return done

func _card_score(engine: MatchV2, player: int, card_id: String) -> float:
    var card: Dictionary = engine.db.get_card(card_id)
    match engine.card_role(card_id):
        "Creature":
            return float(card.get("power", 0)) * 1.6 + float(card.get("health", 0)) * 0.8
        "Place":
            return 2.0 + float(card.get("presence", 1))
    var score := 1.0
    for e in card.get("effects", []):
        match String(e.get("kind", "")):
            "damage_heart": score += float(e.get("amount", 0)) * 1.8
            "damage_unit": score += float(e.get("amount", 0)) * 1.4
            "heal_heart": score += float(e.get("amount", 0)) * 0.7
            "draw": score += float(e.get("amount", 0)) * 1.5
            "buff_unit": score += float(e.get("power", 0)) * 1.2
    return score

func _pick_target(engine: MatchV2, player: int, card_id: String, targets: Array) -> Dictionary:
    var role := engine.card_role(card_id)
    if role == "Creature" or role == "Place":
        # Prefer a lane the rival is contesting, so the body has a job.
        for t in targets:
            if engine.lane(engine.opponent(player), int(t["lane"]))["creature"] != null: return t
        return targets[0]
    if engine.spell_target_kind(card_id) == "enemy_creature":
        var best: Dictionary = targets[0]
        var best_power := -1
        for t in targets:
            var foe = engine.lane(int(t["side"]), int(t["lane"]))["creature"]
            if foe != null and int(foe["power"]) > best_power:
                best_power = int(foe["power"])
                best = t
        return best
    return targets[0]
