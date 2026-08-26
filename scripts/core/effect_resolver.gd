class_name EffectResolver
extends RefCounted

func apply(effect: Dictionary, engine, actor: int, pos: Vector2i, secondary: Vector2i = Vector2i(-1, -1)) -> Array:
    var events: Array = []
    var kind := String(effect.get("kind", ""))
    var amount := int(effect.get("amount", 0))
    var target := String(effect.get("target", ""))
    var tile: Dictionary = engine.board.get_tile(pos)
    match kind:
        "add_state":
            var state := String(effect.get("state", ""))
            if state != "" and engine.board.add_state(pos, state):
                events.append({"type":"state_added","state":state,"pos":pos,"actor":actor})
        "damage_unit":
            if not tile.is_empty():
                var unit = tile.get("creature")
                if unit != null and (target != "enemy_on_tile" or int(unit.get("owner", -1)) != actor):
                    unit["health"] = int(unit.get("health", 0)) - amount
                    events.append({"type":"unit_damaged","amount":amount,"pos":pos,"actor":actor})
                    if int(unit["health"]) <= 0:
                        var dead: Dictionary = unit.duplicate(true)
                        tile["creature"] = null
                        engine.players[int(dead.get("owner", -1))]["graveyard"].append(String(dead.get("card_id", "")))
                        events.append({"type":"unit_died","unit":dead,"pos":pos,"actor":actor})
        "damage_heart":
            var victim := 1 - actor if target == "enemy" else actor
            engine.players[victim]["heart"] = max(0, int(engine.players[victim]["heart"]) - amount)
            events.append({"type":"heart_damaged","player":victim,"amount":amount,"actor":actor})
        "heal_heart":
            var who := actor if target == "self" else 1 - actor
            var before := int(engine.players[who]["heart"])
            engine.players[who]["heart"] = min(30, before + amount)
            events.append({"type":"heart_healed","player":who,"amount":int(engine.players[who]["heart"])-before,"actor":actor})
        "draw":
            for _i in range(amount): engine.draw_card(actor)
            events.append({"type":"draw","player":actor,"amount":amount})
        "gain_wonder":
            engine.players[actor]["wonder"] = int(engine.players[actor]["wonder"]) + amount
            events.append({"type":"wonder","player":actor,"amount":amount})
        "gain_aether":
            engine.grant_aether(actor, amount)
            events.append({"type":"aether","player":actor,"amount":amount})
        "buff_unit":
            if not tile.is_empty():
                var unit = tile.get("creature")
                if unit != null and (target not in ["friendly_on_tile","self_unit"] or int(unit.get("owner", -1)) == actor):
                    var p := int(effect.get("power", 0)); var h := int(effect.get("health", 0))
                    unit["power"] = int(unit.get("power",0)) + p
                    unit["health"] = int(unit.get("health",0)) + h
                    unit["max_health"] = int(unit.get("max_health",unit["health"])) + h
                    events.append({"type":"unit_buffed","player":actor,"power":p,"health":h,"pos":pos})
        "transform_terrain":
            if not tile.is_empty():
                tile["terrain"] = String(effect.get("terrain","neutral"))
                tile["owner"] = actor
                events.append({"type":"terrain_changed","player":actor,"terrain":tile["terrain"],"pos":pos})
        "summon_token":
            if not tile.is_empty() and tile.get("creature") == null:
                var token: Dictionary = engine.db.get_token(String(effect.get("token_id","")))
                if not token.is_empty():
                    tile["creature"] = engine.make_unit_from_token(token, actor)
                    tile["owner"] = actor
                    events.append({"type":"token_summoned","player":actor,"token_id":token.get("id",""),"pos":pos})
        "resurrect_last":
            var gy: Array = engine.players[actor]["graveyard"]
            if not gy.is_empty():
                var cid := String(gy.pop_back())
                engine.players[actor]["hand"].append(cid)
                events.append({"type":"returned_from_grave","player":actor,"card_id":cid})
        "move_unit":
            # The caster picks the destination; the simulation checks it is legal.
            if not tile.is_empty() and engine.board.in_bounds(secondary):
                var subject = tile.get("creature")
                var wanted_enemy := target == "enemy_on_tile"
                if subject != null and (not wanted_enemy or int(subject.get("owner", -1)) != actor):
                    if engine.legal_push_targets(pos).has(secondary):
                        var dest: Dictionary = engine.board.get_tile(secondary)
                        tile["creature"] = null
                        dest["creature"] = subject
                        events.append({"type":"unit_pushed","player":actor,"from":pos,"to":secondary,"unit":subject})
    return events
