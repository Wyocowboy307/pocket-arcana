class_name MatchEngine
extends Node

signal state_changed
signal event_emitted(event: Dictionary)
signal match_finished(winner: int)

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
var rng := RandomNumberGenerator.new()
var selected_seed := 424242
var event_log: Array[String] = []

func setup(content: ContentDatabase, deck0_id: String = "starter_life", deck1_id: String = "starter_fire") -> void:
    db = content
    combo.setup(db.recipes, db.terrain_attunement)
    rng.seed = selected_seed
    board.reset()
    players = [_make_player(db.get_deck(deck0_id)), _make_player(db.get_deck(deck1_id))]
    _seed_sanctuary_terrain(0)
    _seed_sanctuary_terrain(1)
    for p in range(2):
        _shuffle_deck(players[p]["deck"])
        for _i in range(8): draw_card(p)
    chapter = 1
    starting_player = 0
    current_player = 0
    _start_chapter(false)

func _make_player(deck_def: Dictionary) -> Dictionary:
    var deck: Array = []
    for entry in deck_def.get("cards",[]):
        for _i in range(int(entry.get("count",0))): deck.append(String(entry.get("card_id","")))
    return {"heart":25,"seals":0,"wonder":0,"deck":deck,"hand":[],"discard":[],"graveyard":[],"commander_id":String(deck_def.get("commander_id","")),"passed":false,"commander_used":false,"turns_taken":0,"max_aether":3,"aether":3,"chapter_flags":{}}

func _shuffle_deck(deck: Array) -> void:
    for i in range(deck.size()-1,0,-1):
        var j := rng.randi_range(0,i)
        var tmp=deck[i]; deck[i]=deck[j]; deck[j]=tmp

func _seed_sanctuary_terrain(player: int) -> void:
    var pos := Vector2i(3,4) if player==0 else Vector2i(3,0)
    var cmd := db.get_commander(String(players[player]["commander_id"]))
    var el := String(cmd.get("element","life"))
    var info: Dictionary = db.elements.get(el,{})
    board.shape(player,pos,String(info.get("terrain","grove")))

func _start_chapter(draw_between: bool = true) -> void:
    for p in range(2):
        players[p]["passed"] = false
        players[p]["commander_used"] = false
        players[p]["chapter_flags"] = {}
        players[p]["turns_taken"] = 0
        players[p]["max_aether"] = min(10, 3 + chapter)
        players[p]["aether"] = players[p]["max_aether"]
        if draw_between:
            for _i in range(3 if chapter==2 else 2): draw_card(p)
        _dispatch_commander_trigger(p,"on_chapter_start",{})
    current_player = starting_player
    _log("Chapter %d begins." % chapter)
    state_changed.emit()

func draw_card(player: int) -> void:
    var deck: Array = players[player]["deck"]
    if deck.is_empty(): return
    players[player]["hand"].append(deck.pop_back())

func has_attunement(player: int, required) -> bool:
    if required is not Array or required.is_empty(): return true
    var owned: Array[String] = []
    for row in board.tiles:
        for tile in row:
            if int(tile.get("owner",-1)) != player: continue
            var terrain := String(tile.get("terrain","neutral"))
            for el in db.terrain_attunement.get(terrain,[]):
                if not owned.has(String(el)): owned.append(String(el))
    for el in required:
        if not owned.has(String(el)): return false
    return true

func legal_targets_for_card(player: int, card_id: String) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    var card := db.get_card(card_id)
    if card.is_empty(): return out
    var typ := String(card.get("type",""))
    for y in range(BoardModel.HEIGHT):
        for x in range(BoardModel.WIDTH):
            var pos := Vector2i(x,y); var tile := board.get_tile(pos)
            if typ == "creature" and int(tile.get("owner",-1))==player and tile.get("creature")==null: out.append(pos)
            elif typ == "landmark" and int(tile.get("owner",-1))==player and tile.get("landmark")==null: out.append(pos)
            elif typ in ["spell","terrain","relic"]: out.append(pos)
    return out

func play_card(player: int, card_id: String, pos: Vector2i) -> Dictionary:
    if not _can_act(player): return _fail("It is not your turn.")
    var p: Dictionary = players[player]
    if not p["hand"].has(card_id): return _fail("That card is not in your hand.")
    var card := db.get_card(card_id)
    if card.is_empty(): return _fail("Card data is missing.")
    if int(card.get("cost",0)) > int(p["aether"]): return _fail("Not enough Aether.")
    if not has_attunement(player, card.get("attunement",[])): return _fail("Shape the needed element first.")
    if not legal_targets_for_card(player,card_id).has(pos): return _fail("That card cannot go there.")
    p["aether"] = int(p["aether"]) - int(card.get("cost",0))
    p["hand"].erase(card_id)
    var tile := board.get_tile(pos)
    var typ := String(card.get("type",""))
    if typ == "creature":
        tile["creature"] = make_unit_from_card(card,player); tile["owner"] = player
        _emit({"type":"creature_summoned","player":player,"card_id":card_id,"pos":pos})
    elif typ == "landmark":
        tile["landmark"] = {"card_id":card_id,"name":card.get("name",card_id),"owner":player,"presence":int(card.get("presence",1))}; tile["owner"] = player
        _emit({"type":"landmark_built","player":player,"card_id":card_id,"pos":pos})
    for effect in card.get("effects",[]): _apply_and_followups(effect,player,pos)
    if typ in ["spell","terrain","relic"]: p["discard"].append(card_id)
    _dispatch_commander_trigger(player,"on_first_card_played",{"card":card})
    _log("P%d played %s." % [player+1,String(card.get("name",card_id))])
    _check_victory_or_finish_action(player)
    return {"ok":true}

func terrain_for_element(element: String) -> String:
    var info: Dictionary = db.elements.get(element, {})
    return String(info.get("terrain", ""))

func can_shape_with_element(player: int, element: String, pos: Vector2i) -> bool:
    var terrain := terrain_for_element(element)
    if terrain == "": return false
    return board.can_shape(player, pos, terrain)

func shape(player: int, element: String, pos: Vector2i) -> Dictionary:
    if not _can_act(player): return _fail("It is not your turn.")
    var info: Dictionary = db.elements.get(element,{})
    if info.is_empty(): return _fail("Unknown element.")
    if not board.shape(player,pos,String(info.get("terrain","neutral"))): return _fail("Shape next to your realm.")
    _emit({"type":"shape","player":player,"element":element,"pos":pos})
    _log("P%d shaped %s." % [player+1,String(info.get("name",element))])
    _finish_action(player)
    return {"ok":true}

func use_commander(player: int, pos: Vector2i) -> Dictionary:
    if not _can_act(player): return _fail("It is not your turn.")
    if bool(players[player]["commander_used"]): return _fail("Command already used this Chapter.")
    var cmd := db.get_commander(String(players[player]["commander_id"]))
    for effect in cmd.get("command",{}).get("effects",[]): _apply_and_followups(effect,player,pos)
    players[player]["commander_used"] = true
    _emit({"type":"commander","player":player,"commander_id":cmd.get("id",""),"pos":pos})
    _log("P%d used %s's Command." % [player+1,String(cmd.get("name","Commander"))])
    _check_victory_or_finish_action(player)
    return {"ok":true}

func move_or_attack(player: int, from: Vector2i, to: Vector2i) -> Dictionary:
    if not _can_act(player): return _fail("It is not your turn.")
    if not board.neighbors(from).has(to): return _fail("Move only one tile at a time.")
    var src := board.get_tile(from); var dst := board.get_tile(to)
    var unit = src.get("creature")
    if unit == null or int(unit.get("owner",-1)) != player: return _fail("Pick one of your creatures.")
    var enemy = dst.get("creature")
    if enemy == null:
        src["creature"] = null; dst["creature"] = unit; dst["owner"] = player
        _emit({"type":"unit_moved","player":player,"from":from,"to":to})
        _dispatch_commander_trigger(player,"on_unit_move",{"unit":unit})
    elif int(enemy.get("owner",-1)) != player:
        var my_power := int(unit.get("power",0)); var their_power := int(enemy.get("power",0))
        unit["health"] = int(unit.get("health",0)) - their_power
        enemy["health"] = int(enemy.get("health",0)) - my_power
        _emit({"type":"combat","player":player,"from":from,"to":to,"my_damage":their_power,"enemy_damage":my_power})
        _clean_dead_on_tile(from); _clean_dead_on_tile(to)
    else: return _fail("That tile already has your creature.")
    # A creature standing adjacent to the enemy Sanctuary can attack the Heart instead by clicking the Sanctuary tile.
    if int(dst.get("sanctuary_owner",-1)) == 1-player and enemy == null:
        players[1-player]["heart"] = max(0,int(players[1-player]["heart"])-int(unit.get("power",0)))
        _emit({"type":"heart_attack","player":player,"amount":int(unit.get("power",0))})
    _check_victory_or_finish_action(player)
    return {"ok":true}

func pass_chapter(player: int) -> Dictionary:
    if not _can_act(player): return _fail("It is not your turn.")
    players[player]["passed"] = true
    _log("P%d passed." % (player+1))
    if bool(players[1-player]["passed"]): _resolve_chapter()
    else:
        current_player = 1-player
        _begin_turn(current_player)
    state_changed.emit()
    return {"ok":true}

func make_unit_from_card(card: Dictionary, owner: int) -> Dictionary:
    var unit := {"uid":board.next_unit_id,"card_id":card.get("id",""),"name":card.get("name",""),"owner":owner,"power":int(card.get("power",0)),"health":int(card.get("health",1)),"max_health":int(card.get("health",1))}
    board.next_unit_id += 1
    return unit

func make_unit_from_token(token: Dictionary, owner: int) -> Dictionary:
    var out={"uid":board.next_unit_id,"card_id":"token:"+String(token.get("id","")),"name":token.get("name","Token"),"owner":owner,"power":int(token.get("power",1)),"health":int(token.get("health",1)),"max_health":int(token.get("health",1))}
    board.next_unit_id += 1
    return out

func _clean_dead_on_tile(pos: Vector2i) -> void:
    var tile := board.get_tile(pos); var unit=tile.get("creature")
    if unit!=null and int(unit.get("health",0))<=0:
        var owner:=int(unit.get("owner",-1)); players[owner]["graveyard"].append(String(unit.get("card_id",""))); tile["creature"]=null
        _emit({"type":"unit_died","unit":unit,"pos":pos})
        _dispatch_commander_trigger(owner,"on_unit_death",{"unit":unit})

func _apply_and_followups(effect: Dictionary, actor: int, pos: Vector2i) -> void:
    for event in effects.apply(effect,self,actor,pos):
        _emit(event)
        if String(event.get("type",""))=="state_added": _dispatch_commander_trigger(actor,"on_first_state_added",event)
        if String(event.get("type",""))=="unit_died": _dispatch_commander_trigger(int(event.get("unit",{}).get("owner",actor)),"on_unit_death",event)
    for event in combo.resolve_tile(board,pos):
        if int(event.get("wonder",0))>0: players[actor]["wonder"]+=int(event["wonder"])
        _emit(event)

func _dispatch_commander_trigger(player: int, trigger: String, context: Dictionary) -> void:
    var cmd := db.get_commander(String(players[player]["commander_id"]))
    var passive: Dictionary = cmd.get("passive",{})
    if String(passive.get("trigger","")) != trigger: return
    var flag := "passive:"+trigger
    if bool(passive.get("once_per_chapter",false)) and bool(players[player]["chapter_flags"].get(flag,false)): return
    for cond in passive.get("conditions",[]):
        if String(cond.get("kind",""))=="card_element":
            var card: Dictionary = context.get("card", {})
            if not card.get("elements", []).has(cond.get("element")):
                return
        elif String(cond.get("kind",""))=="state_is" and String(context.get("state","")) != String(cond.get("state","")): return
    players[player]["chapter_flags"][flag]=true
    for effect in passive.get("effects",[]): _apply_and_followups(effect,player,Vector2i(3,4) if player==0 else Vector2i(3,0))
    _emit({"type":"commander_passive","player":player,"commander_id":cmd.get("id","")})

func _can_act(player: int) -> bool:
    return not match_over and current_player==player and not bool(players[player]["passed"])

func _finish_action(player: int) -> void:
    players[player]["turns_taken"] = int(players[player]["turns_taken"]) + 1
    var other:=1-player
    if bool(players[other]["passed"]): current_player=player
    else: current_player=other
    _begin_turn(current_player)
    state_changed.emit()

func _begin_turn(player: int) -> void:
    players[player]["max_aether"] = min(10, 3 + chapter + int(players[player]["turns_taken"]))
    players[player]["aether"] = players[player]["max_aether"]

func _check_victory_or_finish_action(player: int) -> void:
    if int(players[1-player]["heart"])<=0:
        _finish_match(player,"Heart broken")
    elif int(players[player]["wonder"])>=10:
        _finish_match(player,"Wonder completed")
    else: _finish_action(player)

func _resolve_chapter() -> void:
    var a:=board.realm_score(0); var b:=board.realm_score(1)
    _log("Chapter %d score: %d–%d." % [chapter,a,b])
    if a>b: players[0]["seals"]+=1; _log("P1 wins the Chapter.")
    elif b>a: players[1]["seals"]+=1; _log("P2 wins the Chapter.")
    else: _log("The Chapter is a tie. No Seal awarded.")
    if int(players[0]["seals"])>=2: _finish_match(0,"Two Chapter Seals"); return
    if int(players[1]["seals"])>=2: _finish_match(1,"Two Chapter Seals"); return
    chapter += 1
    if chapter>3:
        var winner:=0 if int(players[0]["heart"])+a >= int(players[1]["heart"])+b else 1
        _finish_match(winner,"Final tiebreak"); return
    board.clear_creatures_for_new_chapter()
    starting_player=1-starting_player
    _start_chapter(true)

func _finish_match(winner: int, reason: String) -> void:
    match_over=true; _log("P%d wins: %s." % [winner+1,reason]); match_finished.emit(winner); state_changed.emit()

func _emit(event: Dictionary) -> void:
    event_emitted.emit(event)

func _log(text: String) -> void:
    event_log.append(text)
    if event_log.size()>20: event_log.pop_front()

func _fail(reason: String) -> Dictionary:
    return {"ok":false,"reason":reason}
