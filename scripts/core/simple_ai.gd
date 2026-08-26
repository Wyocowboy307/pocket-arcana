class_name SimpleAI
extends RefCounted

func choose_action(engine, player: int) -> Dictionary:
    var p: Dictionary = engine.players[player]
    # Play the highest-cost legal card we can place.
    var hand: Array = p.get("hand", [])
    var candidates: Array = []
    for card_id in hand:
        var card := engine.db.get_card(String(card_id))
        if int(card.get("cost",99)) <= int(p.get("aether",0)) and engine.has_attunement(player, card.get("attunement",[])):
            candidates.append(card)
    candidates.sort_custom(func(a,b): return int(a.get("cost",0)) > int(b.get("cost",0)))
    for card in candidates:
        var pos := _first_playable_tile(engine, player, card)
        if pos.x >= 0:
            return {"kind":"play_card","card_id":card["id"],"pos":pos}
    # Shape toward the center using the Commander's element.
    var commander := engine.db.get_commander(String(p.get("commander_id","")))
    var el := String(commander.get("element","life"))
    for y in range(BoardModel.HEIGHT):
        for x in range(BoardModel.WIDTH):
            var pos := Vector2i(x,y)
            if engine.board.can_shape(player,pos):
                return {"kind":"shape","element":el,"pos":pos}
    return {"kind":"pass"}

func _first_playable_tile(engine, player: int, card: Dictionary) -> Vector2i:
    var typ := String(card.get("type",""))
    for y in range(BoardModel.HEIGHT):
        for x in range(BoardModel.WIDTH):
            var pos := Vector2i(x,y)
            var tile := engine.board.get_tile(pos)
            if int(tile.get("owner",-1)) != player: continue
            if typ == "creature" and tile.get("creature") == null: return pos
            if typ == "landmark" and tile.get("landmark") == null: return pos
            if typ in ["spell","terrain","relic"]: return pos
    return Vector2i(-1,-1)
